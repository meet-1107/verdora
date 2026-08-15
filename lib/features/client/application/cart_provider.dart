import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/presentation/auth_providers.dart';
import '../domain/cart_item.dart';

final cartProvider =
    NotifierProvider<CartNotifier, List<CartItem>>(CartNotifier.new);

/// The client's shopping cart. Persisted to local storage (per signed-in user)
/// so a partly-built order survives closing the app — on the next launch the
/// same products are still in the cart.
class CartNotifier extends Notifier<List<CartItem>> {
  String? _uid;

  @override
  List<CartItem> build() {
    // Rebuilds when the signed-in user changes, so each dealer keeps their own
    // saved cart and it clears on sign-out.
    _uid = ref.watch(currentUserProvider).valueOrNull?.uid;
    _restore(_uid);
    return const [];
  }

  String _key(String? uid) => 'client_cart_${uid ?? 'anon'}';

  Future<void> _restore(String? uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(uid));
      if (raw == null || raw.isEmpty) return;
      final saved = (jsonDecode(raw) as List)
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList();
      // Only apply if this is still the same user and nothing was added in the
      // meantime (avoid clobbering a just-added item during async load).
      if (_uid == uid && state.isEmpty && saved.isNotEmpty) {
        state = saved;
      }
    } catch (_) {
      // Corrupt/incompatible saved cart — ignore.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key(_uid), jsonEncode(state.map((c) => c.toJson()).toList()));
    } catch (_) {}
  }

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
    _persist();
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
    _persist();
  }

  void remove(String variantId) {
    state = state.where((c) => c.variantId != variantId).toList();
    _persist();
  }

  void clear() {
    state = const [];
    _persist();
  }
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
