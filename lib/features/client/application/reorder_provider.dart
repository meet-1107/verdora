import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../orders/domain/order.dart' show OrderItem;
import '../../orders/presentation/order_providers.dart';

/// A frequently-ordered variant surfaced for one-tap reordering.
class ReorderItem {
  const ReorderItem({
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.rate,
    required this.count,
  });

  final String variantId;
  final String productName;
  final String variantLabel;
  final double rate;
  final int count;
}

Iterable<List<T>> _chunk<T>(List<T> list, int size) sync* {
  for (var i = 0; i < list.length; i += size) {
    yield list.sublist(i, i + size > list.length ? list.length : i + size);
  }
}

/// Aggregates the signed-in client's most-frequently-ordered variants from
/// their recent orders' line items. Read-only; used by the Quick Reorder strip.
final frequentlyOrderedProvider =
    FutureProvider<List<ReorderItem>>((ref) async {
  final orders = ref.watch(clientOrdersProvider).valueOrNull ?? const [];
  if (orders.isEmpty) return const [];

  // Look at the most recent orders only (keeps the query small).
  final recentIds = orders.take(20).map((o) => o.id).toList();
  final db = ref.watch(firestoreProvider);

  final items = <OrderItem>[];
  for (final chunk in _chunk(recentIds, 30)) {
    final snap = await db
        .collection(Collections.orderItems)
        .where('orderId', whereIn: chunk)
        .get();
    items.addAll(snap.docs.map((d) => OrderItem.fromMap(d.id, d.data())));
  }

  final counts = <String, int>{};
  final latest = <String, OrderItem>{};
  for (final it in items) {
    if (it.variantId.isEmpty) continue;
    counts[it.variantId] = (counts[it.variantId] ?? 0) + 1;
    latest[it.variantId] = it;
  }

  final result = latest.values
      .map((it) => ReorderItem(
            variantId: it.variantId,
            productName: it.productName,
            variantLabel: it.variantLabel,
            rate: it.rate,
            count: counts[it.variantId] ?? 1,
          ))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  return result.take(10).toList();
});
