import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_filter_chip_bar.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_status_chip.dart';
import '../../../core/widgets/state_views.dart';
import '../../client/presentation/client_orders_screen.dart' show OrderTile;
import '../domain/order.dart';
import '../domain/order_status.dart';
import 'order_detail_screen.dart';
import 'order_providers.dart';

/// Order Control Center — the admin's operational workspace. Surfaces orders
/// that need action (approval, packing, dispatch) and lets the admin drill into
/// any order with minimal clicks. UI only: reads [companyOrdersProvider] and
/// filters/searches the already-loaded list client-side; "View" opens the
/// existing [OrderDetailScreen] (same mechanism the previous screen used via
/// [OrderTile]).
class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  final _search = TextEditingController();
  String _query = '';
  OrderStatus? _filter; // null = all

  /// Filter row: All + every lifecycle status.
  // Delivered/Completed/Returned are retired from the workflow — don't offer
  // them as filters (historical orders still render their stored status fine).
  static final _filters = <OrderStatus?>[
    null,
    ...OrderStatus.values.where((s) =>
        s != OrderStatus.delivered &&
        s != OrderStatus.completed &&
        s != OrderStatus.returned),
  ];

  /// Statuses that count as booked revenue ("approved and beyond").
  static const _revenueStatuses = <OrderStatus>{
    OrderStatus.approved,
    OrderStatus.packing,
    OrderStatus.packed,
    OrderStatus.dispatched,
    OrderStatus.delivered,
    OrderStatus.completed,
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openOrder(Order order) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
      );

  int _count(List<Order> orders, OrderStatus s) =>
      orders.where((o) => o.status == s).length;

  List<Order> _visible(List<Order> orders) {
    var list = _filter == null
        ? orders
        : orders.where((o) => o.status == _filter).toList();
    if (_query.isNotEmpty) {
      list = list.where((o) {
        return ('${o.orderNo ?? ''} ${o.invoiceNo ?? ''}')
                .toLowerCase()
                .contains(_query) ||
            o.partyName.toLowerCase().contains(_query);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(companyOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Order Control Center'),
      ),
      body: ordersAsync.when(
        loading: () => const LoadingView(message: 'Loading orders…'),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(companyOrdersProvider),
        ),
        data: (orders) => LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final pad = isWide
                ? AppSpacing.pagePaddingDesktop
                : AppSpacing.pagePaddingMobile;
            final visible = _visible(orders);

            return ListView(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpacing.huge),
              children: [
                _StatRow(
                  orders: orders,
                  isWide: isWide,
                  count: (s) => _count(orders, s),
                  revenueStatuses: _revenueStatuses,
                  onTapStatus: (s) => setState(() => _filter = s),
                ),
                const SizedBox(height: AppSpacing.lg),
                _ActionRequiredPanel(
                  pending: _count(orders, OrderStatus.pending),
                  packing: _count(orders, OrderStatus.packing),
                  packed: _count(orders, OrderStatus.packed),
                  onReviewPending: () =>
                      setState(() => _filter = OrderStatus.pending),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSearchBar(
                  controller: _search,
                  hint: 'Search by order no. or dealer',
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
                const SizedBox(height: AppSpacing.md),
                AppFilterChipBar(
                  labels: [for (final f in _filters) f?.label ?? 'All'],
                  selectedIndex: _filters.indexOf(_filter),
                  onSelected: (i) => setState(() => _filter = _filters[i]),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionHeader(
                  title: 'Orders',
                  subtitle: '${visible.length} shown'
                      '${orders.length == visible.length ? '' : ' of ${orders.length}'}',
                ),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxl),
                    child: EmptyView(
                      message: 'No orders match your filters.',
                      icon: Icons.search_off,
                      action: FilledButton.tonal(
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                          _filter = null;
                        }),
                        child: const Text('Clear filters'),
                      ),
                    ),
                  )
                else if (isWide)
                  _OrdersTable(orders: visible, onView: _openOrder)
                else
                  for (final o in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: OrderTile(
                        order: o,
                        showParty: true,
                        onTap: () => _openOrder(o),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Responsive KPI strip: 2 columns on phone, 5 on wide screens.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.orders,
    required this.isWide,
    required this.count,
    required this.revenueStatuses,
    required this.onTapStatus,
  });

  final List<Order> orders;
  final bool isWide;
  final int Function(OrderStatus) count;
  final Set<OrderStatus> revenueStatuses;
  final ValueChanged<OrderStatus?> onTapStatus;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayRevenue = orders
        .where((o) =>
            revenueStatuses.contains(o.status) &&
            o.createdAt != null &&
            o.createdAt!.year == now.year &&
            o.createdAt!.month == now.month &&
            o.createdAt!.day == now.day)
        .fold<double>(0, (sum, o) => sum + o.grandTotal);

    final cards = <Widget>[
      _StatCard(
        icon: Icons.receipt_long_outlined,
        label: 'Total Orders',
        value: '${orders.length}',
        color: AppColors.primary,
        onTap: () => onTapStatus(null),
      ),
      _StatCard(
        icon: Icons.pending_actions,
        label: 'Pending Approval',
        value: '${count(OrderStatus.pending)}',
        color: AppStatusPalette.pending,
        onTap: () => onTapStatus(OrderStatus.pending),
      ),
      _StatCard(
        icon: Icons.inventory_2_outlined,
        label: 'Packing',
        value: '${count(OrderStatus.packing)}',
        color: AppStatusPalette.packing,
        onTap: () => onTapStatus(OrderStatus.packing),
      ),
      _StatCard(
        icon: Icons.local_shipping_outlined,
        label: 'Dispatch Ready',
        value: '${count(OrderStatus.packed)}',
        color: AppStatusPalette.packed,
        onTap: () => onTapStatus(OrderStatus.packed),
      ),
      _StatCard(
        icon: Icons.currency_rupee,
        label: "Today's Revenue",
        value: Formatters.moneyCompact(todayRevenue),
        color: AppColors.success,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 5 : 2,
        mainAxisExtent: 104,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemBuilder: (_, i) => cards[i],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Highlighted panel that spotlights orders needing action. Tapping the primary
/// button filters the list down to pending-approval orders.
class _ActionRequiredPanel extends StatelessWidget {
  const _ActionRequiredPanel({
    required this.pending,
    required this.packing,
    required this.packed,
    required this.onReviewPending,
  });

  final int pending;
  final int packing;
  final int packed;
  final VoidCallback onReviewPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nothingToDo = pending == 0 && packing == 0 && packed == 0;

    final headline = pending > 0
        ? '$pending order${pending == 1 ? '' : 's'} waiting for approval'
        : nothingToDo
            ? 'All caught up — nothing needs action'
            : 'No approvals pending';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: nothingToDo
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(
            nothingToDo ? Icons.check_circle_outline : Icons.priority_high,
            color: nothingToDo ? AppColors.success : scheme.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Action Required',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: nothingToDo
                        ? scheme.onSurfaceVariant
                        : scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: nothingToDo
                        ? scheme.onSurface
                        : scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (packing > 0 || packed > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$packing packing · $packed ready to dispatch',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: nothingToDo
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (pending > 0) ...[
            const SizedBox(width: AppSpacing.md),
            FilledButton.icon(
              onPressed: onReviewPending,
              icon: const Icon(Icons.rule),
              label: const Text('Review'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Wide-screen data table. Wrapped in a horizontal scroll view so it never
/// overflows on narrow desktop panes; the parent list handles vertical scroll.
class _OrdersTable extends StatelessWidget {
  const _OrdersTable({required this.orders, required this.onView});

  final List<Order> orders;
  final ValueChanged<Order> onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 720),
          child: DataTable(
            headingTextStyle: theme.textTheme.labelLarge,
            columns: const [
              DataColumn(label: Text('Order No')),
              DataColumn(label: Text('Dealer')),
              DataColumn(label: Text('Items'), numeric: true),
              DataColumn(label: Text('Amount'), numeric: true),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final o in orders)
                DataRow(
                  onSelectChanged: (_) => onView(o),
                  cells: [
                    DataCell(o.isBackorder
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(child: Text(o.displayId)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('Backorder',
                                  style: TextStyle(
                                      color: Color(0xFFB45309),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10)),
                            ),
                          ])
                        : Text(o.displayId)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          o.partyName.isEmpty ? '—' : o.partyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text('${o.itemCount}')),
                    DataCell(Text(Formatters.money(o.grandTotal))),
                    DataCell(AppStatusChip(
                      label: o.status.label,
                      statusValue: o.status.value,
                    )),
                    DataCell(Text(Formatters.date(o.createdAt))),
                    DataCell(
                      TextButton.icon(
                        onPressed: () => onView(o),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('View'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
