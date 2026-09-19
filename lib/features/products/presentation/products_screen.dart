import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_thumb.dart';
import '../../../core/widgets/state_views.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../../import_engine/logic/product_import_config.dart';
import '../../import_engine/logic/product_import_executor.dart';
import '../../import_engine/presentation/import_screen.dart';
import '../../import_engine/presentation/zip_image_import_screen.dart';
import '../../inventory/presentation/inventory_entries_screen.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../inventory/presentation/inventory_screen.dart';
import '../../subcategories/domain/subcategory.dart';
import '../../subcategories/presentation/subcategory_providers.dart';
import '../data/product_repository.dart';
import '../domain/product.dart';
import '../domain/variant.dart';
import 'product_form_screen.dart';
import 'product_providers.dart';

// ---- palette ---------------------------------------------------------------
const _kPrimary = Color(0xFF0F4CBA);
const _kSuccess = Color(0xFF16A34A);
const _kWarning = Color(0xFFF59E0B);
const _kDanger = Color(0xFFDC2626);

enum _Health { inStock, low, out, none }

_Health _healthOf(List<Variant> sizes) {
  if (sizes.isEmpty) return _Health.none;
  final total = sizes.fold(0, (s, v) => s + v.currentStock);
  if (total <= 0) return _Health.out;
  if (sizes.any((v) => v.isLowStock)) return _Health.low;
  return _Health.inStock;
}

String _sizeLabel(Variant v) {
  final size = v.attributes['Size'];
  final unit = v.attributes['Size Unit'];
  if (size != null && size.trim().isNotEmpty) {
    return (unit != null && unit.trim().isNotEmpty) ? '$size $unit' : size;
  }
  if (v.attributes.isEmpty) return 'Size';
  return v.attributes.values.join(' ');
}

/// Length + unit (e.g. "3 mtr"); "-" when not set. Lets the admin tell apart
/// variants that share the same size but differ in length.
String _lengthLabel(Variant v) {
  final l = (v.attributes['Length'] ?? '').trim();
  final lu = (v.attributes['Length Unit'] ?? '').trim();
  if (l.isEmpty) return '-';
  return lu.isEmpty ? l : '$l $lu';
}

bool _hasLength(Variant v) => (v.attributes['Length'] ?? '').trim().isNotEmpty;

/// Weight + unit (e.g. "25 gm"); "-" when not set.
String _weightLabel(Variant v) {
  final w = (v.attributes['Weight'] ?? '').trim();
  final wu = (v.attributes['Weight Unit'] ?? '').trim();
  if (w.isEmpty) return '-';
  return wu.isEmpty ? w : '$w $wu';
}

/// The size value WITHOUT its unit (e.g. "1", "3/4") for a compact table.
String _sizeValue(Variant v) {
  final s = (v.attributes['Size'] ?? '').trim();
  return s.isEmpty ? _sizeLabel(v) : s;
}

