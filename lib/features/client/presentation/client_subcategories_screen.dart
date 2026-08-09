import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_cart_fab.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_skeleton_loader.dart';
import '../../../core/widgets/app_subcategory_card.dart';
import '../../../core/widgets/app_subcategory_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../categories/domain/category.dart';
import '../../products/presentation/product_providers.dart';
import '../../subcategories/domain/subcategory.dart';
import '../../subcategories/presentation/subcategory_providers.dart';
import '../application/cart_provider.dart';
import 'client_cart_screen.dart';
import 'client_catalog_screen.dart';

enum _Sort { alphabetical, mostProducts }

/// Subcategory drill-down: category context, quick reorder, and a list of
/// product families with counts. UI redesign only; reads existing providers.
class ClientSubcategoriesScreen extends ConsumerStatefulWidget {
  const ClientSubcategoriesScreen({super.key, required this.category});
  final Category category;

  @override
  ConsumerState<ClientSubcategoriesScreen> createState() =>
      _ClientSubcategoriesScreenState();
}

class _ClientSubcategoriesScreenState
    extends ConsumerState<ClientSubcategoriesScreen> {
  final _search = TextEditingController();
  String _query = '';
  _Sort _sort = _Sort.alphabetical;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final subsAsync = ref.watch(subcategoriesProvider);
    final products = ref.watch(productsProvider).valueOrNull ?? const [];
    final cartCount = ref.watch(cartItemCountProvider);

    // Counts (UI aggregation from existing providers).
    final subCounts = <String, int>{};
    var categoryProductCount = 0;
    for (final p in products) {
      if (p.status != 'active' || p.categoryId != category.id) continue;
      categoryProductCount++;
      final sid = p.subcategoryId;
      if (sid != null) subCounts[sid] = (subCounts[sid] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Subcategories'),
            Text(
              category.name,
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
      floatingActionButton:
          AppCartFab(count: cartCount, onTap: () => _openCart(context)),
      body: subsAsync.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(subcategoriesProvider),
        ),
        data: (all) {
          final ofCategory = all
              .where((s) => s.categoryId == category.id && s.isActive)
              .toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.huge),
            children: [
              AppSubcategoryHeader(
                name: category.name,
                imageUrl: category.imageUrl,
                description: category.description.isNotEmpty
                    ? category.description
                    : 'Choose a product family to continue.',
                stats: [
                  ('${ofCategory.length}', 'Subcategories'),
                  ('$categoryProductCount', 'Products'),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: AppSearchBar(
                  controller: _search,
                  hint: 'Search subcategory',
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              if (ofCategory.isEmpty)
                _emptyNoSubcategories(context, category)
              else
                _list(context, ofCategory, subCounts),
            ],
          );
        },
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<Subcategory> subs,
    Map<String, int> counts,
  ) {
    var list = subs;
    if (_query.isNotEmpty) {
      list = list.where((s) => s.name.toLowerCase().contains(_query)).toList();
    }
    list = [...list];
    if (_sort == _Sort.alphabetical) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      list.sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
    }

    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxl),
        child: EmptyView(
          message: 'No subcategories found.\nTry another keyword.',
          icon: Icons.search_off,
          action: FilledButton.tonal(
            onPressed: () => setState(() {
              _search.clear();
              _query = '';
            }),
            child: const Text('Clear search'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AppSectionHeader(
            title: 'Available subcategories',
            action: PopupMenuButton<_Sort>(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: _Sort.alphabetical, child: Text('Alphabetical')),
                PopupMenuItem(
                    value: _Sort.mostProducts, child: Text('Most products')),
              ],
            ),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) {
            final s = list[i];
            return AppSubcategoryCard(
              name: s.name,
              imageUrl: s.imageUrl,
              productCount: counts[s.id] ?? 0,
              onTap: () => _openProducts(context, s),
            );
          },
        ),
      ],
    );
  }

  Widget _emptyNoSubcategories(BuildContext context, Category category) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: EmptyView(
        message: 'No subcategories here yet.\n'
            'Browse all products in ${category.name}.',
        icon: Icons.inventory_2_outlined,
        action: FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                ClientCatalogScreen(initialCategoryId: category.id),
          )),
          icon: const Icon(Icons.storefront_outlined),
          label: const Text('View all products'),
        ),
      ),
    );
  }

  void _openProducts(BuildContext context, Subcategory s) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClientCatalogScreen(
        initialCategoryId: s.categoryId,
        initialSubcategoryId: s.id,
      ),
    ));
  }

  void _openCart(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientCartScreen()),
    );
  }
}
