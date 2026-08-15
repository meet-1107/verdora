import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_bottom_order_bar.dart';
import '../../../core/widgets/app_product_summary.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../categories/presentation/category_providers.dart';
import '../../discounts/logic/discount_resolver.dart';
import '../../discounts/presentation/discount_providers.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../subcategories/presentation/subcategory_providers.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/domain/order.dart';
import '../../orders/domain/order_status.dart';
import '../../orders/presentation/order_providers.dart';
import '../../parties/presentation/party_providers.dart';
import '../../products/domain/product.dart';
import '../../products/domain/variant.dart';
import '../../products/presentation/product_providers.dart';
import '../application/cart_provider.dart';
import '../domain/cart_item.dart';
import 'client_categories_screen.dart';
import 'client_checkout_preview_screen.dart';

/// Order Summary — a professional B2B order review (labelled "Order Summary" in
/// the UI even though the file stays `cart_screen`). Review, edit quantities
/// (including a Bulk Edit mode), remove/duplicate, see discounts and totals,
/// add a note, then proceed. Cart/order/discount logic is unchanged.
class ClientCartScreen extends ConsumerStatefulWidget {
  const ClientCartScreen({super.key});

  @override
  ConsumerState<ClientCartScreen> createState() => _ClientCartScreenState();
}

class _ClientCartScreenState extends ConsumerState<ClientCartScreen> {
  bool _savingDraft = false;
  bool _repeating = false;
  bool _bulkEdit = false;
  final _notes = TextEditingController();
  final _bulkControllers = <String, TextEditingController>{};
  final Set<String> _expanded = {}; // expanded product groups (by product id)

