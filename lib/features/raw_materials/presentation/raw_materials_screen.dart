import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/state_views.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';
import '../domain/raw_material_variant.dart';
import 'raw_material_form_screen.dart';
import 'raw_material_providers.dart';
import 'raw_material_stock_sheet.dart';
import 'raw_material_variant_form_screen.dart';

/// Admin → Operations → Raw Material. Lists raw materials. A "single" material
/// shows its stock and manages it inline; a material with variants expands to
/// show its variants (each with its own unit and stock). A persistent button
/// below adds a new one.
class RawMaterialsScreen extends ConsumerStatefulWidget {
  const RawMaterialsScreen({super.key});

  @override
  ConsumerState<RawMaterialsScreen> createState() => _RawMaterialsScreenState();
}

class _RawMaterialsScreenState extends ConsumerState<RawMaterialsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openForm({RawMaterial? existing}) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RawMaterialFormScreen(existing: existing)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rawMaterialsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Raw Material'),
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(rawMaterialsProvider)),
        data: (all) {
          final list = _query.isEmpty
              ? all
              : all
                  .where((m) => m.name.toLowerCase().contains(_query))
                  .toList();
          list.sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                child: TextField(
                  controller: _search,
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search raw materials',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? const EmptyView(
                        message: 'No raw materials yet.\n'
                            'Add your first one below.',
                        icon: Icons.science_outlined)
                    : list.isEmpty
                        ? const EmptyView(
                            message: 'No matches.', icon: Icons.search_off)
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0,
                                AppSpacing.lg, AppSpacing.lg),
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (_, i) => _RawCard(
                              m: list[i],
                              onEditMaterial: () =>
                                  _openForm(existing: list[i]),
                            ),
                          ),
              ),
              // Persistent "Add raw material" button below.
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm,
                      AppSpacing.lg, AppSpacing.md),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add raw material'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One raw material card. Single materials show/manage stock inline; variant
/// materials expand to reveal their variants.
class _RawCard extends ConsumerStatefulWidget {
  const _RawCard({required this.m, required this.onEditMaterial});
  final RawMaterial m;
  final VoidCallback onEditMaterial;

  @override
  ConsumerState<_RawCard> createState() => _RawCardState();
}

class _RawCardState extends ConsumerState<_RawCard> {
  bool _expanded = false;

  RawMaterial get m => widget.m;

  void _stockSheet(RawMaterialVariant v) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RawMaterialStockSheet(variant: v),
    );
  }

  void _addVariant() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RawMaterialVariantFormScreen(rawMaterialId: m.id)));
  }

  void _editVariant(RawMaterialVariant v) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            RawMaterialVariantFormScreen(rawMaterialId: m.id, existing: v)));
  }

  Future<void> _deleteMaterial() async {
    final ok = await _confirm(
        'Delete raw material', 'Delete "${m.name}" and all of its stock?');
    if (!ok) return;
    try {
      await ref.read(rawMaterialRepositoryProvider).deleteMaterial(m.id);
      _toast('Raw material deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _deleteVariant(RawMaterialVariant v) async {
    final ok = await _confirm('Delete variant', 'Delete "${v.label}"?');
    if (!ok) return;
    try {
      await ref.read(rawMaterialRepositoryProvider).deleteVariant(v.id);
      _toast('Variant deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text('$body This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final variants = ref.watch(variantsOfProvider(m.id));
    final img = appImageProvider(m.imageUrl);
    final simple = isSimpleVariantList(variants);
    final v = variants.isNotEmpty ? variants.first : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (simple && v != null) {
                _stockSheet(v);
              } else if (variants.isEmpty) {
                widget.onEditMaterial();
              } else {
                setState(() => _expanded = !_expanded);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      image: img == null
                          ? null
                          : DecorationImage(image: img, fit: BoxFit.cover),
                    ),
                    child: img == null
                        ? Icon(Icons.science_outlined,
                            color: scheme.onSurfaceVariant)
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        _subtitle(theme, scheme, variants, simple, v),
                      ],
                    ),
                  ),
                  // Vertical expand arrow for variant materials.
                  if (!simple && variants.isNotEmpty)
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down,
                          color: scheme.onSurfaceVariant),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (a) {
                      switch (a) {
                        case 'stock':
                          if (v != null) _stockSheet(v);
                        case 'edit':
                          widget.onEditMaterial();
                        case 'delete':
                          _deleteMaterial();
                      }
                    },
                    itemBuilder: (_) => [
                      if (simple)
                        const PopupMenuItem(
                            value: 'stock', child: Text('Update stock')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete',
                              style: TextStyle(color: AppColors.error))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Inline variant dropdown.
          if (!simple && variants.isNotEmpty && _expanded) ...[
            const Divider(height: 1),
            for (final variant in variants)
              _VariantTile(
                v: variant,
                onTap: () => _stockSheet(variant),
                onSelect: (a) {
                  switch (a) {
                    case 'stock':
                      _stockSheet(variant);
                    case 'edit':
                      _editVariant(variant);
                    case 'delete':
                      _deleteVariant(variant);
                  }
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addVariant,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add variant'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _subtitle(ThemeData theme, ColorScheme scheme,
      List<RawMaterialVariant> variants, bool simple, RawMaterialVariant? v) {
    if (variants.isEmpty) {
      return Text('No stock yet — tap to set up',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant));
    }
    if (simple && v != null) {
      return Row(
        children: [
          _pill(
            'Stock: ${fmtQty(v.currentStock)} ${v.unit}',
            v.isOutOfStock || v.isLowStock ? AppColors.error : scheme.primary,
          ),
          if (v.isOutOfStock) ...[
            const SizedBox(width: 6),
            _pill('Out of stock', AppColors.error),
          ] else if (v.isLowStock) ...[
            const SizedBox(width: 6),
            _pill('Low', AppColors.warning),
          ],
        ],
      );
    }
    final outCount = variants.where((x) => x.isOutOfStock).length;
    final lowCount = variants.where((x) => x.isLowStock).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${variants.length} variants',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        if (outCount > 0 || lowCount > 0) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              if (outCount > 0) _pill('$outCount out of stock', AppColors.error),
              if (lowCount > 0) _pill('$lowCount low', AppColors.warning),
            ],
          ),
        ],
      ],
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      );
}

/// A single variant row inside an expanded material card.
class _VariantTile extends StatelessWidget {
  const _VariantTile(
      {required this.v, required this.onTap, required this.onSelect});
  final RawMaterialVariant v;
  final VoidCallback onTap;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stockColor =
        v.isOutOfStock || v.isLowStock ? AppColors.error : scheme.primary;
    final status = v.isOutOfStock
        ? 'Out of stock'
        : v.isLowStock
            ? 'Low'
            : null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.straighten, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(v.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            // Value written with its unit, e.g. "500 kg" / "20 mm".
            Text('${fmtQty(v.currentStock)} ${v.unit}',
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: stockColor)),
            if (status != null) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: (v.isOutOfStock
                            ? AppColors.error
                            : AppColors.warning)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(status,
                    style: TextStyle(
                        color: v.isOutOfStock
                            ? AppColors.error
                            : AppColors.warning,
                        fontWeight: FontWeight.w700,
                        fontSize: 10)),
              ),
            ],
            PopupMenuButton<String>(
              onSelected: onSelect,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'stock', child: Text('Update stock')),
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.error))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
