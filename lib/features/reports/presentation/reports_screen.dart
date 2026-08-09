import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/export_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/state_views.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/domain/order_status.dart';
import '../../orders/presentation/order_providers.dart';

/// Revenue counts once an order is approved (or further along).
const _revenueStatuses = {
  OrderStatus.approved,
  OrderStatus.packing,
  OrderStatus.packed,
  OrderStatus.dispatched,
  OrderStatus.delivered,
  OrderStatus.completed,
};

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(companyOrdersProvider);
    final variants = ref.watch(allVariantsProvider).valueOrNull ?? const [];
    final lowStock = ref.watch(lowStockVariantsProvider).length;

    final inventoryValue =
        variants.fold<double>(0, (s, v) => s + v.currentStock * v.rate);

    return Scaffold(
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Reports'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Export orders',
            onSelected: (fmt) => _export(context, ref, fmt),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
              PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(companyOrdersProvider)),
        data: (orders) {
          final revenueOrders =
              orders.where((o) => _revenueStatuses.contains(o.status)).toList();
          final revenue =
              revenueOrders.fold<double>(0, (s, o) => s + o.grandTotal);
          final pending =
              orders.where((o) => o.status == OrderStatus.pending).length;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _grid([
                _Metric('Revenue', Formatters.moneyCompact(revenue),
                    Icons.payments_outlined, Colors.green),
                _Metric('Orders', '${orders.length}',
                    Icons.receipt_long_outlined, Colors.blue),
                _Metric('Pending', '$pending', Icons.pending_actions_outlined,
                    Colors.orange),
                _Metric(
                    'Inventory value',
                    Formatters.moneyCompact(inventoryValue),
                    Icons.inventory_2_outlined,
                    Colors.indigo),
                _Metric('Low stock', '$lowStock', Icons.warning_amber_outlined,
                    Colors.red),
              ]),
              const SizedBox(height: 24),
              _Section(
                title: 'Orders by status',
                child: _StatusBreakdown(orders: orders),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Top parties by revenue',
                child: _TopParties(orders: revenueOrders),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Monthly revenue',
                child: _MonthlyRevenue(orders: revenueOrders),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref, String fmt) async {
    final orders = ref.read(companyOrdersProvider).valueOrNull ?? const [];
    if (orders.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No orders to export.')));
      return;
    }
    final headers = [
      'Invoice',
      'Party',
      'Date',
      'Status',
      'Subtotal',
      'Discount',
      'Total',
    ];
    final rows = [
      for (final o in orders)
        [
          o.invoiceNo ?? '',
          o.partyName,
          Formatters.date(o.createdAt),
          o.status.label,
          o.subtotal.toStringAsFixed(2),
          o.discountTotal.toStringAsFixed(2),
          o.grandTotal.toStringAsFixed(2),
        ],
    ];
    final service = ref.read(exportServiceProvider);
    try {
      switch (fmt) {
        case 'csv':
          await service.exportCsv(
              fileName: 'orders', headers: headers, rows: rows);
        case 'xlsx':
          await service.exportExcel(
              fileName: 'orders', headers: headers, rows: rows);
        case 'pdf':
          await service.exportPdf(
              title: 'Orders Report', headers: headers, rows: rows);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Widget _grid(List<Widget> children) => LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 1000 ? 5 : (c.maxWidth > 600 ? 3 : 2);
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: children,
          );
        },
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: child)),
      ],
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final counts = <OrderStatus, int>{};
    for (final o in orders) {
      counts[o.status] = (counts[o.status] ?? 0) + 1;
    }
    if (counts.isEmpty) return const Text('No orders yet.');
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(e.key.label)),
                Text('${e.value}',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
      ],
    );
  }
}

class _TopParties extends StatelessWidget {
  const _TopParties({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    for (final o in orders) {
      totals[o.partyName] = (totals[o.partyName] ?? 0) + o.grandTotal;
    }
    if (totals.isEmpty) return const Text('No revenue yet.');
    final top = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: [
        for (final e in top.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(e.key)),
                Text(Formatters.money(e.value)),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthlyRevenue extends StatelessWidget {
  const _MonthlyRevenue({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM yyyy');
    final totals = <String, double>{};
    for (final o in orders) {
      final d = o.createdAt;
      if (d == null) continue;
      final key = fmt.format(d);
      totals[key] = (totals[key] ?? 0) + o.grandTotal;
    }
    if (totals.isEmpty) return const Text('No revenue yet.');
    final max = totals.values.fold<double>(0, (m, v) => v > m ? v : m);
    return Column(
      children: [
        for (final e in totals.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key),
                    Text(Formatters.money(e.value)),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: max == 0 ? 0 : e.value / max,
                  minHeight: 6,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
