import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../products/domain/variant.dart';
import '../domain/inventory_transaction.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(firestoreProvider));
});

class InventoryRepository {
  InventoryRepository(this._db);

  final FirebaseFirestore _db;

  /// Every variant in the company (used for the inventory list).
  Stream<List<Variant>> watchAllVariants(String companyId) {
    return _db
        .collection(Collections.variants)
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map(
            (s) => s.docs.map((d) => Variant.fromMap(d.id, d.data())).toList());
  }

  /// Every stock movement in the company (used to reconstruct historical stock
  /// for backups). One-time fetch.
  Future<List<InventoryTransaction>> allTransactions(String companyId) async {
    final snap = await _db
        .collection(Collections.inventoryTransactions)
        .where('companyId', isEqualTo: companyId)
        .get();
    return snap.docs
        .map((d) => InventoryTransaction.fromMap(d.id, d.data()))
        .toList();
  }

  /// Every stock movement in the company (newest first, sorted client-side to
  /// avoid a composite index). Used by the entries screen.
  Stream<List<InventoryTransaction>> watchCompanyTransactions(
      String companyId) {
    return _db
        .collection(Collections.inventoryTransactions)
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => InventoryTransaction.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)));
      return list;
    });
  }

  /// Transaction history for a single variant, newest first.
  Stream<List<InventoryTransaction>> watchTransactions(String variantId) {
    return _db
        .collection(Collections.inventoryTransactions)
        .where('variantId', isEqualTo: variantId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => InventoryTransaction.fromMap(d.id, d.data()))
            .toList());
  }

  /// One-time cleanup: any variant whose cached stock drifted below zero is
  /// reset to zero. Cheap — only negative docs match. Safe to call repeatedly.
  Future<void> zeroNegativeStock(String companyId) async {
    // Single-field inequality (auto-indexed); single-company deployment.
    final snap = await _db
        .collection(Collections.variants)
        .where('currentStock', isLessThan: 0)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'currentStock': 0});
    }
    await batch.commit();
  }

  /// Records a stock movement and updates the variant's cached currentStock.
  Future<void> record({
    required Variant variant,
    required int delta,
    required InventoryTxnType type,
    String? note,
    String? createdBy,
  }) async {
    await _db.collection(Collections.inventoryTransactions).add({
      'companyId': variant.companyId,
      'variantId': variant.id,
      'type': type.value,
      'quantity': delta,
      'refType': 'manual',
      'note': note,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _db
        .collection(Collections.variants)
        .doc(variant.id)
        .update({'currentStock': FieldValue.increment(delta)});
  }
}
