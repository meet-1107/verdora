import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_status_chip.dart';
import '../../../core/widgets/state_views.dart';
import '../../activity/data/activity_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../products/domain/variant.dart';
import '../../products/presentation/product_providers.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/domain/order.dart';
import '../../orders/domain/order_status.dart';
import '../../orders/presentation/order_detail_screen.dart';
import '../../orders/presentation/order_providers.dart';

/// Warehouse Operations Center — an action-first workspace. The top strip and
/// "Needs attention" panel tell staff what to do now; tapping any KPI filters
/// the order queue below. Order cards are order/customer-focused, and the
/// low-stock table surfaces available vs minimum with an urgency badge. Reuses
/// the existing order + inventory logic (dispatch deducts stock).
class WarehouseScreen extends ConsumerStatefulWidget {
  const WarehouseScreen({super.key});

  @override
  ConsumerState<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends ConsumerState<WarehouseScreen> {
  static const _queueStatuses = [
    OrderStatus.approved,
    OrderStatus.modifiedApproved,
    OrderStatus.packing,
    OrderStatus.packed,
    OrderStatus.dispatched,
  ];
  OrderStatus? _filter; // null = all active queue
  bool _busy = false;
  final _lowStockKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _advance(Order o) {
    final repo = ref.read(orderRepositoryProvider);
    final logger = ref.read(activityLoggerProvider);
    final uid = ref.read(currentUserProvider).valueOrNull?.uid;
    final label = o.displayId;
    switch (o.status) {
      case OrderStatus.approved:
      case OrderStatus.modifiedApproved:
        _run(() async {
          await repo.setStatus(o.id, OrderStatus.packing);
          await logger.record('order.packing', target: label);
        }, 'Packing started.');
      case OrderStatus.packing:
        _run(() async {
          await repo.markPacked(o, createdBy: uid);
          await logger.record('order.packed', target: label);
        }, 'Marked packed — stock deducted.');
      case OrderStatus.packed:
        _run(() async {
          await repo.markDispatched(o, createdBy: uid);
          await logger.record('order.dispatched', target: label);
        }, 'Dispatched.');
      default:
        break;
    }
  }

  String? _actionLabel(OrderStatus s) => switch (s) {
        OrderStatus.approved || OrderStatus.modifiedApproved => 'Start packing',
        OrderStatus.packing => 'Mark packed',
        OrderStatus.packed => 'Dispatch',
        _ => null,
      };

  void _reviewLowStock() {
    final ctx = _lowStockKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.05);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(companyOrdersProvider);
    final lowStock = ref.watch(lowStockVariantsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Warehouse Operations'),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ordersAsync.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
              error: e, onRetry: () => ref.invalidate(companyOrdersProvider)),
          data: (orders) {
            int count(OrderStatus s) =>
                orders.where((o) => o.status == s).length;
            final waiting = count(OrderStatus.approved) +
                count(OrderStatus.modifiedApproved);
            final packing = count(OrderStatus.packing);
            final ready = count(OrderStatus.packed);
            final dispatched = count(OrderStatus.dispatched);

            final queue = orders
                .where((o) => _filter == null
                    ? _queueStatuses.contains(o.status)
                    : o.status == _filter)
                .toList();

            return ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                // KPI strip — tap to filter the queue.
                _KpiStrip(
                  items: [
                    _Kpi('Waiting', waiting, AppColors.warning,
                        onTap: () => setState(() => _filter = OrderStatus.approved),
                        selected: _filter == OrderStatus.approved),
                    _Kpi('Packing', packing, AppColors.info,
                        onTap: () => setState(() => _filter = OrderStatus.packing),
                        selected: _filter == OrderStatus.packing),
                    _Kpi('Ready', ready, const Color(0xFF7B1FA2),
                        onTap: () => setState(() => _filter = OrderStatus.packed),
                        selected: _filter == OrderStatus.packed),
                    _Kpi('Dispatched', dispatched, AppColors.success,
                        onTap: () =>
                            setState(() => _filter = OrderStatus.dispatched),
                        selected: _filter == OrderStatus.dispatched),
                    _Kpi('Low stock', lowStock.length, AppColors.error,
                        onTap: _reviewLowStock),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // Needs attention.
                _AttentionPanel(
                  rows: [
                    if (lowStock.isNotEmpty)
                      _Attention(
                        icon: Icons.inventory_2_outlined,
                        color: AppColors.error,
                        text: '${lowStock.length} product(s) below minimum stock',
                        priority: 'Critical',
                        actionLabel: 'Review',
                        onAction: _reviewLowStock,
                      ),
                    if (waiting > 0)
                      _Attention(
                        icon: Icons.pending_actions_outlined,
                        color: AppColors.warning,
                        text: '$waiting order(s) waiting to be packed',
                        priority: 'High',
                        actionLabel: 'Start',
                        onAction: () =>
                            setState(() => _filter = OrderStatus.approved),
                      ),
                    if (ready > 0)
                      _Attention(
                        icon: Icons.local_shipping_outlined,
                        color: const Color(0xFF7B1FA2),
                        text: '$ready order(s) ready to dispatch',
                        priority: 'High',
                        actionLabel: 'Dispatch',
                        onAction: () =>
                            setState(() => _filter = OrderStatus.packed),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // Queue header + filter.
                Row(
                  children: [
                    Text('Order queue',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (_filter != null)
                      TextButton(
                        onPressed: () => setState(() => _filter = null),
                        child: const Text('Show all'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),

                if (queue.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xl),
                    child: EmptyView(
                        message: 'No orders in this stage.',
                        icon: Icons.inventory_2_outlined),
                  )
                else
                  for (final o in queue)
                    _OrderCard(
                      order: o,
                      actionLabel: _actionLabel(o.status),
                      onAction: () => _advance(o),
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => OrderDetailScreen(order: o)),
                      ),
                    ),

                const SizedBox(height: AppSpacing.xl),
                Container(key: _lowStockKey),
                _LowStockTable(lowStock: lowStock),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.md),
                    child: LinearProgressIndicator(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---- KPI strip -------------------------------------------------------------

class _Kpi {
  _Kpi(this.label, this.value, this.color, {this.onTap, this.selected = false});
  final String label;
  final int value;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.items});
  final List<_Kpi> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 900 ? 5 : (c.maxWidth > 520 ? 3 : 2);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.7,
        children: [
          for (final k in items)
            Material(
              color: k.selected
                  ? k.color.withValues(alpha: 0.12)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: k.onTap,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: k.selected
                            ? k.color
                            : Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${k.value}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                  fontWeight: FontWeight.w800, color: k.color)),
                      Text(k.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

// ---- attention panel -------------------------------------------------------

class _Attention {
  _Attention({
    required this.icon,
    required this.color,
    required this.text,
    required this.priority,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final Color color;
  final String text;
  final String priority;
  final String actionLabel;
  final VoidCallback onAction;
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({required this.rows});
  final List<_Attention> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Text('All clear — nothing needs attention.',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text('Needs attention',
                  style: theme.textTheme.titleMedium),
            ),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _row(context, rows[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _Attention a) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Icon(a.icon, color: a.color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.text, style: theme.textTheme.bodyMedium),
                Text(a.priority,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: a.color, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: a.onAction,
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: a.color,
                backgroundColor: a.color.withValues(alpha: 0.12)),
            child: Text(a.actionLabel),
          ),
        ],
      ),
    );
  }
}

// ---- order card (order / customer / action focused) ------------------------

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.actionLabel,
    required this.onAction,
    required this.onOpen,
  });
  final Order order;
  final String? actionLabel;
  final VoidCallback onAction;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Order id + status
            Row(
              children: [
                Expanded(
                  child: Text(order.displayId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                AppStatusChip(
                    label: order.status.label,
                    statusValue: order.status.value),
              ],
            ),
            const SizedBox(height: 2),
            // 2. Customer
            Text(order.partyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            // 3. SKUs + value
            Row(
              children: [
                _meta(theme, Icons.grid_view_rounded,
                    '${order.itemCount} SKU(s)'),
                const SizedBox(width: AppSpacing.lg),
                _meta(theme, Icons.currency_rupee,
                    Formatters.money(order.grandTotal)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // 4. Actions
            Row(
              children: [
                OutlinedButton(onPressed: onOpen, child: const Text('Open')),
                const Spacer(),
                if (actionLabel != null)
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
}

// ---- low stock table -------------------------------------------------------

class _LowStockTable extends ConsumerWidget {
  const _LowStockTable({required this.lowStock});
  final List<Variant> lowStock;

  ({String label, Color color}) _urgency(Variant v) {
    if (v.currentStock <= 0) {
      return (label: 'OUT', color: AppColors.error);
    }
    if (v.currentStock <= v.minStock / 2) {
      return (label: 'CRITICAL', color: AppColors.error);
    }
    return (label: 'LOW', color: AppColors.warning);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final products = ref.watch(productsProvider).valueOrNull ?? const [];
    final names = {for (final p in products) p.id: p.name};
    final items = [...lowStock]
      ..sort((a, b) => a.currentStock.compareTo(b.currentStock));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text('Low stock monitor', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('${items.length}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: AppColors.error)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('All stock is above minimum. 👍',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              )
            else ...[
              // header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Row(
                  children: [
                    Expanded(flex: 5, child: _H('PRODUCT')),
                    Expanded(flex: 2, child: _H('AVAIL.')),
                    Expanded(flex: 2, child: _H('MIN')),
                    Expanded(flex: 3, child: _H('URGENCY')),
                  ],
                ),
              ),
              for (final v in items.take(30))
                _row(theme, names[v.productId] ?? 'Product', v),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String product, Variant v) {
    final u = _urgency(v);
    final size = v.attributes['Size'] ?? '';
    final unit = v.attributes['Size Unit'] ?? '';
    final label = size.isEmpty ? '' : '$size $unit'.trim();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (label.isNotEmpty)
                  Text(label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${v.currentStock}',
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: u.color)),
          ),
          Expanded(
              flex: 2,
              child: Text('${v.minStock}',
                  style: theme.textTheme.bodyMedium)),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: u.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(u.label,
                    style: TextStyle(
                        color: u.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant));
}
