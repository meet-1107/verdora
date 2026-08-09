import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/category.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(ref.watch(firestoreProvider));
});

/// Firestore data access for [Category]. Every query is company-scoped.
class CategoryRepository {
  CategoryRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Collections.categories);

  /// Live list of categories for a company, ordered by [Category.sortOrder].
  Stream<List<Category>> watchCategories(String companyId) {
    return _col
        .where('companyId', isEqualTo: companyId)
        .orderBy('sortOrder')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Category.fromMap(d.id, d.data())).toList());
  }

  Future<void> create(Category category) => _col.add(category.toCreateMap());

  Future<void> update(Category category) =>
      _col.doc(category.id).update(category.toUpdateMap());

  /// Soft-delete (archive) keeps referential integrity with products.
  Future<void> archive(String id) =>
      _col.doc(id).update({'status': 'archived'});

  Future<void> delete(String id) => _col.doc(id).delete();
}
