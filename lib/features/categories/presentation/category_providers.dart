import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/category_repository.dart';
import '../domain/category.dart';

/// Live categories for the signed-in user's company.
final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(categoryRepositoryProvider).watchCategories(user.companyId);
});
