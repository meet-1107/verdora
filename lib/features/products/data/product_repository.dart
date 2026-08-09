import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/product.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(firestoreProvider));
});

class ProductRepository {
  ProductRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Collections.products);

  Stream<List<Product>> watchProducts(String companyId) {
    return _col.where('companyId', isEqualTo: companyId).snapshots().map(
        (s) => s.docs.map((d) => Product.fromMap(d.id, d.data())).toList());
  }

  /// Creates a product and returns the new document id (needed to attach
  /// variants).
  Future<String> create(Product product) async {
    final ref = await _col.add(product.toMap());
    return ref.id;
  }

  Future<void> update(Product product) =>
      _col.doc(product.id).update(product.toMap());

  Future<void> archive(String id) =>
      _col.doc(id).update({'status': 'archived'});

  Future<void> delete(String id) => _col.doc(id).delete();
}
