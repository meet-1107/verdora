import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/discount_repository.dart';
import '../domain/discount.dart';

final discountsProvider = StreamProvider<List<Discount>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(discountRepositoryProvider).watchAll(user.companyId);
});
