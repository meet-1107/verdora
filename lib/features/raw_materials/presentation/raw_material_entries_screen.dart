import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';
import 'raw_material_providers.dart';

/// Raw-material stock entries — recent by default (last 10), or all when
/// [showAll] is true. Entries can be selected and deleted (history only).
class RawMaterialEntriesScreen extends ConsumerStatefulWidget {
  const RawMaterialEntriesScreen({super.key, this.showAll = false});
  final bool showAll;

  @override
  ConsumerState<RawMaterialEntriesScreen> createState() =>
      _RawMaterialEntriesScreenState();
}

class _RawMaterialEntriesScreenState
    extends ConsumerState<RawMaterialEntriesScreen> {
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
          .read(rawMaterialRepositoryProvider)
          .deleteTxns(_selected.toList());
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

  @override
  Widget build(BuildContext context) {
    final async =
        ref.watch(widget.showAll ? rawAllTxnsProvider : rawRecentTxnsProvider);
    final materials = ref.watch(rawMaterialsProvider).valueOrNull ?? const [];
    final names = {for (final m in materials) m.id: m.name};

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
            : (widget.showAll ? 'All raw material entries' : 'Recent entries')),
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
            onRetry: () => ref.invalidate(widget.showAll
                ? rawAllTxnsProvider
                : rawRecentTxnsProvider)),
        data: (txns) {
          if (txns.isEmpty) {
            return const EmptyView(
                message: 'No stock entries yet.', icon: Icons.history);
          }
          final allIds = txns.map((t) => t.id).toList();
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
                  itemCount: txns.length + (widget.showAll ? 0 : 1),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (!widget.showAll && i == txns.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const RawMaterialEntriesScreen(
                                            showAll: true))),
                            icon: const Icon(Icons.list_alt),
                            label: const Text('View all entries'),
                          ),
                        ),
                      );
                    }
                    final t = txns[i];
                    final material = names[t.rawMaterialId] ?? 'Raw material';
                    final title = t.label.trim().isEmpty
                        ? material
                        : '$material · ${t.label}';
                    return _EntryRow(
                      title: title,
                      subtitle:
                          '${t.typeLabel} · ${Formatters.dateTime(t.createdAt)}',
                      quantity: t.quantity,
                      unit: t.unit,
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
    required this.unit,
    required this.selectMode,
    required this.selected,
    this.onTap,
    this.onLongPress,
  });
  final String title;
  final String subtitle;
  final double quantity;
  final String unit;
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
            Text('${up ? '+' : ''}${fmtQty(quantity)} $unit',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}
