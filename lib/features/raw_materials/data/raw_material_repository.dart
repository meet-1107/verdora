import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
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
      await _logTxn(v.rawMaterialId, ref.id, v.currentStock, 'opening',
          companyId: v.companyId, createdBy: createdBy, note: 'Opening stock');
    }
    return ref.id;
  }

  Future<void> updateVariant(RawMaterialVariant v) =>
      _variants.doc(v.id).update(v.toUpdateMap());

  Future<void> deleteVariant(String id) => _variants.doc(id).delete();

  /// Moves a variant's stock by [delta] and records the movement.
  /// [type] labels the movement — e.g. `production` / `purchase` (stock in),
  /// `return` (stock out). A reduction is clamped so stock never goes below 0.
  Future<void> addVariantStock(RawMaterialVariant v, double delta,
      {String type = 'add', String? note, String? createdBy}) async {
    if (delta == 0) return;
    double applied = delta;
    if (delta < 0) {
      // Clamp a reduction (e.g. a return) so stock never goes negative.
      if (v.currentStock + delta < 0) applied = -v.currentStock;
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
    await _logTxn(v.rawMaterialId, v.id, applied, type,
        companyId: v.companyId, note: note, createdBy: createdBy);
  }

  /// Sets a variant's stock to [newStock] (records the difference), clamped ≥ 0.
  Future<void> setVariantStock(RawMaterialVariant v, double newStock,
      {String? note, String? createdBy}) async {
    final clamped = newStock < 0 ? 0.0 : newStock;
    final delta = clamped - v.currentStock;
    await _variants.doc(v.id).update({
      'currentStock': clamped,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (delta != 0) {
      await _logTxn(v.rawMaterialId, v.id, delta, 'adjust',
          companyId: v.companyId, note: note, createdBy: createdBy);
    }
  }

  Stream<List<RawMaterialTxn>> watchVariantTxns(String variantId) {
    return _txns.where('variantId', isEqualTo: variantId).snapshots().map((s) {
      final list =
          s.docs.map((d) => RawMaterialTxn.fromMap(d.id, d.data())).toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)));
      return list;
    });
  }

  Future<void> _logTxn(
      String rawMaterialId, String variantId, double quantity, String type,
      {required String companyId, String? note, String? createdBy}) {
    return _txns.add({
      'companyId': companyId,
      'rawMaterialId': rawMaterialId,
      'variantId': variantId,
      'quantity': quantity,
      'type': type,
      'note': note,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