  @override
  void dispose() {
    _notes.dispose();
    for (final c in _bulkControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _bulkCtrl(CartItem item) {
    return _bulkControllers.putIfAbsent(
      item.variantId,
      () => TextEditingController(text: '${item.quantity}'),
    );
  }

  // ---------------------------------------------------------------------------
  // Final review + submit happens on the Checkout Preview screen.
  void _goCheckout() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ClientCheckoutPreviewScreen(initialNote: _notes.text),
    ));
  }

  Future<void> _saveDraft() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    final party = ref.read(orderPartyProvider);
    if (user == null || party == null) {
      _snack('No party selected for this order.');
      return;
    }
    setState(() => _savingDraft = true);
    try {
      final order = Order(
        id: '',
        companyId: user.companyId,
        partyId: party.id,
        partyName: party.name,
        status: OrderStatus.draft,
        subtotal: ref.read(cartSubtotalProvider),
        discountTotal: ref.read(cartDiscountProvider),
        grandTotal: ref.read(cartTotalProvider),
        itemCount: cart.length,
        note: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      final items = [
        for (final c in cart)
          OrderItem(
            id: '',
            companyId: user.companyId,
            orderId: '',
            variantId: c.variantId,
            productName: c.productName,
            variantLabel: c.variantLabel,
            rate: c.rate,
            quantity: c.quantity,
            discountPercent: c.discountPercent,
          ),
      ];
      await ref.read(orderRepositoryProvider).createOrder(
            order: order,
            items: items,
            clientCode: party.partyCode.isEmpty ? party.id : party.partyCode,
          );
      ref.read(cartProvider.notifier).clear();
      if (mounted) {
        Navigator.pop(context);
        _snack('Saved as draft.');
      }
    } catch (e) {
      _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  Future<void> _repeatLast() async {
    final orders = ref.read(clientOrdersProvider).valueOrNull ?? const [];
    if (orders.isEmpty) return;
    setState(() => _repeating = true);
    try {
      final items =
          await ref.read(orderRepositoryProvider).watchItems(orders.first.id).first;
      for (final it in items) {
        ref.read(cartProvider.notifier).addVariant(
              variantId: it.variantId,
              productName: it.productName,
              variantLabel: it.variantLabel,
              rate: it.rate,
              qty: it.quantity,
              discountPercent: it.discountPercent,
            );
      }
      _snack('Loaded ${items.length} item(s) from your last order.');
    } catch (e) {
      _snack('Could not load last order: $e');
    } finally {
      if (mounted) setState(() => _repeating = false);
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear order?'),
        content: const Text('Remove all items from this order?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) ref.read(cartProvider.notifier).clear();
  }

  void _addMore() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ClientCategoriesScreen()),
      );

  void _removeWithUndo(CartItem item) {
    ref.read(cartProvider.notifier).remove(item.variantId);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed ${item.productName}'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => ref.read(cartProvider.notifier).addVariant(
                variantId: item.variantId,
                productName: item.productName,
                variantLabel: item.variantLabel,
                rate: item.rate,
                qty: item.quantity,
                discountPercent: item.discountPercent,
              ),
        ),
      ));
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Widget _sectionHeader(String title, {required bool category}) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          left: category ? 0 : 8, top: category ? 4 : 8, bottom: 6),
      child: Row(
        children: [
          Icon(category ? Icons.folder_rounded : Icons.account_tree_rounded,
              size: category ? 18 : 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (category
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.titleSmall)
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Two-stage discount: (1) subtract each product's specific discount per line,
  /// then (2) subtract the party's global % from the resulting total.
  ({
    double subtotal,
    double productDiscount,
    double globalPercent,
    double globalDiscount,
    double grandTotal,
  }) _recompute() {
    final cart = ref.read(cartProvider);
    final party = ref.read(orderPartyProvider);
    final resolver =
        DiscountResolver(ref.read(discountsProvider).valueOrNull ?? const []);
    final variants =
        ref.read(allVariantsProvider).valueOrNull ?? const <Variant>[];
    final products =
        ref.read(productsProvider).valueOrNull ?? const <Product>[];
    final variantById = {for (final v in variants) v.id: v};
    final productById = {for (final p in products) p.id: p};

    var subtotal = 0.0, productDiscount = 0.0, afterProduct = 0.0;
    for (final c in cart) {
      var specific = 0.0;
      final v = variantById[c.variantId];
      final p = v != null ? productById[v.productId] : null;
      if (v != null && p != null) {
        specific = resolver.resolveSpecific(DiscountContext(
          variantId: v.id,
          productId: p.id,
          categoryId: p.categoryId,
          subcategoryId: p.subcategoryId ?? '',
          partyId: party?.id ?? '',
        ));
      }
      final gross = c.rate * c.quantity;
      final lineDisc = gross * specific / 100;
      subtotal += gross;
      productDiscount += lineDisc;
      afterProduct += gross - lineDisc;
    }
    final globalPct = party?.defaultDiscount ?? 0;
    final globalDiscount = afterProduct * globalPct / 100;
    return (
      subtotal: subtotal,
      productDiscount: productDiscount,
      globalPercent: globalPct,
      globalDiscount: globalDiscount,
      grandTotal: afterProduct - globalDiscount,
    );
  }

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    // Watch the discount inputs so totals refresh live.
    ref.watch(orderPartyProvider);
    ref.watch(discountsProvider);
    ref.watch(allVariantsProvider);
    ref.watch(productsProvider);
    final hasHistory =
        (ref.watch(clientOrdersProvider).valueOrNull ?? const []).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Order Summary'),
            Text(
              '${cart.length} product(s) selected',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          if (cart.isNotEmpty) ...[
            IconButton(
              tooltip: 'Bulk edit quantities',
              isSelected: _bulkEdit,
              onPressed: () => setState(() => _bulkEdit = !_bulkEdit),
              icon: const Icon(Icons.edit_outlined),
              selectedIcon: const Icon(Icons.edit),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'more':
                    _addMore();
                  case 'draft':
                    _saveDraft();
                  case 'repeat':
                    _repeatLast();
                  case 'clear':
                    _deleteAll();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'more', child: Text('Add more products')),
                const PopupMenuItem(
                    value: 'draft', child: Text('Save as draft')),
                if (hasHistory)
                  const PopupMenuItem(
                      value: 'repeat', child: Text('Repeat last order')),
                const PopupMenuItem(value: 'clear', child: Text('Clear order')),
              ],
            ),
          ],
        ],
      ),
      body: cart.isEmpty
          ? _emptyState(hasHistory)
          : Column(
              children: [
                Expanded(child: _content(cart)),
                AppBottomOrderBar(
                  totalLabel: 'Final amount',
                  totalValue: Formatters.money(_recompute().grandTotal),
                  actionLabel: 'Proceed to Checkout',
                  onAction: _goCheckout,
                ),
              ],
            ),
    );
  }

  Widget _content(List<CartItem> cart) {
    final totalQty = ref.watch(cartCountProvider);
    // Re-resolve discounts against the current party + rules.
    final t = _recompute();

    // Weight lookup — cart items don't store weight; resolve it from variants.
    final variants =
        ref.watch(allVariantsProvider).valueOrNull ?? const <Variant>[];
    final variantsById = {for (final v in variants) v.id: v};

    // Per-piece weight normalised to GRAMS so gm + kg lines sum correctly.
    double gramsFor(String variantId) {
      final v = variantsById[variantId];
      if (v == null) return 0;
      final w = double.tryParse(v.attributes['Weight'] ?? '') ?? 0;
      final unit = (v.attributes['Weight Unit'] ?? '').trim().toLowerCase();
      return unit == 'kg' ? w * 1000 : w;
    }

    // Group by product name, preserving first-seen order (for the summary stat).
    final groups = <String, List<CartItem>>{};
    for (final item in cart) {
      groups.putIfAbsent(item.productName, () => <CartItem>[]).add(item);
    }

    // Length lookup (cart items don't store length).
    String lengthOf(CartItem c) {
      final v = variantsById[c.variantId];
      if (v == null) return '-';
      final l = (v.attributes['Length'] ?? '').trim();
      final lu = (v.attributes['Length Unit'] ?? '').trim();
      if (l.isEmpty) return '-';
      return lu.isEmpty ? l : '$l $lu';
    }

    // Size value WITHOUT its unit (e.g. "1", "3/4"); falls back to the label.
    String sizeOf(CartItem c) {
      final v = variantsById[c.variantId];
      final s = (v?.attributes['Size'] ?? '').trim();
      return s.isEmpty ? c.variantLabel : s;
    }

    // Category → Subcategory → Product tree for the grouped view.
    final products = ref.watch(productsProvider).valueOrNull ?? const <Product>[];
    final productById = {for (final p in products) p.id: p};
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final catName = {for (final c in cats) c.id: c.name};
    final subcats = ref.watch(subcategoriesProvider).valueOrNull ?? const [];
    final subName = {for (final s in subcats) s.id: s.name};

    final itemsByProduct = <String, List<CartItem>>{};
    final unknown = <String, List<CartItem>>{}; // productName -> items (no match)
    for (final c in cart) {
      final v = variantsById[c.variantId];
      final p = v != null ? productById[v.productId] : null;
      if (p == null) {
        unknown.putIfAbsent(c.productName, () => []).add(c);
      } else {
        itemsByProduct.putIfAbsent(p.id, () => []).add(c);
      }
    }
    final tree = <String, Map<String, List<String>>>{};
    for (final pid in itemsByProduct.keys) {
      final p = productById[pid]!;
      tree
          .putIfAbsent(p.categoryId, () => {})
          .putIfAbsent(p.subcategoryId ?? '', () => [])
          .add(pid);
    }

    // Grand total weight — shown in kg once it reaches 1000 g.
    double totalGrams = 0;
    for (final item in cart) {
      totalGrams += gramsFor(item.variantId) * item.quantity;
    }
    final totalWeightText = totalGrams <= 0
        ? '-'
        : totalGrams >= 1000
            ? '${_fmtWeight(totalGrams / 1000)} kg'
            : '${_fmtWeight(totalGrams)} gm';

    // Build the grouped, collapsible product list (Category → Subcategory).
    _CartProductGroup group(String id, String name, List<CartItem> items) =>
        _CartProductGroup(
          productName: name,
          items: items,
          lengthOf: lengthOf,
          sizeOf: sizeOf,
          expanded: _expanded.contains(id),
          onToggle: () => setState(() =>
              _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id)),
          onRemove: _removeWithUndo,
        );

    final grouped = <Widget>[];
    final catIds = tree.keys.toList()
      ..sort((a, b) => (catName[a] ?? '')
          .toLowerCase()
          .compareTo((catName[b] ?? '').toLowerCase()));
    for (final catId in catIds) {
      grouped.add(_sectionHeader(catName[catId] ?? 'Category', category: true));
      final subMap = tree[catId]!;
      final subIds = subMap.keys.toList()
        ..sort((a, b) {
          if (a.isEmpty) return 1;
          if (b.isEmpty) return -1;
          return (subName[a] ?? '')
              .toLowerCase()
              .compareTo((subName[b] ?? '').toLowerCase());
        });
      for (final subId in subIds) {
        if (subId.isNotEmpty) {
          grouped.add(
              _sectionHeader(subName[subId] ?? 'Subcategory', category: false));
        }
        final pids = subMap[subId]!
          ..sort((a, b) => productById[a]!
              .name
              .toLowerCase()
              .compareTo(productById[b]!.name.toLowerCase()));
        for (final pid in pids) {
          grouped.add(Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: group(pid, productById[pid]!.name, itemsByProduct[pid]!),
          ));
        }
      }
    }
    for (final e in unknown.entries) {
      grouped.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: group(e.key, e.key, e.value),
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
      children: [
        AppProductSummary(stats: [
          ('${groups.length}', 'Products'),
          (Formatters.qty(totalQty), 'Quantity'),
          (Formatters.money(t.grandTotal), 'Estimated total'),
        ]),
        const SizedBox(height: AppSpacing.xl),
        if (_bulkEdit)
          for (final item in cart)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _BulkRow(
                item: item,
                controller: _bulkCtrl(item),
                onChanged: (q) => ref
                    .read(cartProvider.notifier)
                    .setQuantity(item.variantId, q),
              ),
            )
        else
          ...grouped,
        const SizedBox(height: AppSpacing.sm),
        _TotalsCard(
          totalQty: totalQty,
          totalWeightText: totalWeightText,
          subtotal: t.subtotal,
          productDiscount: t.productDiscount,
          globalPercent: t.globalPercent,
          globalDiscount: t.globalDiscount,
          finalAmount: t.grandTotal,
        ),
        const SizedBox(height: AppSpacing.xl),
        TextField(
          controller: _notes,
          maxLines: 3,
          maxLength: 250,
          decoration: const InputDecoration(
            labelText: 'Order note (optional)',
            hintText: 'e.g. Deliver urgently',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _addMore,
          icon: const Icon(Icons.add),
          label: const Text('Continue shopping'),
        ),
        if (_savingDraft)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _emptyState(bool hasHistory) {
    return EmptyView(
      message: 'No products added.\nBrowse products and start building your '
          'order.',
      icon: Icons.shopping_cart_outlined,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _addMore,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Browse categories'),
          ),
          if (hasHistory) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _repeating ? null : _repeatLast,
              icon: _repeating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.history),
              label: const Text('Repeat last order'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Trims trailing zeros from a weight value (e.g. 12.0 -> "12", 12.5 -> "12.5").
String _fmtWeight(double w) {
  if (w == w.roundToDouble()) return w.toStringAsFixed(0);
  return w.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

/// Order totals with a clear discount breakdown: Total amount → Discount → the
/// prominent Final amount, plus a savings line.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.totalQty,
    required this.totalWeightText,
    required this.subtotal,
    required this.productDiscount,
    required this.globalPercent,
    required this.globalDiscount,
    required this.finalAmount,
  });
  final int totalQty;
  final String totalWeightText;
  final double subtotal;
  final double productDiscount;
  final double globalPercent;
  final double globalDiscount;
  final double finalAmount;

  static const _green = Color(0xFF16A34A);

  static String _pct(double p) => p == p.roundToDouble()
      ? p.toStringAsFixed(0)
      : p.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalSaved = productDiscount + globalDiscount;
    Widget line(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text(value,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          line('Total quantity', Formatters.qty(totalQty)),
          line('Total weight', totalWeightText),
          const Divider(height: AppSpacing.lg),
          line('Total amount', Formatters.money(subtotal)),
          if (productDiscount > 0)
            line('Product discount', '− ${Formatters.money(productDiscount)}',
                color: _green),
          if (globalDiscount > 0)
            line('Cash discount (${_pct(globalPercent)}%)',
                '− ${Formatters.money(globalDiscount)}',
                color: _green),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text('Final amount',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(Formatters.money(finalAmount),
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, color: scheme.primary)),
              ],
            ),
          ),
          if (totalSaved > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.savings_outlined, size: 18, color: _green),
                const SizedBox(width: 6),
                Text('You saved ${Formatters.money(totalSaved)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: _green, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A product group: a bold product-name header followed by one editable line
/// per variant (Size · Qty · Weight · Amount), each with a quantity stepper and
/// a delete action.
/// A collapsible product group: tap the product name to reveal a Size · Length ·
/// Rate · Qty · Amount table for its lines (with quantity steppers + delete).
class _CartProductGroup extends StatelessWidget {
  const _CartProductGroup({
    required this.productName,
    required this.items,
    required this.lengthOf,
    required this.sizeOf,
    required this.expanded,
    required this.onToggle,
    required this.onRemove,
  });

  final String productName;
  final List<CartItem> items;
  final String Function(CartItem item) lengthOf;
  final String Function(CartItem item) sizeOf;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(CartItem item) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = items.fold<double>(0, (s, c) => s + c.rate * c.quantity);
    final qty = items.fold<int>(0, (s, c) => s + c.quantity);

    return Card(
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(productName,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                            '${items.length} size(s) · ${Formatters.qty(qty)} pcs',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Text(Formatters.money(total),
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary)),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Builder(builder: (context) {
                    final showLength = items.any((c) => lengthOf(c) != '-');
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                      child: Column(
                        children: [
                          _CartTableHeader(showLength: showLength),
                          for (final c in items)
                            _CartLineRow(
                              item: c,
                              size: sizeOf(c),
                              length: lengthOf(c),
                              showLength: showLength,
                              onRemove: onRemove,
                            ),
                        ],
                      ),
                    );
                  })
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _CartTableHeader extends StatelessWidget {
  const _CartTableHeader({required this.showLength});
  final bool showLength;
  static const _style = TextStyle(
      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Expanded(flex: 3, child: Text('SIZE', style: _style)),
          if (showLength)
            const Expanded(flex: 3, child: Text('LENGTH', style: _style)),
          const Expanded(flex: 3, child: Text('RATE', style: _style)),
          const Expanded(flex: 4, child: Text('QTY', style: _style)),
          const Expanded(flex: 3, child: Text('AMOUNT', style: _style)),
          const SizedBox(width: 30),
        ],
      ),
    );
  }
}

