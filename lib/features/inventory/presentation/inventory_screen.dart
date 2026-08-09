import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../../products/domain/variant.dart';
import '../../products/presentation/product_form_screen.dart';
import '../../products/presentation/product_providers.dart';
import '../../subcategories/domain/subcategory.dart';
import '../../subcategories/presentation/subcategory_providers.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory_transaction.dart';
import 'inventory_providers.dart';

// ---- palette (per the requested design) -----------------------------------
const _kPrimary = Color(0xFF0F4CBA);
const _kSuccess = Color(0xFF16A34A);
const _kWarning = Color(0xFFF59E0B);
const _kDanger = Color(0xFFDC2626);

String _sizeLabel(Variant v) {
  final size = v.attributes['Size'];
  final unit = v.attributes['Size Unit'];
  if (size != null && size.trim().isNotEmpty) {
    if (unit != null && unit.trim().isNotEmpty) return '$size $unit';
    return size;
  }
  if (v.attributes.isEmpty) return 'Size';
  return v.attributes.values.join(' ');
}

/// Length + unit (e.g. "3 mtr"); "-" when not set — distinguishes variants that
/// share a size but differ in length.
String _lengthLabel(Variant v) {
  final l = (v.attributes['Length'] ?? '').trim();
  final lu = (v.attributes['Length Unit'] ?? '').trim();
  if (l.isEmpty) return '-';
  return lu.isEmpty ? l : '$l $lu';
}

bool _hasLength(Variant v) => (v.attributes['Length'] ?? '').trim().isNotEmpty;

/// The size value WITHOUT its unit (e.g. "1", "3/4") for a compact table.
String _sizeValue(Variant v) {
  final s = (v.attributes['Size'] ?? '').trim();
  return s.isEmpty ? _sizeLabel(v) : s;
}

enum _StockState { inStock, low, out }

_StockState _stateFor(Variant v) {
  if (v.currentStock <= 0) return _StockState.out;
  if (v.currentStock <= v.minStock) return _StockState.low;
  return _StockState.inStock;
}