// ---------------------------------------------------------------------------
// Level 1 — Categories
// ---------------------------------------------------------------------------

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final products = ref.watch(productsProvider).valueOrNull ?? const [];

    final countByCat = <String, int>{};
    for (final p in products) {
      countByCat[p.categoryId] = (countByCat[p.categoryId] ?? 0) + 1;
    }

    final q = _query.trim().toLowerCase();
    final cats = [...categories]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final list =
        q.isEmpty ? cats : cats.where((c) => c.name.toLowerCase().contains(q)).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Products'),
        actions: [
          IconButton(
            tooltip: 'Stock entries',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const InventoryEntriesScreen())),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import',
            onSelected: (v) {
              final Widget screen = v == 'csv'
                  ? ImportScreen(
                      title: 'Import Products',
                      target: 'products',
                      fields: ProductImportConfig.fields,
                      executorProvider: productImportExecutorProvider,
                    )
                  : const ZipImageImportScreen();
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => screen));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'csv', child: Text('Import products (CSV/Excel)')),
              PopupMenuItem(value: 'zip', child: Text('Import images (ZIP)')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: categories.isEmpty
          ? const EmptyView(
              message: 'No categories yet.\nAdd a category first, then products.',
              icon: Icons.folder_outlined,
            )
          : Column(
              children: [
                _SearchBar(
                  controller: _search,
                  hint: 'Search categories…',
                  onChanged: (v) => setState(() => _query = v),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyView(
                          message: 'No categories match.',
                          icon: Icons.search_off)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final c = list[i];
                            return _NavTile(
                              imageUrl: c.imageUrl,
                              fallbackIcon: Icons.folder_rounded,
                              title: c.name,
                              subtitle: '${countByCat[c.id] ?? 0} product(s)',
                              onTap: () {
                                // No subcategories → go straight to products.
                                final subs =
                                    ref.read(subcategoriesProvider).valueOrNull ??
                                        const [];
                                final hasSubs = subs.any(
                                    (s) => s.categoryId == c.id && s.isActive);
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => hasSubs
                                      ? _SubcategoryProductsScreen(category: c)
                                      : _ProductListScreen(
                                          category: c, subcategory: null),
                                ));
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Level 2 — Subcategories (+ All products)
// ---------------------------------------------------------------------------

class _SubcategoryProductsScreen extends ConsumerWidget {
  const _SubcategoryProductsScreen({required this.category});
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
                _ProductListScreen(category: category, subcategory: sub),
          ),
        );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      appBar: AppBar(title: Text(category.name)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _NavTile(
            fallbackIcon: Icons.all_inbox_rounded,
            title: 'All products',
            subtitle: '${catProducts.length} product(s)',
            onTap: () => openProducts(null),
          ),
          for (final s in sorted)
            _NavTile(
              imageUrl: s.imageUrl,
              fallbackIcon: Icons.account_tree_rounded,
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
// Level 3 — Product list (expandable cards + filter chips)
// ---------------------------------------------------------------------------

class _ProductListScreen extends ConsumerStatefulWidget {
  const _ProductListScreen({required this.category, required this.subcategory});
  final Category category;
  final Subcategory? subcategory;

  @override
  ConsumerState<_ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<_ProductListScreen> {
  final _search = TextEditingController();
  String _query = '';
  _Health? _filter; // null = all
  String? _openProduct;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openEditor({Product? product}) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProductFormScreen(existing: product)),
      );

  Future<void> _confirmDelete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product'),
        content: Text('Delete “${p.name}”? This cannot be undone.'),
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
    try {
      await ref.read(productRepositoryProvider).delete(p.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Product deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
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

    var base = products
        .where((p) => p.categoryId == widget.category.id)
        .where((p) => sub == null || p.subcategoryId == sub.id)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Filter counts (before the search filter).
    final counts = <_Health, int>{};
    for (final p in base) {
      final h = _healthOf(varsByProduct[p.id] ?? const []);
      counts[h] = (counts[h] ?? 0) + 1;
    }

    var list = base;
    if (_filter != null) {
      list = list
          .where((p) => _healthOf(varsByProduct[p.id] ?? const []) == _filter)
          .toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) {
        if (p.name.toLowerCase().contains(q)) return true;
        for (final v in varsByProduct[p.id] ?? const <Variant>[]) {
          if (_sizeLabel(v).toLowerCase().contains(q)) return true;
        }
        final stock =
            (varsByProduct[p.id] ?? const []).fold(0, (s, v) => s + v.currentStock);
        return stock.toString().contains(q);
      }).toList();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      appBar: AppBar(title: Text(sub?.name ?? 'All ${widget.category.name}')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kPrimary,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _search,
            hint: 'Search products, sizes, stock…',
            onChanged: (v) => setState(() => _query = v),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _Chip(
                  label: 'All (${base.length})',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                _Chip(
                  label: 'In Stock (${counts[_Health.inStock] ?? 0})',
                  dot: _kSuccess,
                  selected: _filter == _Health.inStock,
                  onTap: () => setState(() => _filter = _Health.inStock),
                ),
                _Chip(
                  label: 'Low Stock (${counts[_Health.low] ?? 0})',
                  dot: _kWarning,
                  selected: _filter == _Health.low,
                  onTap: () => setState(() => _filter = _Health.low),
                ),
                _Chip(
                  label: 'Out of Stock (${counts[_Health.out] ?? 0})',
                  dot: _kDanger,
                  selected: _filter == _Health.out,
                  onTap: () => setState(() => _filter = _Health.out),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: list.isEmpty
                ? EmptyView(
                    message: q.isEmpty && _filter == null
                        ? 'No products here yet.\nTap “Add Product”.'
                        : 'No products match.',
                    icon: Icons.inventory_2_outlined,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final p = list[i];
                      final sizes = varsByProduct[p.id] ?? const <Variant>[];
                      return _ProductInfoCard(
                        product: p,
                        sizes: sizes,
                        breadcrumb: sub != null
                            ? '${widget.category.name} › ${sub.name}'
                            : widget.category.name,
                        expanded: _openProduct == p.id,
                        onToggle: () => setState(() =>
                            _openProduct = _openProduct == p.id ? null : p.id),
                        onEdit: () => _openEditor(product: p),
                        onDelete: () => _confirmDelete(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---- product card ----------------------------------------------------------

class _ProductInfoCard extends StatelessWidget {
  const _ProductInfoCard({
    required this.product,
    required this.sizes,
    required this.breadcrumb,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });
  final Product product;
  final List<Variant> sizes;
  final String breadcrumb;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final health = _healthOf(sizes);
    final totalStock = sizes.fold(0, (s, v) => s + v.currentStock);
    final inStock = sizes.where((v) => v.currentStock > 0).length;
    final outStock = sizes.where((v) => v.currentStock <= 0).length;
    final stockColor = switch (health) {
      _Health.out => _kDanger,
      _Health.low => _kWarning,
      _ => _kSuccess,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Avatar(product: product),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Full name on ONE line — auto-shrinks when long.
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(product.name,
                                      maxLines: 1,
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: scheme.onSurface)),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(breadcrumb,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          onSelected: (v) {
                            if (v == 'edit') onEdit();
                            if (v == 'add') onEdit();
                            if (v == 'delete') onDelete();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'edit', child: Text('Edit product')),
                            PopupMenuItem(
                                value: 'add', child: Text('Add variant')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete product')),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _MiniBadge(
                                icon: Icons.grid_view_rounded,
                                text:
                                    '${sizes.length} ${sizes.length == 1 ? 'Variant' : 'Variants'}',
                                fg: _kPrimary,
                                bg: _kPrimary.withValues(alpha: 0.15),
                              ),
                              _MiniBadge(
                                icon: Icons.inventory_2_rounded,
                                text: '${Formatters.qty(totalStock)} Stock',
                                fg: stockColor,
                                bg: stockColor.withValues(alpha: 0.12),
                              ),
                            ],
                          ),
                        ),
                        _Chevron(expanded: expanded),
                      ],
                    ),
                    if (sizes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (inStock > 0) ...[
                            const Icon(Icons.check_circle,
                                size: 13, color: _kSuccess),
                            const SizedBox(width: 4),
                            Text('$inStock in stock',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: _kSuccess,
                                    fontWeight: FontWeight.w600)),
                          ],
                          if (inStock > 0 && outStock > 0)
                            const SizedBox(width: 12),
                          if (outStock > 0) ...[
                            const Icon(Icons.cancel,
                                size: 13, color: _kDanger),
                            const SizedBox(width: 4),
                            Text('$outStock out of stock',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: _kDanger,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    ],
                    if (product.createdAt != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.schedule,
                              size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text('Added ${Formatters.date(product.createdAt)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: expanded
                  ? _VariantsPanel(
                      sizes: sizes,
                      onAdd: onEdit,
                      onEditSize: (v) => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (_) => EditStockSheet(variant: v),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

}

class _VariantsPanel extends StatelessWidget {
  const _VariantsPanel({
    required this.sizes,
    required this.onAdd,
    required this.onEditSize,
  });
  final List<Variant> sizes;
  final VoidCallback onAdd;
  final ValueChanged<Variant> onEditSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...sizes]
      ..sort((a, b) => _sizeLabel(a).compareTo(_sizeLabel(b)));
    // Only show the Length column when at least one size has a length value.
    final showLength = sorted.any(_hasLength);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: _kWarning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('No variants added.',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: _kPrimary, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  _headerCell('SIZE', 3),
                  if (showLength) _headerCell('LENGTH', 3),
                  _headerCell('RATE', 3),
                  _headerCell('WEIGHT', 3),
                  _headerCell('STOCK', 3),
                  const SizedBox(width: 34),
                ],
              ),
            ),
            for (final v in sorted) _sizeRow(v, showLength, scheme),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kPrimary,
                side: const BorderSide(color: _kPrimary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Variant'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text, int flex) => Expanded(
        flex: flex,
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11)),
      );

  Widget _valueCell(String text, int flex, Color color,
          {bool bold = false}) =>
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
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                    color: color)),
          ),
        ),
      );

  Widget _sizeRow(Variant v, bool showLength, ColorScheme scheme) {
    final low = v.currentStock <= 0
        ? _kDanger
        : v.isLowStock
            ? _kWarning
            : _kSuccess;
    final label = v.currentStock <= 0
        ? 'Out'
        : v.isLowStock
            ? 'Low'
            : 'In';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _valueCell(_sizeValue(v), 3, scheme.onSurface, bold: true),
          if (showLength) _valueCell(_lengthLabel(v), 3, scheme.onSurfaceVariant),
          _valueCell(v.rate > 0 ? Formatters.money(v.rate) : '-', 3,
              scheme.onSurfaceVariant),
          _valueCell(_weightLabel(v), 3, scheme.onSurfaceVariant),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(Formatters.qty(v.currentStock),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: low.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(label,
                      style: TextStyle(
                          color: low,
                          fontWeight: FontWeight.w700,
                          fontSize: 10)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 34,
            child: IconButton(
              tooltip: 'Update stock',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.edit_outlined, size: 18, color: _kPrimary),
              onPressed: () => onEditSize(v),
            ),
          ),
        ],
      ),
    );
  }
}

