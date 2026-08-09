import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/product_repository.dart';
import '../data/variant_repository.dart';
import '../domain/product.dart';
import '../domain/variant.dart';

final productsProvider = StreamProvider<List<Product>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(productRepositoryProvider).watchProducts(user.companyId);
});

/// Live variants for a given product.
final variantsByProductProvider =
    StreamProvider.family<List<Variant>, String>((ref, productId) {
  return ref.watch(variantRepositoryProvider).watchByProduct(productId);
});
