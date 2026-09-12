import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/raw_material.dart';

final rawMaterialRepositoryProvider = Provider<RawMaterialRepository>((ref) {
  return RawMaterialRepository(ref.watch(firestoreProvider));
});

class RawMaterialRepository {
  RawMaterialRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Collections.rawMaterials);
  CollectionReference<Map<String, dynamic>> get _txns =>
      _db.collection(Collections.rawMaterialTransactions);

  Stream<List<RawMaterial>> watchAll(String companyId) {
    return _col.where('companyId', isEqualTo: companyId).snapshots().map(
        (s) => s.docs.map((d) => RawMaterial.fromMap(d.id, d.data())).toList());
  }

  /// Movements for one material, newest first (sorted client-side to avoid a
  /// composite index).
  Stream<List<RawMaterialTxn>> watchTxns(String rawMaterialId) {
    return _txns.where('rawMaterialId', isEqualTo: rawMaterialId).snapshots().map(
      (s) {
        final list =
            s.docs.map((d) => RawMaterialTxn.fromMap(d.id, d.data())).toList();
        list.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));
        return list;
      },
    );
  }

  Future<String> add(RawMaterial rm, {String? createdBy}) async {
    final ref = await _col.add(rm.toCreateMap());
    if (rm.currentStock != 0) {
      await _logTxn(ref.id, rm.currentStock, 'opening',
          companyId: rm.companyId, createdBy: createdBy, note: 'Opening stock');
    }
    return ref.id;
  }

  Future<void> update(RawMaterial rm) => _col.doc(rm.id).update(rm.toUpdateMap());

  Future<void> delete(String id) => _col.doc(id).delete();

  /// Adds [delta] to the material's stock and records the movement.
  Future<void> addStock(RawMaterial rm, double delta,
      {String? note, String? createdBy}) async {
    if (delta == 0) return;
    await _col.doc(rm.id).update({
      'currentStock': FieldValue.increment(delta),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _logTxn(rm.id, delta, 'add',
        companyId: rm.companyId, note: note, createdBy: createdBy);
  }

  /// Sets the material's stock to [newStock] (records the difference).
  Future<void> setStock(RawMaterial rm, double newStock,
      {String? note, String? createdBy}) async {
    final clamped = newStock < 0 ? 0.0 : newStock;
    final delta = clamped - rm.currentStock;
    await _col.doc(rm.id).update({
      'currentStock': clamped,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (delta != 0) {
      await _logTxn(rm.id, delta, 'adjust',
          companyId: rm.companyId, note: note, createdBy: createdBy);
    }
  }

  Future<void> _logTxn(String rawMaterialId, double quantity, String type,
      {required String companyId, String? note, String? createdBy}) {
    return _txns.add({
      'companyId': companyId,
      'rawMaterialId': rawMaterialId,
      'quantity': quantity,
      'type': type,
      'note': note,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