/// Product avatar: the product image if present, else a coloured 2-letter tile.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    // AppThumb renders inline-base64 / network images (with its own fallback).
    if (product.imageUrls.isNotEmpty) {
      return AppThumb(url: product.imageUrls.first, size: 60);
    }
    final initials = _initials(product.name);
    final color = _avatarColor(product.name);
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
      child: Text(initials,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2B3A57))),
    );
  }

  static String _initials(String name) {
    final words =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final base = words.isEmpty ? name : words.last;
    final s = base.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (s.isEmpty) return '?';
    return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
  }

  static Color _avatarColor(String name) {
    const colors = [
      Color(0xFFDCE7FB),
      Color(0xFFE7E0FB),
      Color(0xFFFCE4DC),
      Color(0xFFDDF3E6),
      Color(0xFFFDEFD3),
      Color(0xFFDFF1F7),
    ];
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h + c) % colors.length;
    }
    return colors[h];
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.icon,
    required this.text,
    required this.fg,
    required this.bg,
  });
  final IconData icon;
  final String text;
  final Color fg;
  final Color bg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(text,
              style:
                  TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.imageUrl,
  });
  final String? imageUrl;
  final IconData fallbackIcon;
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                AppThumb(url: imageUrl, size: 64, icon: fallbackIcon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Full name — wraps rather than truncating.
                      Text(title,
                          softWrap: true,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _kPrimary : scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? _kPrimary : scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: selected ? Colors.white : dot,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
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

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: AppSearchBar(
            controller: controller, hint: hint, onChanged: onChanged),
      ),
    );
  }
}