class _CartLineRow extends StatelessWidget {
  const _CartLineRow({
    required this.item,
    required this.size,
    required this.length,
    required this.showLength,
    required this.onRemove,
  });
  final CartItem item;
  final String size;
  final String length;
  final bool showLength;
  final void Function(CartItem item) onRemove;

  Widget _val(String text, int flex, {bool bold = false, Color? color}) =>
      Expanded(
        flex: flex,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(text,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: color)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _val(size, 3, bold: true, color: scheme.onSurface),
          if (showLength) _val(length, 3, color: scheme.onSurfaceVariant),
          _val(Formatters.money(item.rate), 3),
          _val(Formatters.qty(item.quantity), 4, bold: true),
          _val(Formatters.money(item.rate * item.quantity), 3,
              bold: true, color: scheme.primary),
          SizedBox(
            width: 30,
            child: IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
              onPressed: () => onRemove(item),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact bulk-edit row: product + a numeric quantity field.
class _BulkRow extends StatelessWidget {
  const _BulkRow({
    required this.item,
    required this.controller,
    required this.onChanged,
  });

  final CartItem item;
  final TextEditingController controller;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium),
                  Text(item.variantLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            SizedBox(
              width: 96,
              child: TextField(
                controller: controller,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Qty',
                ),
                onChanged: (v) => onChanged(int.tryParse(v.trim()) ?? 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
