import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/raw_material.dart';
import 'raw_material_providers.dart';

/// Raw-material stock entries — recent by default (last 10), or all when
/// [showAll] is true. Reached from the Raw Material screen.
class RawMaterialEntriesScreen extends ConsumerWidget {
  const RawMaterialEntriesScreen({super.key, this.showAll = false});
  final bool showAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async =
        ref.watch(showAll ? rawAllTxnsProvider : rawRecentTxnsProvider);
    final materials = ref.watch(rawMaterialsProvider).valueOrNull ?? const [];
    final names = {for (final m in materials) m.id: m.name};

    return Scaffold(
      appBar: AppBar(
          title: Text(showAll ? 'All raw material entries' : 'Recent entries')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(
                showAll ? rawAllTxnsProvider : rawRecentTxnsProvider)),
        data: (txns) {
          if (txns.isEmpty) {
            return const EmptyView(
                message: 'No stock entries yet.', icon: Icons.history);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: txns.length + (showAll ? 0 : 1),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              if (!showAll && i == txns.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Center(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const RawMaterialEntriesScreen(
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
                subtitle: '${t.typeLabel} · ${Formatters.dateTime(t.createdAt)}',
                quantity: t.quantity,
                unit: t.unit,
              );
            },
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
  });
  final String title;
  final String subtitle;
  final double quantity;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = quantity >= 0;
    final color = up ? const Color(0xFF16A34A) : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
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
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text('${up ? '+' : ''}${fmtQty(quantity)} $unit',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
