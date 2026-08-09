import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/subcategory.dart';

final subcategoryRepositoryProvider = Provider<SubcategoryRepository>((ref) {
  return SubcategoryRepository(ref.watch(firestoreProvider));
});

class SubcategoryRepository {
  SubcategoryRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Collections.subcategories);

  Stream<List<Subcategory>> watchAll(String companyId) {
    return _col
        .where('companyId', isEqualTo: companyId)
        .orderBy('sortOrder')
        .snapshots()
        .map((s) =>
            s.docs.map((d) => Subcategory.fromMap(d.id, d.data())).toList());
  }

  Future<void> create(Subcategory s) => _col.add(s.toCreateMap());
  Future<void> update(Subcategory s) => _col.doc(s.id).update(s.toUpdateMap());
  Future<void> archive(String id) =>
      _col.doc(id).update({'status': 'archived'});
  Future<void> delete(String id) => _col.doc(id).delete();
}
