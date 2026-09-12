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
    return ref.id;
  }

  Future<void> updateVariant(RawMaterialVariant v) =>
      _variants.doc(v.id).update(v.toUpdateMap());

  Future<void> deleteVariant(String id) => _variants.doc(id).delete();

  /// Moves a variant's stock by [delta]. [type]/[note]/[createdBy] are accepted
  /// for call-site compatibility but no movement history is stored (kept out of
  /// the database intentionally). A reduction is clamped so stock never goes
  /// below 0.
  Future<void> addVariantStock(RawMaterialVariant v, double delta,
      {String type = 'add', String? note, String? createdBy}) async {
    if (delta == 0) return;
    if (delta < 0) {
      // Clamp a reduction (e.g. a return) so stock never goes negative.
      final applied = v.currentStock + delta < 0 ? -v.currentStock : delta;
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
  }

  /// Sets a variant's stock to [newStock], clamped ≥ 0. No history is stored.
  Future<void> setVariantStock(RawMaterialVariant v, double newStock,
      {String? note, String? createdBy}) async {
    final clamped = newStock < 0 ? 0.0 : newStock;
    await _variants.doc(v.id).update({
      'currentStock': clamped,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
