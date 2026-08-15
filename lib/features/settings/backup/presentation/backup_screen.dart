import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/export_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../inventory/data/inventory_repository.dart';
import '../../../inventory/domain/inventory_transaction.dart';
import '../../../inventory/presentation/inventory_providers.dart';
import '../../../orders/domain/order.dart';
import '../../../orders/domain/order_status.dart';
import '../../../orders/presentation/order_providers.dart';
import '../../../products/domain/product.dart';
import '../../../products/presentation/product_providers.dart';

/// Admin monthly backup — exports a CSV containing, for the chosen month:
///   1. Each party's orders (order no, date, status, amount), the party's total
///      and the whole month's total.
///   2. Inventory stock per variant at the START and END of the month (rebuilt
///      from the immutable inventory-transaction ledger).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  DateTime _month = DateTime(2000); // resolved on first build
  bool _busy = false;
  bool _init = false;

  static const _statusExcluded = {
    OrderStatus.rejected,
    OrderStatus.cancelled,
    OrderStatus.draft,
  };

  List<DateTime> _availableMonths(List<Order> orders) {
    final seen = <String>{};
    final months = <DateTime>[];
    for (final o in orders) {
      final d = o.createdAt;
      if (d == null) continue;
      final key = '${d.year}-${d.month}';
      if (seen.add(key)) months.add(DateTime(d.year, d.month));
    }
    // Always include the current period even with no orders yet.
    months.sort((a, b) => b.compareTo(a));
    return months;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orders = ref.watch(companyOrdersProvider).valueOrNull ?? const [];
    final months = _availableMonths(orders);

    if (!_init && months.isNotEmpty) {
      _month = months.first;
      _init = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly backup')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Export a month\'s data as a CSV file.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
              'Includes each party\'s orders and totals, and inventory stock at '
              'the start and end of the month (variant-wise).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.xl),
          if (months.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('No orders yet — nothing to back up.'),
              ),
            )
          else ...[
            Text('Month', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<DateTime>(
              initialValue: _month,
              items: [
                for (final m in months)
                  DropdownMenuItem(
                    value: m,
                    child: Text(DateFormat('MMMM yyyy').format(m)),
                  ),
              ],
              onChanged: (v) => setState(() => _month = v ?? _month),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: Text(_busy ? 'Preparing…' : 'Download CSV backup'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final companyId =
          ref.read(currentUserProvider).valueOrNull?.companyId ?? 'default';
      final orders = ref.read(companyOrdersProvider).valueOrNull ?? const [];
      final variants = ref.read(allVariantsProvider).valueOrNull ?? const [];
      final products = ref.read(productsProvider).valueOrNull ?? const <Product>[];
      final productName = {for (final p in products) p.id: p.name};
      final txns =
          await ref.read(inventoryRepositoryProvider).allTransactions(companyId);

      final monthStart = DateTime(_month.year, _month.month, 1);
      final nextMonth = DateTime(_month.year, _month.month + 1, 1);

      // ---- Section 1: orders grouped by party --------------------------
      final monthOrders = orders
          .where((o) =>
              o.createdAt != null &&
              !o.createdAt!.isBefore(monthStart) &&
              o.createdAt!.isBefore(nextMonth))
          .toList()
        ..sort((a, b) => a.partyName
            .toLowerCase()
            .compareTo(b.partyName.toLowerCase()));

      final rows = <List<String>>[];
      rows.add(['ORDERS BY PARTY']);
      rows.add(['Party', 'Order No', 'Date', 'Status', 'Amount']);

      final byParty = <String, List<Order>>{};
      for (final o in monthOrders) {
        byParty.putIfAbsent(o.partyName, () => []).add(o);
      }
      var monthTotal = 0.0;
      for (final entry in byParty.entries) {
        var partyTotal = 0.0;
        final list = entry.value
          ..sort((a, b) => (a.createdAt ?? monthStart)
              .compareTo(b.createdAt ?? monthStart));
        for (final o in list) {
          final counts = !_statusExcluded.contains(o.status);
          if (counts) partyTotal += o.grandTotal;
          rows.add([
            entry.key,
            o.displayId,
            Formatters.date(o.createdAt),
            o.status.label,
            Formatters.money(o.grandTotal),
          ]);
        }
        rows.add(['', '', '', '${entry.key} total', Formatters.money(partyTotal)]);
        rows.add([]);
        monthTotal += partyTotal;
      }
      rows.add(['', '', '', 'MONTH TOTAL', Formatters.money(monthTotal)]);
      rows.add([]);
      rows.add([]);

      // ---- Section 2: inventory stock start vs end ---------------------
      rows.add(['INVENTORY STOCK — start vs end of month']);
      rows.add(['Product', 'Size', 'Opening stock', 'Closing stock', 'Rate']);

      // Group transactions by variant for fast running sums.
      final txByVariant = <String, List<InventoryTransaction>>{};
      for (final t in txns) {
        txByVariant.putIfAbsent(t.variantId, () => []).add(t);
      }
      int stockBefore(String variantId, DateTime cutoff) {
        var sum = 0;
        for (final t in txByVariant[variantId] ?? const <InventoryTransaction>[]) {
          if (t.createdAt != null && t.createdAt!.isBefore(cutoff)) {
            sum += t.quantity;
          }
        }
        return sum < 0 ? 0 : sum;
      }

      final sortedVariants = [...variants]
        ..sort((a, b) {
          final pa = productName[a.productId] ?? '';
          final pb = productName[b.productId] ?? '';
          return pa.toLowerCase().compareTo(pb.toLowerCase());
        });
      for (final v in sortedVariants) {
        final size = (v.attributes['Size'] ?? '').trim();
        final unit = (v.attributes['Size Unit'] ?? '').trim();
        final sizeLabel = [size, unit].where((s) => s.isNotEmpty).join(' ');
        rows.add([
          productName[v.productId] ?? 'Product',
          sizeLabel,
          '${stockBefore(v.id, monthStart)}',
          '${stockBefore(v.id, nextMonth)}',
          Formatters.money(v.rate),
        ]);
      }

      final label = DateFormat('yyyy-MM').format(_month);
      await ref.read(exportServiceProvider).exportCsv(
            fileName: 'backup_$label',
            headers: ['Monthly Backup — ${DateFormat('MMMM yyyy').format(_month)}'],
            rows: rows,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
