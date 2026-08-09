import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/subcategory_repository.dart';
import '../domain/subcategory.dart';

/// All subcategories for the current company.
final subcategoriesProvider = StreamProvider<List<Subcategory>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(subcategoryRepositoryProvider).watchAll(user.companyId);
});

/// Subcategories filtered to a single parent category.
final subcategoriesByCategoryProvider =
    Provider.family<List<Subcategory>, String>((ref, categoryId) {
  final all = ref.watch(subcategoriesProvider).valueOrNull ?? const [];
  return all.where((s) => s.categoryId == categoryId).toList();
});
