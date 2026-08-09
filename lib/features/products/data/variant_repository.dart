import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/variant.dart';

final variantRepositoryProvider = Provider<VariantRepository>((ref) {
  return VariantRepository(ref.watch(firestoreProvider));
});

class VariantRepository {
  VariantRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _variants =>
      _db.collection(Collections.variants);
  CollectionReference<Map<String, dynamic>> get _txns =>
      _db.collection(Collections.inventoryTransactions);

  Stream<List<Variant>> watchByProduct(String productId) {
    return _variants.where('productId', isEqualTo: productId).snapshots().map(
        (s) => s.docs.map((d) => Variant.fromMap(d.id, d.data())).toList());
  }

  /// Creates a variant. If [openingStock] > 0, also records an `opening`
  /// inventory transaction (stock is transaction-derived, never hand-set).
  Future<void> create(Variant variant, {int openingStock = 0}) async {
    final ref = await _variants.add({
      ...variant.toMap(),
      'currentStock': openingStock,
    });
    if (openingStock > 0) {
      await _txns.add({
        'companyId': variant.companyId,
        'variantId': ref.id,
        'type': 'opening',
        'quantity': openingStock,
        'refType': 'manual',
        'note': 'Opening stock',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> update(Variant variant) =>
      _variants.doc(variant.id).update(variant.toMap());

  /// Updates a variant AND, when [newStock] differs from [previousStock], writes
  /// the absolute new stock plus an `adjustment` transaction for the delta so the
  /// inventory ledger stays consistent. Use this when editing a size where the
  /// admin may also change its stock on hand.
  Future<void> updateWithStock(
    Variant variant, {
    required int previousStock,
    required int newStock,
  }) async {
    await _variants.doc(variant.id).update({
      ...variant.toMap(),
      'currentStock': newStock,
    });
    final delta = newStock - previousStock;
    if (delta != 0) {
      await _txns.add({
        'companyId': variant.companyId,
        'variantId': variant.id,
        'type': 'adjustment',
        'quantity': delta,
        'refType': 'manual',
        'note': 'Stock set to $newStock (edited)',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> delete(String id) => _variants.doc(id).delete();

  /// Records a manual stock movement and updates the cached [Variant.currentStock].
  Future<void> adjustStock({
    required Variant variant,
    required int delta,
    required String
        type, // adjustment | purchase | damage | return | correction
    String? note,
  }) async {
    await _txns.add({
      'companyId': variant.companyId,
      'variantId': variant.id,
      'type': type,
      'quantity': delta,
      'refType': 'manual',
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _variants.doc(variant.id).update({
      'currentStock': FieldValue.increment(delta),
    });
  }
}
