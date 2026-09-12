import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/state_views.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';
import '../domain/raw_material_variant.dart';
import 'raw_material_providers.dart';
import 'raw_material_stock_sheet.dart';
import 'raw_material_variant_form_screen.dart';

/// Drill-down for a single raw material: lists its variants (sizes / specs),
/// each with its own unit and live stock. A persistent button below adds a new
/// variant; each row manages its stock / edit / delete.
class RawMaterialVariantsScreen extends ConsumerWidget {
  const RawMaterialVariantsScreen({super.key, required this.materialId});
  final String materialId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materials = ref.watch(rawMaterialsProvider).valueOrNull ?? const [];
    final material = materials.where((m) => m.id == materialId).firstOrNull;
    final async = ref.watch(rawVariantsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(material?.name ?? 'Variants')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(rawVariantsProvider)),
        data: (_) {
          final variants = ref.watch(variantsOfProvider(materialId));
          return Column(
            children: [
              Expanded(
                child: variants.isEmpty
                    ? const EmptyView(
                        message: 'No variants yet.\n'
                            'Add sizes or specs (e.g. 1/2, 3/4) below.',
                        icon: Icons.straighten)
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: variants.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, i) => _VariantCard(
                          v: variants[i],
                          onTap: () => _manageStock(context, variants[i]),
                          onSelect: (a) {
                            switch (a) {
                              case 'stock':
                                _manageStock(context, variants[i]);
                              case 'edit':
                                _openForm(context, existing: variants[i]);
                              case 'delete':
                                _delete(context, ref, variants[i]);
                            }
                          },
                        ),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => _openForm(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add variant'),
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

  void _openForm(BuildContext context, {RawMaterialVariant? existing}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RawMaterialVariantFormScreen(
        rawMaterialId: materialId,
        existing: existing,
      ),
    ));
  }

  void _manageStock(BuildContext context, RawMaterialVariant v) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RawMaterialStockSheet(variant: v),
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, RawMaterialVariant v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete variant'),
        content: Text('Delete "${v.label}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(rawMaterialRepositoryProvider).deleteVariant(v.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Variant deleted.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard(
      {required this.v, required this.onTap, required this.onSelect});
  final RawMaterialVariant v;
  final VoidCallback onTap;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final attrs = v.attributes.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        attrs.isEmpty
                            ? '${v.unitType} · measured in ${v.unit}'
                            : attrs,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _pill(
                          'Stock: ${fmtQty(v.currentStock)} ${v.unit}',
                          v.isOutOfStock || v.isLowStock
                              ? AppColors.error
                              : scheme.primary,
                        ),
                        if (v.isOutOfStock) ...[
                          const SizedBox(width: 6),
                          _pill('Out of stock', AppColors.error),
                        ] else if (v.isLowStock) ...[
                          const SizedBox(width: 6),
                          _pill('Low', AppColors.warning),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
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
      ),
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
