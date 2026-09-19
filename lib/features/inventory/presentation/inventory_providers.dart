import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../products/domain/variant.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory_transaction.dart';

final allVariantsProvider = StreamProvider<List<Variant>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref
      .watch(inventoryRepositoryProvider)
      .watchAllVariants(user.companyId);
});

final lowStockVariantsProvider = Provider<List<Variant>>((ref) {
  final all = ref.watch(allVariantsProvider).valueOrNull ?? const [];
  return all.where((v) => v.isLowStock).toList();
});

/// One-shot cleanup that resets any negative stock cache to zero. Watched once
/// when the admin shell mounts.
final zeroNegativeStockProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return;
  await ref.read(inventoryRepositoryProvider).zeroNegativeStock(user.companyId);
});

final variantTransactionsProvider =
    StreamProvider.family<List<InventoryTransaction>, String>((ref, variantId) {
  return ref.watch(inventoryRepositoryProvider).watchTransactions(variantId);
});

/// Every stock entry in the company (newest first) — for the entries screen.
final companyInventoryTxnsProvider =
    StreamProvider<List<InventoryTransaction>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref
      .watch(inventoryRepositoryProvider)
      .watchCompanyTransactions(user.companyId);
});
