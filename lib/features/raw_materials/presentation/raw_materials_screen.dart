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
import 'raw_material_variants_screen.dart';

/// Admin → Operations → Raw Material. Lists raw materials. A "single" material
/// shows its stock and manages it inline; a material with variants shows how
/// many it has and drills into them. A persistent button below adds a new one.
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

  void _openVariants(RawMaterial m) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RawMaterialVariantsScreen(materialId: m.id)));
  }

  void _manageStock(RawMaterialVariant v) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RawMaterialStockSheet(variant: v),
    );
  }

  Future<void> _delete(RawMaterial m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete raw material'),
        content: Text(
            'Delete "${m.name}" and all of its stock? This cannot be undone.'),
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
      await ref.read(rawMaterialRepositoryProvider).deleteMaterial(m.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Raw material deleted.')));
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
                              variants:
                                  ref.watch(variantsOfProvider(list[i].id)),
                              onTapSimple: _manageStock,
                              onTapVariants: () => _openVariants(list[i]),
                              onSelect: (a) {
                                switch (a) {
                                  case 'stock':
                                    final vs = ref
                                        .read(variantsOfProvider(list[i].id));
                                    if (vs.isNotEmpty) _manageStock(vs.first);
                                  case 'edit':
                                    _openForm(existing: list[i]);
                                  case 'delete':
                                    _delete(list[i]);
                                }
                              },
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

class _RawCard extends StatelessWidget {
  const _RawCard({
    required this.m,
    required this.variants,
    required this.onTapSimple,
    required this.onTapVariants,
    required this.onSelect,
  });
  final RawMaterial m;
  final List<RawMaterialVariant> variants;
  final ValueChanged<RawMaterialVariant> onTapSimple;
  final VoidCallback onTapVariants;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final img = appImageProvider(m.imageUrl);
    final simple = isSimpleVariantList(variants);
    final v = variants.isNotEmpty ? variants.first : null;

    // Subtitle + badges differ for single vs variant materials.
    final Widget subtitle;
    if (variants.isEmpty) {
      subtitle = Text('No stock yet',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant));
    } else if (simple && v != null) {
      subtitle = Row(
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
    } else {
      final outCount = variants.where((x) => x.isOutOfStock).length;
      final lowCount = variants.where((x) => x.isLowStock).length;
      subtitle = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${variants.length} variants · ${m.unit}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          if (outCount > 0 || lowCount > 0) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                if (outCount > 0)
                  _pill('$outCount out of stock', AppColors.error),
                if (lowCount > 0) _pill('$lowCount low', AppColors.warning),
              ],
            ),
          ],
        ],
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (simple && v != null) {
            onTapSimple(v);
          } else {
            onTapVariants();
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
                    subtitle,
                  ],
                ),
              ),
              if (!simple) const Icon(Icons.chevron_right),
              PopupMenuButton<String>(
                onSelected: onSelect,
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
