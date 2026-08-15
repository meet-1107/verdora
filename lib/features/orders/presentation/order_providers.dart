import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/order_repository.dart';
import '../domain/order.dart';

/// Orders for the signed-in client's party.
final clientOrdersProvider = StreamProvider<List<Order>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final partyId = user?.partyId;
  if (partyId == null) return Stream.value(const []);
  return ref.watch(orderRepositoryProvider).watchForParty(partyId);
});

/// All orders for the company (admin).
final companyOrdersProvider = StreamProvider<List<Order>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(orderRepositoryProvider).watchForCompany(user.companyId);
});

final orderItemsProvider =
    StreamProvider.family<List<OrderItem>, String>((ref, orderId) {
  return ref.watch(orderRepositoryProvider).watchItems(orderId);
});

/// All line items across the company (admin only — used for reports & backup).
final companyOrderItemsProvider = StreamProvider<List<OrderItem>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(orderRepositoryProvider).watchAllItems(user.companyId);
});