// ---------------------------------------------------------------------------
// Level 1 — Categories (tap a category to open its subcategories)
// ---------------------------------------------------------------------------

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _lowOnly = false; // top-bar toggle: only stock < 500
  String? _openProduct; // expanded product in the low-stock view

  /// Threshold for the quick low-stock filter.
  static const int _lowThreshold = 500;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final products = ref.watch(productsProvider).valueOrNull ?? const [];
    final variants = ref.watch(allVariantsProvider).valueOrNull ?? const [];
    final lowCount = ref.watch(lowStockVariantsProvider).length;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Inventory'),
        actions: [
          // On/off toggle: filter directly to low stock (< 500).
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                Text('Low < 500',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Switch(
                  value: _lowOnly,
                  onChanged: (v) => setState(() {
                    _lowOnly = v;
                    _openProduct = null;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _lowOnly
          ? _lowStockView(products, variants)
          : _categoriesView(categories, products, lowCount),
    );
  }

  // ---- normal categories drill-down view -----------------------------------

  Widget _categoriesView(
      List categories, List products, int lowCount) {
    final countByCat = <String, int>{};
    for (final p in products) {
      countByCat[p.categoryId] = (countByCat[p.categoryId] ?? 0) + 1;
    }
    final q = _query.trim().toLowerCase();
    final cats = [...categories]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final list = q.isEmpty
        ? cats
        : cats.where((c) => c.name.toLowerCase().contains(q)).toList();

    return Column(
      children: [
        _searchBar('Search categories…'),
        if (lowCount > 0) _LowStockBanner(count: lowCount),
        Expanded(
          child: categories.isEmpty
              ? const EmptyView(
                  message: 'No categories yet.\n'
                      'Add categories and products to track inventory.',
                  icon: Icons.inventory_2_outlined,
                )
              : list.isEmpty
                  ? EmptyView(
                      message: 'No categories match “${_query.trim()}”.',
                      icon: Icons.search_off,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final c = list[i] as Category;
                        return _NavTile(
                          icon: Icons.folder_rounded,
                          title: c.name,
                          subtitle: '${countByCat[c.id] ?? 0} product(s)',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  _SubcategoriesInventoryScreen(category: c),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ---- low-stock flat view (stock < 500) -----------------------------------

  Widget _lowStockView(List products, List variants) {
    final varsByProduct = <String, List<Variant>>{};
    for (final v in variants.cast<Variant>()) {
      if (v.status != 'active') continue;
      (varsByProduct[v.productId] ??= []).add(v);
    }
    int stockOf(String pid) => (varsByProduct[pid] ?? const <Variant>[])
        .fold(0, (s, v) => s + v.currentStock);
    int sizesOf(String pid) => (varsByProduct[pid] ?? const <Variant>[]).length;

    // Products that have at least one size below the threshold.
    var low = products.cast<Product>().where((p) {
      final sizes = varsByProduct[p.id] ?? const <Variant>[];
      return sizes.any((v) => v.currentStock < _lowThreshold);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      low = low.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    return Column(
      children: [
        _searchBar('Search low-stock products…'),
        Container(
          width: double.infinity,
          color: _kWarning.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.filter_alt, color: _kWarning, size: 18),
              const SizedBox(width: 8),
              Text('${low.length} product(s) with a size under $_lowThreshold',
                  style: const TextStyle(
                      color: _kWarning, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Expanded(
          child: low.isEmpty
              ? const EmptyView(
                  message: 'Nothing under 500.\nAll stock looks healthy.',
                  icon: Icons.check_circle_outline,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  itemCount: low.length,
                  itemBuilder: (context, i) {
                    final p = low[i];
                    return _ProductCard(
                      product: p,
                      sizes: sizesOf(p.id),
                      stock: stockOf(p.id),
                      expanded: _openProduct == p.id,
                      onToggle: () => setState(() =>
                          _openProduct = _openProduct == p.id ? null : p.id),
                      onEditProduct: () => _openProductForm(p),
                      onAddSize: () => _openProductForm(p),
                      onDelete: () => _confirmDeleteProduct(p),
                      onEditSize: _editStock,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _searchBar(String hint) => Material(
        elevation: 1,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: AppSearchBar(
            controller: _search,
            hint: hint,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
      );

  void _openProductForm(Product p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(existing: p)),
    );
  }

  Future<void> _confirmDeleteProduct(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product'),
        content: Text('Delete “${p.name}” and stop tracking it? '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kDanger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(productRepositoryProvider).delete(p.id);
  }

  void _editStock(Variant v) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditStockSheet(variant: v),
    );
  }
}

// ---------------------------------------------------------------------------
// Level 2 — Subcategories of a category (+ "All products")
// ---------------------------------------------------------------------------

class _SubcategoriesInventoryScreen extends ConsumerWidget {
  const _SubcategoriesInventoryScreen({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subcategoriesByCategoryProvider(category.id));
    final products = ref.watch(productsProvider).valueOrNull ?? const [];
    final catProducts =
        products.where((p) => p.categoryId == category.id).toList();

    int countForSub(String subId) =>
        catProducts.where((p) => p.subcategoryId == subId).length;

    final sorted = [...subs]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    void openProducts(Subcategory? sub) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                _ProductsInventoryScreen(category: category, subcategory: sub),
          ),
        );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      appBar: AppBar(title: Text(category.name)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _NavTile(
            icon: Icons.all_inbox_rounded,
            title: 'All products',
            subtitle: '${catProducts.length} product(s)',
            onTap: () => openProducts(null),
          ),
          for (final s in sorted)
            _NavTile(
              icon: Icons.inventory_2_rounded,
              title: s.name,
              subtitle: '${countForSub(s.id)} product(s)',
              onTap: () => openProducts(s),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Level 3 — Products (with the expandable sizes table)
// ---------------------------------------------------------------------------

class _ProductsInventoryScreen extends ConsumerStatefulWidget {
  const _ProductsInventoryScreen({required this.category, this.subcategory});
  final Category category;
  final Subcategory? subcategory;

  @override
  ConsumerState<_ProductsInventoryScreen> createState() =>
      _ProductsInventoryScreenState();
}

class _ProductsInventoryScreenState
    extends ConsumerState<_ProductsInventoryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _openProduct; // only one product expanded at a time

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subcategory;
    final products = ref.watch(productsProvider).valueOrNull ?? const [];
    final variants = ref.watch(allVariantsProvider).valueOrNull ?? const [];

    final varsByProduct = <String, List<Variant>>{};
    for (final v in variants) {
      if (v.status != 'active') continue;
      (varsByProduct[v.productId] ??= []).add(v);
    }
    int stockOf(String pid) => (varsByProduct[pid] ?? const <Variant>[])
        .fold(0, (s, v) => s + v.currentStock);
    int sizesOf(String pid) => (varsByProduct[pid] ?? const <Variant>[]).length;

    var list = products
        .where((p) => p.categoryId == widget.category.id)
        .where((p) => sub == null || p.subcategoryId == sub.id)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) {
        if (p.name.toLowerCase().contains(q)) return true;
        for (final v in varsByProduct[p.id] ?? const <Variant>[]) {
          if (_sizeLabel(v).toLowerCase().contains(q)) return true;
        }
        return stockOf(p.id).toString().contains(q);
      }).toList();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      appBar: AppBar(title: Text(sub?.name ?? 'All ${widget.category.name}')),
      body: Column(
        children: [
          Material(
            elevation: 1,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: AppSearchBar(
                controller: _search,
                hint: 'Search product, size or stock…',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyView(
                    message: q.isEmpty
                        ? 'No products here yet.'
                        : 'No products match “${_query.trim()}”.',
                    icon: Icons.inventory_2_outlined,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final p = list[i];
                      return _ProductCard(
                        product: p,
                        sizes: sizesOf(p.id),
                        stock: stockOf(p.id),
                        expanded: _openProduct == p.id,
                        onToggle: () => setState(() =>
                            _openProduct = _openProduct == p.id ? null : p.id),
                        onEditProduct: () => _openProductForm(p),
                        onAddSize: () => _openProductForm(p),
                        onDelete: () => _confirmDeleteProduct(p),
                        onEditSize: _editStock,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openProductForm(Product p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(existing: p)),
    );
  }

  Future<void> _confirmDeleteProduct(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product'),
        content: Text('Delete “${p.name}” and stop tracking it? '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kDanger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(productRepositoryProvider).delete(p.id);
  }

  void _editStock(Variant v) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditStockSheet(variant: v),
    );
  }
}

// ---- shared bits -----------------------------------------------------------

class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _kWarning.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kWarning, size: 18),
          const SizedBox(width: 8),
          Text('$count size(s) at or below minimum stock.',
              style: const TextStyle(
                  color: Color(0xFF8A5A00), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Category / subcategory drill-down tile.
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _kPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _kPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.sizes,
    required this.stock,
    required this.expanded,
    required this.onToggle,
    required this.onEditProduct,
    required this.onAddSize,
    required this.onDelete,
    required this.onEditSize,
  });
  final Product product;
  final int sizes;
  final int stock;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEditProduct;
  final VoidCallback onAddSize;
  final VoidCallback onDelete;
  final ValueChanged<Variant> onEditSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onToggle,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.widgets_outlined,
                        color: _kPrimary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [
                              _Badge(
                                text: '$sizes ${sizes == 1 ? 'Size' : 'Sizes'}',
                                fg: _kPrimary,
                                bg: _kPrimary.withValues(alpha: 0.15),
                              ),
                              _Badge(
                                text: 'Stock ${Formatters.qty(stock)}',
                                fg: _kSuccess,
                                bg: _kSuccess.withValues(alpha: 0.15),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _Chevron(expanded: expanded),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (v) {
                        switch (v) {
                          case 'edit':
                            onEditProduct();
                          case 'add':
                            onAddSize();
                          case 'delete':
                            onDelete();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'edit', child: Text('Edit product')),
                        PopupMenuItem(value: 'add', child: Text('Add size')),
                        PopupMenuItem(
                            value: 'delete', child: Text('Delete product')),
                      ],
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
                  ? _SizesTable(
                      product: product,
                      onEditSize: onEditSize,
                      onAddSize: onAddSize,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _SizesTable extends ConsumerWidget {
  const _SizesTable({
    required this.product,
    required this.onEditSize,
    required this.onAddSize,
  });
  final Product product;
  final ValueChanged<Variant> onEditSize;
  final VoidCallback onAddSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allVariantsProvider).valueOrNull ?? const <Variant>[];
    final sizes = all
        .where((v) => v.productId == product.id && v.status == 'active')
        .toList()
      ..sort((a, b) => _sizeLabel(a).compareTo(_sizeLabel(b)));

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${sizes.length} ${sizes.length == 1 ? 'Size' : 'Sizes'} '
              'available',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (sizes.isEmpty)
            _EmptySizes(onAddSize: onAddSize)
          else ...[
            _SizesHeader(showLength: sizes.any(_hasLength)),
            for (final v in sizes)
              _SizeLine(
                  variant: v,
                  showLength: sizes.any(_hasLength),
                  onEdit: () => onEditSize(v)),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onAddSize,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kPrimary,
                side: const BorderSide(color: _kPrimary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add New Size'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SizesHeader extends StatelessWidget {
  const _SizesHeader({required this.showLength});
  final bool showLength;

  static const _style = TextStyle(
      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kPrimary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Expanded(flex: 4, child: Text('SIZE', style: _style)),
          if (showLength)
            const Expanded(flex: 3, child: Text('LENGTH', style: _style)),
          const Expanded(flex: 3, child: Text('STOCK', style: _style)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _SizeLine extends StatelessWidget {
  const _SizeLine({
    required this.variant,
    required this.showLength,
    required this.onEdit,
  });
  final Variant variant;
  final bool showLength;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = _stateFor(variant);
    final (badgeText, fg, bg) = switch (state) {
      _StockState.inStock =>
        ('In Stock', _kSuccess, _kSuccess.withValues(alpha: 0.15)),
      _StockState.low =>
        ('Low Stock', _kWarning, _kWarning.withValues(alpha: 0.15)),
      _StockState.out =>
        ('Out of Stock', _kDanger, _kDanger.withValues(alpha: 0.15)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Text(_sizeValue(variant),
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: scheme.onSurface)),
          ),
          if (showLength)
            Expanded(
              flex: 3,
              child: Text(_lengthLabel(variant),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(Formatters.qty(variant.currentStock),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                const SizedBox(height: 3),
                _Badge(text: badgeText, fg: fg, bg: bg, fontSize: 10),
              ],
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              tooltip: 'Edit stock',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.edit_outlined, size: 18, color: _kPrimary),
              onPressed: onEdit,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySizes extends StatelessWidget {
  const _EmptySizes({required this.onAddSize});
  final VoidCallback onAddSize;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Text('📦', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 8),
          Text('No inventory added',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text('Add your first size to begin tracking stock.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.fg,
    required this.bg,
    this.fontSize = 12,
  });
  final String text;
  final Color fg;
  final Color bg;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: fg, fontWeight: FontWeight.w700, fontSize: fontSize)),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.expanded});
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: const Duration(milliseconds: 200),
      child: Icon(Icons.keyboard_arrow_down_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

// ---- edit-stock bottom sheet (4 types; Adjustment sets the total) ----------

class _EditStockSheet extends ConsumerStatefulWidget {
  const _EditStockSheet({required this.variant});
  final Variant variant;

  @override
  ConsumerState<_EditStockSheet> createState() => _EditStockSheetState();
}

class _EditStockSheetState extends ConsumerState<_EditStockSheet> {
  final _qty = TextEditingController();
  final _note = TextEditingController();
  InventoryTxnType _type = InventoryTxnType.purchase;
  bool _saving = false;

  bool get _isAdjustment => _type == InventoryTxnType.adjustment;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onTypeChanged(InventoryTxnType? t) {
    if (t == null) return;
    setState(() {
      _type = t;
      if (_isAdjustment) {
        _qty.text = widget.variant.currentStock.toString();
      } else {
        _qty.clear();
      }
    });
  }

  Future<void> _save() async {
    final v = widget.variant;
    final entered = int.tryParse(_qty.text.trim());
    if (entered == null) return;
    int delta;
    String? note = _note.text.trim().isEmpty ? null : _note.text.trim();
    if (_isAdjustment) {
      delta = entered - v.currentStock;
      if (delta == 0) {
        if (mounted) Navigator.pop(context);
        return;
      }
      note ??= 'Set to $entered';
    } else {
      if (entered <= 0) return;
      delta = entered;
    }
    setState(() => _saving = true);
    try {
      final uid = ref.read(currentUserProvider).valueOrNull?.uid;
      await ref.read(inventoryRepositoryProvider).record(
            variant: v,
            delta: delta,
            type: _type,
            note: note,
            createdBy: uid,
          );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Update stock · ${_sizeLabel(widget.variant)}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Current stock: ${Formatters.qty(widget.variant.currentStock)}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          DropdownButtonFormField<InventoryTxnType>(
            initialValue: _type,
            decoration: const InputDecoration(
                labelText: 'Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(
                  value: InventoryTxnType.purchase, child: Text('Purchase')),
              DropdownMenuItem(
                  value: InventoryTxnType.production, child: Text('Production')),
              DropdownMenuItem(
                  value: InventoryTxnType.adjustment,
                  child: Text('Adjustment')),
              DropdownMenuItem(
                  value: InventoryTxnType.ret, child: Text('Return')),
            ],
            onChanged: _saving ? null : _onTypeChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText:
                  _isAdjustment ? 'Set total quantity' : 'Quantity to add',
              helperText: _isAdjustment
                  ? 'Stock will be set to this total'
                  : 'Adds to the current stock',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
