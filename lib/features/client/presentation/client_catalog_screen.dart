import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_breadcrumb.dart';
import '../../../core/widgets/app_cart_fab.dart';
import '../../../core/widgets/app_lazy_list.dart';
import '../../../core/widgets/app_product_card.dart';
import '../../../core/widgets/app_product_summary.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_skeleton_loader.dart';
import '../../../core/widgets/app_stock_badge.dart';
import '../../../core/widgets/state_views.dart';
import '../../categories/presentation/category_providers.dart';
import '../../discounts/logic/discount_resolver.dart';
import '../../discounts/presentation/discount_providers.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../orders/presentation/order_providers.dart';
import '../../parties/presentation/party_providers.dart';
import '../../products/domain/product.dart';
import '../../products/domain/variant.dart';
import '../../products/presentation/product_providers.dart';
import '../../subcategories/presentation/subcategory_providers.dart';
import '../application/cart_provider.dart';
import 'client_cart_screen.dart';
import 'client_quick_order_screen.dart';

/// Product list — a fast B2B ordering interface (not an e-commerce catalog).
/// Includes a Quick Order Mode for high-volume repeat ordering. UI redesign
/// only; reads existing providers.
class ClientCatalogScreen extends ConsumerStatefulWidget {
  const ClientCatalogScreen({
    super.key,
    this.initialCategoryId,
    this.initialSubcategoryId,
  });

  final String? initialCategoryId;
  final String? initialSubcategoryId;

  @override
  ConsumerState<ClientCatalogScreen> createState() =>
      _ClientCatalogScreenState();
}

