import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/state_views.dart';
import '../../categories/presentation/category_providers.dart';
import '../../discounts/logic/discount_resolver.dart';
import '../../discounts/presentation/discount_providers.dart';
import '../../parties/presentation/party_providers.dart';
import '../../products/domain/product.dart';
import '../../products/domain/variant.dart';
import '../../products/presentation/product_providers.dart';
import '../application/cart_provider.dart';
import 'client_cart_screen.dart';

/// Single-product bulk order screen with **two-way** pack math per size:
///   • Mode 1 — type a Quantity → auto-split into whole Box packs + Packs.
///   • Mode 2 — set Box-pack / Pack counts → Quantity auto-computes.
/// Box-pack size and pack size come from the admin (per variant). Amount always
/// refreshes instantly. A quantity that can't pack exactly disables saving and
/// offers the two nearest valid quantities.
class ClientQuickOrderScreen extends ConsumerStatefulWidget {
  const ClientQuickOrderScreen({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<ClientQuickOrderScreen> createState() =>
      _ClientQuickOrderScreenState();
}

class _Row {
  _Row({required this.boxSize, required this.packSize})
      : boxCountCtrl = TextEditingController(),
        packCountCtrl = TextEditingController(),
        qtyCtrl = TextEditingController();

  /// Admin-set capacities (pieces).
  final int boxSize;
  final int packSize;

  bool selected = false;
  bool alerted = false; // guards the mismatch sound (once per valid→invalid)
  int remaining = 0; // leftover pieces after a quantity split (0 = valid)

  final TextEditingController boxCountCtrl; // # of box packs
  final TextEditingController packCountCtrl; // # of packs
  final TextEditingController qtyCtrl; // total pieces

  int _read(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return (v == null || v < 0) ? 0 : v;
  }

  int get boxCount => _read(boxCountCtrl);
  int get packCount => _read(packCountCtrl);
  int get qty => _read(qtyCtrl);

  bool get valid => remaining == 0;
  bool get counts => selected && qty > 0;

  void dispose() {
    boxCountCtrl.dispose();
    packCountCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class _ClientQuickOrderScreenState
    extends ConsumerState<ClientQuickOrderScreen> {
  final Map<String, _Row> _rows = {};

  @override
  void dispose() {
    for (final r in _rows.values) {
      r.dispose();
    }
    super.dispose();
  }

  _Row _rowFor(Variant v) => _rows.putIfAbsent(v.id, () {
        final pack = v.pack <= 0 ? 1 : v.pack; // admin: pieces per pack
        final perBox = v.boxPack; // admin: pieces per box
        return _Row(boxSize: perBox <= 0 ? pack : perBox, packSize: pack);
      });

  String _sizeLabel(Variant v) {
    final size = v.attributes['Size'];
    final unit = v.attributes['Size Unit'];
    if (size != null && size.trim().isNotEmpty) {
      return (unit != null && unit.trim().isNotEmpty) ? '$size $unit' : size;
    }
    if (v.attributes.isEmpty) return 'Size';
    return v.attributes.values.join(' ');
  }

  double _unitWeight(Variant v) =>
      double.tryParse(v.attributes['Weight'] ?? '') ?? 0;
  String _weightUnit(Variant v) => v.attributes['Weight Unit'] ?? '';

  double _discountFor(Variant v, dynamic party, DiscountResolver resolver) {
    return resolver.resolve(DiscountContext(
      variantId: v.id,
      productId: widget.product.id,
      categoryId: widget.product.categoryId,
      subcategoryId: widget.product.subcategoryId ?? '',
      partyId: party?.id as String? ?? '',
      partyDefaultDiscount: (party?.defaultDiscount as num?)?.toDouble() ?? 0,
    ));
  }

  // ---- two-way calculation (programmatic .text set doesn't fire onChanged, so
  // there's no feedback loop between the quantity and count fields) -----------

  /// Mode 1: Quantity → Box-pack & Pack counts (greedy: max boxes first).
  void _onQtyChanged(_Row row, String raw) {
    setState(() {
      final q = int.tryParse(raw.trim()) ?? 0;
      if (q > 0) row.selected = true;
      _splitQty(row, q);
    });
    _maybeAlertMismatch(row);
  }

  void _splitQty(_Row row, int q) {
    final box = row.boxSize <= 0 ? 1 : row.boxSize;
    final pack = row.packSize <= 0 ? 1 : row.packSize;
    if (q <= 0) {
      row.boxCountCtrl.text = '';
      row.packCountCtrl.text = '';
      row.remaining = 0;
      return;
    }
    final boxes = box >= pack ? q ~/ box : 0;
    final afterBoxes = q - boxes * box;
    final packs = afterBoxes ~/ pack;
    row.remaining = afterBoxes - packs * pack;
    row.boxCountCtrl.text = '$boxes';
    row.packCountCtrl.text = '$packs';
  }

  /// Mode 2: Box-pack & Pack counts → Quantity.
  void _onCountChanged(_Row row) {
    setState(() {
      final q = row.boxCount * row.boxSize + row.packCount * row.packSize;
      row.qtyCtrl.text = q <= 0 ? '' : '$q';
      row.remaining = 0; // whole counts always pack exactly
      if (q > 0) row.selected = true;
    });
    row.alerted = false;
  }

  /// Jump to an exact (valid) quantity chosen from the suggestion chips.
  void _setQtyExact(_Row row, int q) {
    setState(() {
      row.qtyCtrl.text = q <= 0 ? '' : '$q';
      row.selected = q > 0;
      _splitQty(row, q);
    });
    _maybeAlertMismatch(row);
  }

  /// Alerts (sound + haptic) once when a selected size can't pack exactly.
  void _maybeAlertMismatch(_Row row) {
    final invalid = row.selected && row.qty > 0 && !row.valid;
    if (invalid && !row.alerted) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }
    row.alerted = invalid;
  }

  bool _hasMismatch(List<Variant> variants) {
    for (final v in variants) {
      final r = _rows[v.id];
      if (r != null && r.counts && !r.valid) return true;
    }
    return false;
  }

  void _toggleSelect(Variant v, bool sel) => setState(() {
        final row = _rowFor(v);
        row.selected = sel;
        if (!sel) _clear(row);
      });

  void _selectAll(List<Variant> variants, bool sel) => setState(() {
        for (final v in variants) {
          final row = _rowFor(v);
          row.selected = sel;
          if (!sel) _clear(row);
        }
      });

  void _clear(_Row row) {
    row
      ..qtyCtrl.clear()
      ..boxCountCtrl.clear()
      ..packCountCtrl.clear()
      ..remaining = 0
      ..alerted = false;
  }

  ({int qty, double total, double weight}) _totals(
      List<Variant> variants, dynamic party, DiscountResolver resolver) {
    var qty = 0;
    var total = 0.0;
    var weight = 0.0;
    for (final v in variants) {
      final row = _rows[v.id];
      if (row == null || !row.counts) continue;
      final disc = _discountFor(v, party, resolver);
      qty += row.qty;
      total += v.rate * (1 - disc / 100) * row.qty;
      weight += _unitWeight(v) * row.qty;
    }
    return (qty: qty, total: total, weight: weight);
  }

  void _saveToCart(
      List<Variant> variants, dynamic party, DiscountResolver resolver) {
    final cart = ref.read(cartProvider.notifier);
    var added = 0;
    for (final v in variants) {
      final row = _rows[v.id];
      if (row == null || !row.counts) continue;
      cart.addVariant(
        variantId: v.id,
        productName: widget.product.name,
        variantLabel: _sizeLabel(v),
        rate: v.rate,
        qty: row.qty,
        discountPercent: _discountFor(v, party, resolver),
      );
      added += row.qty;
    }
    HapticFeedback.mediumImpact();
    // Capture the app-level messenger + navigator BEFORE navigating.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Navigate / reset FIRST. Showing a snackbar and then immediately popping
    // the screen interrupts its entrance animation, so the auto-dismiss timer
    // never starts and the toast hangs forever. Doing the route change first
    // lets the snackbar animate + time out normally (2s).
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      setState(() {
        for (final v in variants) {
          final r = _rows[v.id];
          if (r != null && r.counts) {
            r.selected = false;
            _clear(r);
          }
        }
      });
    }

    // A lightweight notification-style toast (rounded dark pill, no action),
    // auto-dismissing in 3 seconds.
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF2A2E37),
        elevation: 6,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF34D399), size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${Formatters.qty(added)} pcs added to cart',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ));
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;
    final variantsAsync = ref.watch(variantsByProductProvider(product.id));
    final party = ref.watch(orderPartyProvider);
    final resolver =
        DiscountResolver(ref.watch(discountsProvider).valueOrNull ?? const []);
    final cartCount = ref.watch(cartItemCountProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final categoryName = categories
            .where((c) => c.id == product.categoryId)
            .map((c) => c.name)
            .fold<String?>(null, (p, e) => p ?? e) ??
        '—';

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Badge.count(
              count: cartCount,
              isLabelVisible: cartCount > 0,
              offset: const Offset(-6, 4),
              child: IconButton(
                tooltip: 'Cart',
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ClientCartScreen())),
              ),
            ),
          ),
        ],
      ),
      body: variantsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(variantsByProductProvider(product.id)),
        ),
        data: (all) {
          final variants = all.where((v) => v.status == 'active').toList();
          if (variants.isEmpty) {
            return const EmptyView(
              message: 'No sizes available for this product yet.',
              icon: Icons.inventory_2_outlined,
            );
          }
          final allSelected =
              variants.every((v) => _rows[v.id]?.selected ?? false);
          return Column(
            children: [
              _ProductHeader(product: product, categoryName: categoryName),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.md, 0),
                child: Row(
                  children: [
                    Text('Select sizes', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    const Text('Select all'),
                    Checkbox(
                      value: allSelected,
                      onChanged: (v) => _selectAll(variants, v ?? false),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                  itemCount: variants.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, i) {
                    final v = variants[i];
                    final row = _rowFor(v);
                    return _VariantCard(
                      size: _sizeLabel(v),
                      row: row,
                      rate: v.rate,
                      discount: _discountFor(v, party, resolver),
                      unitWeight: _unitWeight(v),
                      weightUnit: _weightUnit(v),
                      onSelect: (sel) => _toggleSelect(v, sel),
                      onCountChanged: () => _onCountChanged(row),
                      onQtyChanged: (s) => _onQtyChanged(row, s),
                      onPickQty: (q) => _setQtyExact(row, q),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: variantsAsync.maybeWhen(
        data: (all) {
          final variants = all.where((v) => v.status == 'active').toList();
          final t = _totals(variants, party, resolver);
          final mismatch = _hasMismatch(variants);
          final canSave = t.qty > 0 && !mismatch;
          final String subtitle;
          if (mismatch) {
            subtitle = 'Fix the quantity that can\'t be packed exactly';
          } else if (t.qty > 0) {
            subtitle =
                '${Formatters.qty(t.qty)} pcs${t.weight > 0 ? ' · ${_fmtWeight(t.weight)}' : ''}';
          } else {
            subtitle = 'Select sizes & enter quantity';
          }
          return SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(Formatters.money(t.total),
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: mismatch
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: mismatch ? FontWeight.w600 : null)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: canSave
                        ? () => _saveToCart(variants, party, resolver)
                        : null,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Save to cart'),
                  ),
                ],
              ),
            ),
          );
        },
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }

  static String _fmtWeight(double w) => w <= 0
      ? ''
      : '${w % 1 == 0 ? w.toStringAsFixed(0) : w.toStringAsFixed(2)} wt';
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.product, required this.categoryName});
  final Product product;
  final String categoryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerProvider = appImageProvider(
        product.imageUrls.isEmpty ? null : product.imageUrls.first);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: headerProvider == null
                ? _ph(theme)
                : Image(
                    image: headerProvider,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ph(theme),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('Category: $categoryName',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ph(ThemeData theme) => Container(
        width: 56,
        height: 56,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.inventory_2_outlined,
            color: theme.colorScheme.onSurfaceVariant),
      );
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.size,
    required this.row,
    required this.rate,
    required this.discount,
    required this.unitWeight,
    required this.weightUnit,
    required this.onSelect,
    required this.onCountChanged,
    required this.onQtyChanged,
    required this.onPickQty,
  });

  final String size;
  final _Row row;
  final double rate;
  final double discount;
  final double unitWeight;
  final String weightUnit;
  final ValueChanged<bool> onSelect;
  final VoidCallback onCountChanged;
  final ValueChanged<String> onQtyChanged;
  final ValueChanged<int> onPickQty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finalRate = rate * (1 - discount / 100);
    final amount = finalRate * row.qty;
    final totalWeight = unitWeight * row.qty;

    return Card(
      color:
          row.selected ? scheme.primaryContainer.withValues(alpha: 0.25) : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: row.selected,
                  onChanged: (v) => onSelect(v ?? false),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Text(size,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text(Formatters.money(finalRate),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: scheme.primary)),
                if (discount > 0) ...[
                  const SizedBox(width: 4),
                  Text('-${discount.toStringAsFixed(0)}%',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.success)),
                ],
              ],
            ),
            const SizedBox(height: 2),
            // Admin-set capacities.
            Text('Box pack = ${row.boxSize} pcs   ·   Pack = ${row.packSize} pcs',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            _CountRow(
                label: 'Box packs',
                controller: row.boxCountCtrl,
                onChanged: onCountChanged),
            const SizedBox(height: AppSpacing.sm),
            _CountRow(
                label: 'Packs',
                controller: row.packCountCtrl,
                onChanged: onCountChanged),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                SizedBox(
                    width: 92,
                    child: Text('Quantity', style: theme.textTheme.bodyMedium)),
                Expanded(
                  child: TextField(
                    controller: row.qtyCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Enter quantity (pcs)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: onQtyChanged,
                  ),
                ),
              ],
            ),
            if (row.qty > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: 2,
                children: [
                  _tag(theme, '📦 Box packs: ${row.boxCount}'),
                  _tag(theme, 'Packs: ${row.packCount}'),
                  _tag(theme, 'Total: ${Formatters.qty(row.qty)} pcs'),
                  if (unitWeight > 0)
                    _tag(theme,
                        'Weight: ${_fmt(totalWeight)} $weightUnit'.trim()),
                  _tag(theme, 'Amount: ${Formatters.money(amount)}',
                      strong: true),
                ],
              ),
              if (!row.valid) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${row.remaining} pcs left over — this quantity can\'t '
                          'be packed exactly. Pick a valid quantity:',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (row.qty - row.remaining > 0)
                            ActionChip(
                              label: Text(
                                  '${Formatters.qty(row.qty - row.remaining)} (lower)'),
                              onPressed: () =>
                                  onPickQty(row.qty - row.remaining),
                            ),
                          ActionChip(
                            label: Text(
                                '${Formatters.qty(row.qty - row.remaining + row.packSize)} (higher)'),
                            onPressed: () => onPickQty(
                                row.qty - row.remaining + row.packSize),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Widget _tag(ThemeData theme, String text, {bool strong = false}) => Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          color: strong
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        ),
      );
}

/// "Box packs  [–] [ count ] [+]" — editable count with steppers. Empty means
/// zero. Any change recomputes the Quantity (Mode 2).
class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.controller,
    required this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  int get _value => int.tryParse(controller.text.trim()) ?? 0;

  void _set(int n) {
    final v = n < 0 ? 0 : n;
    controller.text = v == 0 ? '' : '$v';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget btn(IconData icon, VoidCallback onTap) => InkResponse(
          onTap: onTap,
          radius: 20,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18),
          ),
        );
    return Row(
      children: [
        SizedBox(
            width: 92,
            child: Text(label, style: theme.textTheme.bodyMedium)),
        btn(Icons.remove, () => _set(_value - 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            width: 68,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                hintText: '0',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
        btn(Icons.add, () => _set(_value + 1)),
      ],
    );
  }
}
