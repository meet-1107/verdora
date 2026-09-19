import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../../products/presentation/product_providers.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory_transaction.dart';
import 'inventory_providers.dart';

/// Product stock entries (purchase / production / adjustment …) — the last 10
/// by default, or all when [showAll] is true. Entries can be selected and
/// deleted (history records only; stock is unchanged).
class InventoryEntriesScreen extends ConsumerStatefulWidget {
  const InventoryEntriesScreen({super.key, this.showAll = false});
  final bool showAll;

  @override
  ConsumerState<InventoryEntriesScreen> createState() =>
      _InventoryEntriesScreenState();
}

class _InventoryEntriesScreenState
    extends ConsumerState<InventoryEntriesScreen> {
  final Set<String> _selected = {};
  bool _selectMode = false;

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  Future<void> _deleteSelected() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete entries'),
        content: Text('Delete ${_selected.length} selected '
            'entr${_selected.length == 1 ? 'y' : 'ies'} from history? '
            'Stock is not changed.'),
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
    if (ok != true) return;
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .deleteTransactions(_selected.toList());
      if (mounted) {
        setState(() {
          _selected.clear();
          _selectMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  String _typeLabel(InventoryTxnType t) => switch (t) {
        InventoryTxnType.opening => 'Opening stock',
        InventoryTxnType.purchase => 'Purchase',
        InventoryTxnType.production => 'Production',
        InventoryTxnType.adjustment => 'Adjustment',
        InventoryTxnType.damage => 'Damage',
        InventoryTxnType.ret => 'Return',
        InventoryTxnType.correction => 'Correction',
        InventoryTxnType.order => 'Order',
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(companyInventoryTxnsProvider);
    final variants = ref.watch(allVariantsProvider).valueOrNull ?? const [];
    final products = ref.watch(productsProvider).valueOrNull ?? const [];
    final variantsById = {for (final v in variants) v.id: v};
    final productNames = {for (final p in products) p.id: p.name};

    String labelFor(String variantId) {
      final v = variantsById[variantId];
      if (v == null) return 'Product';
      final product = productNames[v.productId] ?? 'Product';
      final size = (v.attributes['Size'] ?? '').trim();
      final unit = (v.attributes['Size Unit'] ?? '').trim();
      final sizeLabel = [size, unit].where((s) => s.isNotEmpty).join(' ');
      return sizeLabel.isEmpty ? product : '$product · $sizeLabel';
    }

    return Scaffold(
      appBar: AppBar(
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectMode = false;
                  _selected.clear();
                }),
              )
            : null,
        title: Text(_selectMode
            ? '${_selected.length} selected'
            : (widget.showAll ? 'All product entries' : 'Recent entries')),
        actions: [
          if (_selectMode)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            )
          else
            IconButton(
              tooltip: 'Select',
              icon: const Icon(Icons.checklist),
              onPressed: () => setState(() => _selectMode = true),
            ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(companyInventoryTxnsProvider)),
        data: (all) {
          // Manual stock entries only — hide the automatic order deductions.
          final entries =
              all.where((t) => t.type != InventoryTxnType.order).toList();
          final list =
              widget.showAll ? entries : entries.take(10).toList();
          if (list.isEmpty) {
            return const EmptyView(
                message: 'No stock entries yet.', icon: Icons.history);
          }
          final allIds = list.map((t) => t.id).toList();
          return Column(
            children: [
              if (_selectMode)
                CheckboxListTile(
                  dense: true,
                  value: _selected.length == allIds.length,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected
                        ..clear()
                        ..addAll(allIds);
                    } else {
                      _selected.clear();
                    }
                  }),
                  title: const Text('Select all'),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: list.length + (widget.showAll ? 0 : 1),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (!widget.showAll && i == list.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const InventoryEntriesScreen(
                                            showAll: true))),
                            icon: const Icon(Icons.list_alt),
                            label: const Text('View all entries'),
                          ),
                        ),
                      );
                    }
                    final t = list[i];
                    return _EntryRow(
                      title: labelFor(t.variantId),
                      subtitle:
                          '${_typeLabel(t.type)} · ${Formatters.dateTime(t.createdAt)}',
                      quantity: t.quantity,
                      selectMode: _selectMode,
                      selected: _selected.contains(t.id),
                      onTap: _selectMode ? () => _toggle(t.id) : null,
                      onLongPress: () => setState(() {
                        _selectMode = true;
                        _selected.add(t.id);
                      }),
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
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.title,
    required this.subtitle,
    required this.quantity,
    required this.selectMode,
    required this.selected,
    this.onTap,
    this.onLongPress,
  });
  final String title;
  final String subtitle;
  final int quantity;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = quantity >= 0;
    final color = up ? const Color(0xFF16A34A) : theme.colorScheme.error;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : null,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            if (selectMode)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                    selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 20,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant),
              )
            else
              Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 18, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Text('${up ? '+' : ''}${Formatters.qty(quantity)}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}
