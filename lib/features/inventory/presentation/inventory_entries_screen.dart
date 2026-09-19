import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../../products/presentation/product_providers.dart';
import '../domain/inventory_transaction.dart';
import 'inventory_providers.dart';

/// Product stock entries (purchase / production / adjustment …) — the last 10
/// by default, or all when [showAll] is true. Reached from the Inventory screen.
class InventoryEntriesScreen extends ConsumerWidget {
  const InventoryEntriesScreen({super.key, this.showAll = false});
  final bool showAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          title: Text(showAll ? 'All product entries' : 'Recent entries')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(companyInventoryTxnsProvider)),
        data: (all) {
          // Manual stock entries only — hide the automatic order deductions.
          final entries =
              all.where((t) => t.type != InventoryTxnType.order).toList();
          final list = showAll ? entries : entries.take(10).toList();
          if (list.isEmpty) {
            return const EmptyView(
                message: 'No stock entries yet.', icon: Icons.history);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: list.length + (showAll ? 0 : 1),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              if (!showAll && i == list.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Center(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const InventoryEntriesScreen(
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
              );
            },
          );
        },
      ),
    );
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
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.title,
    required this.subtitle,
    required this.quantity,
  });
  final String title;
  final String subtitle;
  final int quantity;

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
          Text('${up ? '+' : ''}${Formatters.qty(quantity)}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
