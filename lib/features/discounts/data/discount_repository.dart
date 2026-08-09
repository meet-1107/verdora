import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/discount.dart';

final discountRepositoryProvider = Provider<DiscountRepository>((ref) {
  return DiscountRepository(ref.watch(firestoreProvider));
});

class DiscountRepository {
  DiscountRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Collections.discounts);

  Stream<List<Discount>> watchAll(String companyId) {
    return _col.where('companyId', isEqualTo: companyId).snapshots().map(
        (s) => s.docs.map((d) => Discount.fromMap(d.id, d.data())).toList());
  }

  Future<void> create(Discount d) => _col.add(d.toMap());

  Future<void> update(Discount d) => _col.doc(d.id).update({
        'scope': d.scope.value,
        'percent': d.percent,
        'targetId': d.targetId,
        'targetLabel': d.targetLabel,
        'partyId': d.partyId,
        'status': d.status,
      });

  Future<void> delete(String id) => _col.doc(id).delete();
}
