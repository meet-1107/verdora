import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../subcategories/domain/subcategory.dart';
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

  /// Converts a subcategory into a top-level category. Every product under the
  /// subcategory is reassigned to the new category (its subcategory cleared) —
  /// nothing is deleted.
  Future<void> subcategoryToCategory(Subcategory sub,
      {int sortOrder = 0}) async {
    final newCatRef = _col.doc();
    final ops = <void Function(WriteBatch)>[
      (b) => b.set(newCatRef, {
            'companyId': sub.companyId,
            'name': sub.name,
            'description': sub.description,
            'imageUrl': sub.imageUrl,
            'sortOrder': sortOrder,
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
          }),
    ];
    final prods = await _db
        .collection(Collections.products)
        .where('subcategoryId', isEqualTo: sub.id)
        .get();
    for (final d in prods.docs) {
      ops.add((b) => b.update(d.reference,
          {'categoryId': newCatRef.id, 'subcategoryId': null}));
    }
    ops.add((b) =>
        b.delete(_db.collection(Collections.subcategories).doc(sub.id)));
    await _commitChunked(ops);
  }

  /// Converts a category into a subcategory of [targetCategoryId]. All products
  /// under the category move to the target category — direct products go under
  /// the new subcategory; products already in one of this category's own
  /// subcategories keep that subcategory (which is re-parented to the target).
  /// Nothing is deleted.
  Future<void> categoryToSubcategory(Category cat, String targetCategoryId,
      {int sortOrder = 0}) async {
    final newSubRef = _db.collection(Collections.subcategories).doc();
    final ops = <void Function(WriteBatch)>[
      (b) => b.set(newSubRef, {
            'companyId': cat.companyId,
            'categoryId': targetCategoryId,
            'name': cat.name,
            'description': cat.description,
            'imageUrl': cat.imageUrl,
            'sortOrder': sortOrder,
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
          }),
    ];
    final prods = await _db
        .collection(Collections.products)
        .where('categoryId', isEqualTo: cat.id)
        .get();
    for (final d in prods.docs) {
      final sub = d.data()['subcategoryId'] as String?;
      if (sub == null || sub.isEmpty) {
        ops.add((b) => b.update(d.reference,
            {'categoryId': targetCategoryId, 'subcategoryId': newSubRef.id}));
      } else {
        ops.add(
            (b) => b.update(d.reference, {'categoryId': targetCategoryId}));
      }
    }
    final subs = await _db
        .collection(Collections.subcategories)
        .where('categoryId', isEqualTo: cat.id)
        .get();
    for (final d in subs.docs) {
      ops.add((b) => b.update(d.reference, {'categoryId': targetCategoryId}));
    }
    ops.add((b) => b.delete(_col.doc(cat.id)));
    await _commitChunked(ops);
  }

  /// Commits [ops] in batches of 400 (Firestore's limit is 500 writes/batch).
  Future<void> _commitChunked(List<void Function(WriteBatch)> ops) async {
    const chunk = 400;
    for (var i = 0; i < ops.length; i += chunk) {
      final batch = _db.batch();
      final end = (i + chunk) < ops.length ? (i + chunk) : ops.length;
      for (final op in ops.sublist(i, end)) {
        op(batch);
      }
      await batch.commit();
    }
  }
}
