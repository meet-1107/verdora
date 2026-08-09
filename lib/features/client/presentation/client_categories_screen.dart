import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_cart_fab.dart';
import '../../../core/widgets/app_category_grid_card.dart';
import '../../../core/widgets/app_filter_chip_bar.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_skeleton_loader.dart';
import '../../../core/widgets/state_views.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../../products/presentation/product_providers.dart';
import '../../subcategories/presentation/subcategory_providers.dart';
import '../application/cart_provider.dart';
import 'client_catalog_screen.dart';
import 'client_cart_screen.dart';
import 'client_subcategories_screen.dart';

/// Client Categories — a fast, enterprise-style product-navigation grid
/// (not a marketplace). Reads existing providers only; UI redesign only.
class ClientCategoriesScreen extends ConsumerStatefulWidget {
  const ClientCategoriesScreen({super.key});

  @override
  ConsumerState<ClientCategoriesScreen> createState() =>
      _ClientCategoriesScreenState();
}

class _ClientCategoriesScreenState
    extends ConsumerState<ClientCategoriesScreen> {
  final _search = TextEditingController();
  String _query = '';
  int _filter = 0; // 0 = All, 1 = Favorites
  final Set<String> _favorites = {}; // session-local favourites

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int _columnsFor(double width) {
    if (width >= 1500) return 6;
    if (width >= 1200) return 5;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);
    final products = ref.watch(productsProvider).valueOrNull ?? const [];
    final cartCount = ref.watch(cartItemCountProvider);

    // Product counts per category (UI aggregation from existing provider).
    final counts = <String, int>{};
    for (final p in products) {
      if (p.status != 'active') continue;
      counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Categories'),
            Text(
              categoriesAsync.when(
                data: (c) => '${c.where((e) => e.isActive).length} available',
                loading: () => 'Loading…',
                error: (_, __) => '',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cart',
            onPressed: () => _openCart(context),
            icon: Badge(
              isLabelVisible: cartCount > 0,
              label: Text('$cartCount'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      floatingActionButton: AppCartFab(
        count: cartCount,
        onTap: () => _openCart(context),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: AppSearchBar(
              controller: _search,
              hint: 'Search category',
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: AppFilterChipBar(
              labels: const ['All', 'Favorites'],
              icons: const [Icons.grid_view_rounded, Icons.star_outline],
              selectedIndex: _filter,
              onSelected: (i) => setState(() => _filter = i),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cols = _columnsFor(constraints.maxWidth);
                return categoriesAsync.when(
                  loading: () => AppCategorySkeleton(crossAxisCount: cols),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(categoriesProvider),
                  ),
                  data: (all) {
                    var list = all.where((c) => c.isActive).toList();
                    if (_filter == 1) {
                      list = list
                          .where((c) => _favorites.contains(c.id))
                          .toList();
                    }
                    if (_query.isNotEmpty) {
                      list = list
                          .where((c) =>
                              c.name.toLowerCase().contains(_query))
                          .toList();
                    }
                    if (all.where((c) => c.isActive).isEmpty) {
                      return _emptyCategories();
                    }
                    if (list.isEmpty) {
                      return _emptySearch();
                    }
                    list.sort((a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1400),
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.huge,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: AppSpacing.lg,
                            crossAxisSpacing: AppSpacing.lg,
                            childAspectRatio: 0.95,
                          ),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final c = list[i];
                            return AppCategoryGridCard(
                              name: c.name,
                              imageUrl: c.imageUrl,
                              productCount: counts[c.id] ?? 0,
                              favorite: _favorites.contains(c.id),
                              onTap: () => _openProducts(context, c),
                              onLongPress: () => _showOptions(context, c),
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCategories() => EmptyView(
        message: 'No categories found.\n'
            'No product categories are currently available.',
        icon: Icons.category_outlined,
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(categoriesProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      );

  Widget _emptySearch() => EmptyView(
        message: 'No matching categories.\nTry another keyword.',
        icon: Icons.search_off,
        action: FilledButton.tonal(
          onPressed: () => setState(() {
            _search.clear();
            _query = '';
            _filter = 0;
          }),
          child: const Text('Clear search'),
        ),
      );

  void _openProducts(BuildContext context, Category c) {
    // If the category has active subcategories, drill into them; otherwise go
    // straight to the product list (no "no subcategories" screen).
    final subs = ref.read(subcategoriesProvider).valueOrNull ?? const [];
    final hasSubs = subs.any((s) => s.categoryId == c.id && s.isActive);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => hasSubs
          ? ClientSubcategoriesScreen(category: c)
          : ClientCatalogScreen(initialCategoryId: c.id),
    ));
  }

  void _openCart(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientCartScreen()),
    );
  }

  void _showOptions(BuildContext context, Category c) {
    final isFav = _favorites.contains(c.id);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(c.name, style: Theme.of(context).textTheme.titleLarge),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('View products'),
              onTap: () {
                Navigator.pop(context);
                _openProducts(context, c);
              },
            ),
            ListTile(
              leading: Icon(isFav ? Icons.star : Icons.star_outline),
              title: Text(isFav ? 'Remove from favorites' : 'Add to favorites'),
              onTap: () {
                setState(() {
                  if (isFav) {
                    _favorites.remove(c.id);
                  } else {
                    _favorites.add(c.id);
                  }
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
