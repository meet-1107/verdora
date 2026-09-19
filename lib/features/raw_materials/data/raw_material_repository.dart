import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../products/domain/variant.dart' show BomLine;
import '../domain/raw_material.dart';
import '../domain/raw_material_variant.dart';

final rawMaterialRepositoryProvider = Provider<RawMaterialRepository>((ref) {
  return RawMaterialRepository(ref.watch(firestoreProvider));
});

class RawMaterialRepository {
  RawMaterialRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _materials =>
      _db.collection(Collections.rawMaterials);
  CollectionReference<Map<String, dynamic>> get _variants =>
      _db.collection(Collections.rawMaterialVariants);
  CollectionReference<Map<String, dynamic>> get _txns =>
      _db.collection(Collections.rawMaterialTransactions);

  // ---- materials (parents) --------------------------------------------
  Stream<List<RawMaterial>> watchAll(String companyId) {
    return _materials.where('companyId', isEqualTo: companyId).snapshots().map(
        (s) => s.docs.map((d) => RawMaterial.fromMap(d.id, d.data())).toList());
  }

  Future<String> addMaterial(RawMaterial rm) async {
    final ref = await _materials.add(rm.toCreateMap());
    return ref.id;
  }

  Future<void> updateMaterial(RawMaterial rm) =>
      _materials.doc(rm.id).update(rm.toUpdateMap());

  /// Deletes a material and all of its variants in one batch.
  Future<void> deleteMaterial(String id) async {
    final vs = await _variants.where('rawMaterialId', isEqualTo: id).get();
    final batch = _db.batch();
    for (final d in vs.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_materials.doc(id));
    await batch.commit();
  }

  // ---- variants -------------------------------------------------------
  /// All raw-material variants for a company (grouped by rawMaterialId in the
  /// UI). One stream keeps things simple and index-free.
  Stream<List<RawMaterialVariant>> watchVariants(String companyId) {
    return _variants.where('companyId', isEqualTo: companyId).snapshots().map(
        (s) =>
            s.docs.map((d) => RawMaterialVariant.fromMap(d.id, d.data())).toList());
  }

  Future<String> addVariant(RawMaterialVariant v, {String? createdBy}) async {
    final ref = await _variants.add(v.toCreateMap());
    if (v.currentStock != 0) {
      await _logTxn(v, ref.id, v.currentStock, 'opening', note: 'Opening stock');
    }
    return ref.id;
  }

  Future<void> updateVariant(RawMaterialVariant v) =>
      _variants.doc(v.id).update(v.toUpdateMap());

  Future<void> deleteVariant(String id) => _variants.doc(id).delete();

  /// Moves a variant's stock by [delta] and records an entry. A reduction is
  /// clamped so stock never goes below 0.
  Future<void> addVariantStock(RawMaterialVariant v, double delta,
      {String type = 'add', String? note, String? createdBy}) async {
    if (delta == 0) return;
    double applied = delta;
    if (delta < 0) {
      // Clamp a reduction (e.g. a return) so stock never goes negative.
      applied = v.currentStock + delta < 0 ? -v.currentStock : delta;
      if (applied == 0) return;
      await _variants.doc(v.id).update({
        'currentStock': v.currentStock + applied,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _variants.doc(v.id).update({
        'currentStock': FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await _logTxn(v, v.id, applied, type, note: note);
  }

  /// Sets a variant's stock to [newStock], clamped ≥ 0. Records an `adjust`.
  Future<void> setVariantStock(RawMaterialVariant v, double newStock,
      {String? note, String? createdBy}) async {
    final clamped = newStock < 0 ? 0.0 : newStock;
    final delta = clamped - v.currentStock;
    await _variants.doc(v.id).update({
      'currentStock': clamped,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (delta != 0) {
      await _logTxn(v, v.id, delta, 'adjust', note: note);
    }
  }

  /// Consumes raw materials for [bom] to make [qty] units of a product. Each
  /// line's [BomLine.qty] is in the raw material's own unit, so consumption =
  /// line.qty * qty (clamped ≥ 0). Records a `consume` entry per variant.
  Future<void> consumeForBom(List<BomLine> bom, int qty,
      {String? note, String? createdBy}) async {
    if (qty <= 0) return;
    for (final line in bom) {
      if (line.rawVariantId.isEmpty || line.qty <= 0) continue;
      final ref = _variants.doc(line.rawVariantId);
      final snap = await ref.get();
      if (!snap.exists) continue;
      final v = RawMaterialVariant.fromMap(snap.id, snap.data()!);
      final consume = line.qty * qty;
      final newStock = v.currentStock - consume < 0 ? 0.0 : v.currentStock - consume;
      final applied = v.currentStock - newStock; // >= 0
      if (applied <= 0) continue;
      await ref.update({
        'currentStock': newStock,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _logTxn(v, v.id, -applied, 'consume', note: note);
    }
  }

  /// Adds raw materials for [bom] back to stock for [qty] units (the reverse of
  /// [consumeForBom]) — e.g. when a product stock adjustment/return reduces the
  /// product count. Records a `return` entry per variant.
  Future<void> restoreForBom(List<BomLine> bom, int qty,
      {String? note, String? createdBy}) async {
    if (qty <= 0) return;
    for (final line in bom) {
      if (line.rawVariantId.isEmpty || line.qty <= 0) continue;
      final ref = _variants.doc(line.rawVariantId);
      final snap = await ref.get();
      if (!snap.exists) continue;
      final v = RawMaterialVariant.fromMap(snap.id, snap.data()!);
      final add = line.qty * qty;
      await ref.update({
        'currentStock': FieldValue.increment(add),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _logTxn(v, v.id, add, 'return', note: note);
    }
  }

  // ---- entries (history) ----------------------------------------------
  /// Company-wide entries, newest first. [limit] caps the result (0 = all).
  Stream<List<RawMaterialTxn>> watchTxns(String companyId, {int limit = 0}) {
    Query<Map<String, dynamic>> q =
        _txns.where('companyId', isEqualTo: companyId);
    return q.snapshots().map((s) {
      final list =
          s.docs.map((d) => RawMaterialTxn.fromMap(d.id, d.data())).toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)));
      return limit > 0 && list.length > limit ? list.sublist(0, limit) : list;
    });
  }

  Future<void> _logTxn(
      RawMaterialVariant v, String variantId, double quantity, String type,
      {String? note}) {
    return _txns.add({
      'companyId': v.companyId,
      'rawMaterialId': v.rawMaterialId,
      'variantId': variantId,
      'label': v.label,
      'unit': v.unit,
      'quantity': quantity,
      'type': type,
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