class _ClientCatalogScreenState extends ConsumerState<ClientCatalogScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _quickOrder = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static StockStatus _statusFor(List<Variant> vs) {
    final active = vs.where((v) => v.status == 'active').toList();
    if (active.isEmpty) return StockStatus.comingSoon;
    if (!active.any((v) => v.currentStock > 0)) return StockStatus.outOfStock;
    if (!active.any((v) => v.currentStock > 0 && v.currentStock > v.minStock)) {
      return StockStatus.lowStock;
    }
    return StockStatus.inStock;
  }

  // Quick Order Mode: fast in-place variant sheet (no navigation).
  void _openVariants(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VariantPickerSheet(product: product),
    );
  }

  // Browse mode: fast multi-size quick-order grid.
  void _openDetail(Product product) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClientQuickOrderScreen(product: product),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final subs = ref.watch(subcategoriesProvider).valueOrNull ?? const [];
    final productsAsync = ref.watch(productsProvider);
    final allVariants = ref.watch(allVariantsProvider).valueOrNull ?? const [];
    final cartItemCount = ref.watch(cartItemCountProvider);
    final cartVariantIds = ref.watch(cartVariantIdsProvider);
    final orders = ref.watch(clientOrdersProvider).valueOrNull ?? const [];

    // Group variants by product (for counts, stock and search).
    final variantsByProduct = <String, List<Variant>>{};
    for (final v in allVariants) {
      variantsByProduct.putIfAbsent(v.productId, () => []).add(v);
    }

    final catName = _nameFor(categories, _cat);
    final subName = _subName(subs);
    final subtitle = subName ?? catName ?? 'All products';
    final crumbs = ['Home', if (catName != null) catName, if (subName != null) subName];

    final now = DateTime.now();
    final orderedThisMonth = orders
        .where((o) =>
            o.createdAt != null &&
            o.createdAt!.year == now.year &&
            o.createdAt!.month == now.month)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Products'),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _quickOrder ? 'Quick order mode: on' : 'Quick order mode',
            isSelected: _quickOrder,
            onPressed: () => setState(() => _quickOrder = !_quickOrder),
            icon: const Icon(Icons.bolt_outlined),
            selectedIcon: const Icon(Icons.bolt),
          ),
          IconButton(
            tooltip: 'Cart',
            onPressed: _openCart,
            icon: Badge(
              isLabelVisible: cartItemCount > 0,
              label: Text('$cartItemCount'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      floatingActionButton: AppCartFab(count: cartItemCount, onTap: _openCart),
      body: productsAsync.when(
        loading: () => const AppSkeletonList(rowHeight: 96),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(productsProvider)),
        data: (products) {
          // In-scope products (by category/subcategory).
          final scope = products
              .where((p) =>
                  p.status == 'active' &&
                  (_cat == null || p.categoryId == _cat) &&
                  (_subcategoryId == null ||
                      p.subcategoryId == _subcategoryId))
              .toList();
          final scopeVariantCount = scope.fold<int>(
              0, (s, p) => s + (variantsByProduct[p.id]?.length ?? 0));

          // Apply search + quick filter.
          final list = scope.where((p) {
            final vs = variantsByProduct[p.id] ?? const [];
            return _query.isEmpty || _matches(p, vs, _query);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                child: AppBreadcrumb(items: crumbs),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                child: AppSearchBar(
                  controller: _search,
                  hint: 'Search product, size or SKU',
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: AppProductSummary(stats: [
                  ('${scope.length}', 'Products'),
                  ('$scopeVariantCount', 'Sizes'),
                  ('$orderedThisMonth', 'Orders this month'),
                ]),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: list.isEmpty
                    ? _empty()
                    : AppLazyListView<Product>(
                        items: list,
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0,
                            AppSpacing.lg, AppSpacing.huge),
                        separatorHeight: AppSpacing.md,
                        itemBuilder: (context, p, index) {
                          final vs = variantsByProduct[p.id] ?? const [];
                          return AppProductCard(
                            name: p.name,
                            description: p.description,
                            imageUrl: p.imageUrls.isNotEmpty
                                ? p.imageUrls.first
                                : null,
                            variantCount:
                                vs.where((v) => v.status == 'active').length,
                            stock: _statusFor(vs),
                            compact: _quickOrder,
                            inCart:
                                vs.any((v) => cartVariantIds.contains(v.id)),
                            onTap: () => _openDetail(p),
                            onQuickAdd: () => _openVariants(p),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String? get _cat => _catId;
  String? _catId;
  String? _subcategoryId;

  @override
  void initState() {
    super.initState();
    _catId = widget.initialCategoryId;
    _subcategoryId = widget.initialSubcategoryId;
  }

  String? _nameFor(List<dynamic> categories, String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c.name as String;
    }
    return null;
  }

  String? _subName(List<dynamic> subs) {
    if (_subcategoryId == null) return null;
    for (final s in subs) {
      if (s.id == _subcategoryId) return s.name as String;
    }
    return null;
  }

  bool _matches(Product p, List<Variant> vs, String q) {
    if (p.name.toLowerCase().contains(q)) return true;
    for (final v in vs) {
      if ((v.sku ?? '').toLowerCase().contains(q)) return true;
      for (final val in v.attributes.values) {
        if (val.toLowerCase().contains(q)) return true;
      }
    }
    return false;
  }

  Widget _empty() => EmptyView(
        message: _query.isNotEmpty
            ? 'No products match your search.'
            : 'No products available.',
        icon: Icons.inventory_2_outlined,
        action: _query.isNotEmpty
            ? FilledButton.tonal(
                onPressed: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
                child: const Text('Clear search'),
              )
            : null,
      );

  void _openCart() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientCartScreen()),
    );
  }
}

class _VariantPickerSheet extends ConsumerWidget {
  const _VariantPickerSheet({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variants = ref.watch(variantsByProductProvider(product.id));
    final party = ref.watch(currentPartyProvider).valueOrNull;
    final resolver =
        DiscountResolver(ref.watch(discountsProvider).valueOrNull ?? const []);

    double discountFor(String variantId) => resolver.resolve(DiscountContext(
          variantId: variantId,
          productId: product.id,
          categoryId: product.categoryId,
          partyId: party?.id ?? '',
          partyDefaultDiscount: party?.defaultDiscount ?? 0,
        ));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: variants.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(error: e),
          data: (items) {
            final active = items.where((v) => v.status == 'active').toList();
            return ListView(
              controller: controller,
              children: [
                Text(product.name,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                if (active.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: Center(child: Text('No sizes available.')),
                  ),
                for (final v in active)
                  _VariantRow(
                      product: product,
                      variant: v,
                      discountPercent: discountFor(v.id)),
                const SizedBox(height: AppSpacing.lg),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VariantRow extends ConsumerStatefulWidget {
  const _VariantRow({
    required this.product,
    required this.variant,
    required this.discountPercent,
  });
  final Product product;
  final Variant variant;
  final double discountPercent;

  @override
  ConsumerState<_VariantRow> createState() => _VariantRowState();
}

class _VariantRowState extends ConsumerState<_VariantRow> {
  int _qty = 1;

  String get _label => widget.variant.attributes.isEmpty
      ? 'Size'
      : widget.variant.attributes.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');

  @override
  Widget build(BuildContext context) {
    final v = widget.variant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('${Formatters.money(v.rate)} · Pack ${v.pack}'
                      '${widget.discountPercent > 0 ? ' · ${widget.discountPercent}% off' : ''}'),
                ],
              ),
            ),
            _stepper(),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: () {
                ref.read(cartProvider.notifier).addVariant(
                      variantId: v.id,
                      productName: widget.product.name,
                      variantLabel: _label,
                      rate: v.rate,
                      qty: _qty,
                      discountPercent: widget.discountPercent,
                    );
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Added $_qty × ${widget.product.name}')));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepper() {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$_qty'),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _qty++),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
