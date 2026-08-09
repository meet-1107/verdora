import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/cart_item.dart';

final cartProvider =
    NotifierProvider<CartNotifier, List<CartItem>>(CartNotifier.new);

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => const [];

  /// Adds [qty] of a variant, merging with an existing line if present.
  void addVariant({
    required String variantId,
    required String productName,
    required String variantLabel,
    required double rate,
    required int qty,
    double discountPercent = 0,
  }) {
    final existing = state.indexWhere((c) => c.variantId == variantId);
    if (existing >= 0) {
      final updated = [...state];
      updated[existing] = updated[existing]
          .copyWith(quantity: updated[existing].quantity + qty);
      state = updated;
    } else {
      state = [
        ...state,
        CartItem(
          variantId: variantId,
          productName: productName,
          variantLabel: variantLabel,
          rate: rate,
          quantity: qty,
          discountPercent: discountPercent,
        ),
      ];
    }
  }

  void setQuantity(String variantId, int qty) {
    if (qty <= 0) {
      remove(variantId);
      return;
    }
    state = [
      for (final c in state)
        if (c.variantId == variantId) c.copyWith(quantity: qty) else c,
    ];
  }

  void remove(String variantId) =>
      state = state.where((c) => c.variantId != variantId).toList();

  void clear() => state = const [];
}

/// The set of variant ids currently in the cart (for "already in cart" marks).
final cartVariantIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(cartProvider).map((c) => c.variantId).toSet();
});

/// Number of distinct items (lines) in the cart — used for the small cart badge
/// (so it shows "how many products added", not the total piece count).
final cartItemCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).length;
});

/// Derived totals for the current cart.
final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold(0, (sum, c) => sum + c.quantity);
});

final cartSubtotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0.0, (sum, c) => sum + c.gross);
});

final cartDiscountProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0.0, (sum, c) => sum + c.discountAmount);
});

final cartTotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0.0, (sum, c) => sum + c.total);
});
