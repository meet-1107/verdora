import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../orders/domain/order.dart';
import '../../orders/domain/order_status.dart';
import '../../orders/presentation/order_providers.dart';

/// Admin command center: what needs doing now (work queue) first, then today's
/// business numbers, then a lightweight status breakdown. UI only — every value
/// is derived from existing providers.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final ordersAsync = ref.watch(companyOrdersProvider);
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          _Greeting(name: user?.name),
          const SizedBox(height: AppSpacing.xl),
          ordersAsync.when(
            loading: () => const _DashboardSkeleton(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxl),
              child: ErrorView(
                error: e,
                onRetry: () => ref.invalidate(companyOrdersProvider),
              ),
            ),
            data: (orders) => _DashboardBody(orders: orders),
          ),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Good day 👋', style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${name ?? 'Admin'} · ${Formatters.date(DateTime.now())}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The data-backed portion: work queue + today's numbers + status breakdown.
class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.orders});
  final List<Order> orders;

  bool _isToday(DateTime? d) {
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  int _count(OrderStatus s) => orders.where((o) => o.status == s).length;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStock = ref.watch(lowStockVariantsProvider).length;

    final pending = _count(OrderStatus.pending);
    // "Packing" = approved-awaiting-pack + actively packing.
    final packing =
        _count(OrderStatus.approved) + _count(OrderStatus.packing);
    final readyToDispatch = _count(OrderStatus.packed);

    // Today's business.
    final todays = orders.where((o) => _isToday(o.createdAt)).toList();
    const revenueStatuses = {
      OrderStatus.approved,
      OrderStatus.packing,
      OrderStatus.packed,
      OrderStatus.dispatched,
      OrderStatus.delivered,
      OrderStatus.completed,
    };
    final todaysRevenue = todays
        .where((o) => revenueStatuses.contains(o.status))
        .fold<double>(0, (sum, o) => sum + o.grandTotal);
    final todaysPending =
        todays.where((o) => o.status == OrderStatus.pending).length;
    final todaysApproved =
        todays.where((o) => o.status == OrderStatus.approved).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Work queue',
          subtitle: 'What needs your attention right now',
        ),
        _ActionGrid(
          cards: [
            _ActionCardData(
              label: 'Pending approval',
              count: pending,
              icon: Icons.pending_actions_outlined,
              color: AppStatusPalette.pending,
              actionLabel: 'Review',
              onTap: () => context.go('/admin/orders'),
            ),
            _ActionCardData(
              label: 'Packing',
              count: packing,
              icon: Icons.inventory_2_outlined,
              color: AppStatusPalette.packing,
              actionLabel: 'Open',
              onTap: () => context.go('/admin/orders'),
            ),
            _ActionCardData(
              label: 'Ready to dispatch',
              count: readyToDispatch,
              icon: Icons.local_shipping_outlined,
              color: AppStatusPalette.dispatched,
              actionLabel: 'Open',
              onTap: () => context.go('/admin/orders'),
            ),
            _ActionCardData(
              label: 'Low stock',
              count: lowStock,
              icon: Icons.warning_amber_outlined,
              color: AppColors.error,
              actionLabel: 'Manage',
              onTap: () => context.go('/admin/inventory'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        const AppSectionHeader(
          title: "Today's business",
          subtitle: 'Orders and revenue created today',
        ),
        _StatGrid(
          stats: [
            _StatData(
              label: 'Orders',
              value: Formatters.qty(todays.length),
              icon: Icons.receipt_long_outlined,
              color: AppColors.primary,
            ),
            _StatData(
              label: 'Pending',
              value: Formatters.qty(todaysPending),
              icon: Icons.hourglass_bottom_outlined,
              color: AppStatusPalette.pending,
            ),
            _StatData(
              label: 'Approved',
              value: Formatters.qty(todaysApproved),
              icon: Icons.check_circle_outline,
              color: AppStatusPalette.approved,
            ),
            _StatData(
              label: 'Revenue',
              value: Formatters.moneyCompact(todaysRevenue),
              icon: Icons.payments_outlined,
              color: AppColors.brandGreen,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        const AppSectionHeader(
          title: 'Orders by status',
          subtitle: 'All open and completed orders',
        ),
        _StatusBreakdown(orders: orders),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Work queue action cards
// ---------------------------------------------------------------------------

class _ActionCardData {
  const _ActionCardData({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.actionLabel,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final String actionLabel;
  final VoidCallback onTap;
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.cards});
  final List<_ActionCardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 1000
          ? 4
          : constraints.maxWidth > 640
              ? 2
              : 1;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.lg,
        // A little more height (esp. single column) so the icon row, label and
        // action button never overflow — including at larger text scales.
        childAspectRatio: cols == 1 ? 2.4 : 1.3,
        children: [for (final c in cards) _ActionCard(data: c)],
      );
    });
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.data});
  final _ActionCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWork = data.count > 0;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Icon(data.icon, color: data.color, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    Formatters.qty(data.count),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: hasWork ? data.color : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                data.label,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: data.onTap,
                  style: TextButton.styleFrom(
                    foregroundColor: data.color,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(data.actionLabel),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today's business stat cards
// ---------------------------------------------------------------------------

class _StatData {
  const _StatData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final List<_StatData> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 900 ? 4 : 2;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.lg,
        childAspectRatio: 1.7,
        children: [for (final s in stats) _StatCard(data: s)],
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(data.icon, color: data.color, size: 20),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                data.value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              data.label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Orders-by-status breakdown (simple, compiles with existing data)
// ---------------------------------------------------------------------------

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (orders.isEmpty) {
      return const EmptyView(
        message: 'No orders yet.\nNew orders will show up here.',
        icon: Icons.receipt_long_outlined,
      );
    }

    // Preserve lifecycle order; only show statuses that have orders.
    final counts = <OrderStatus, int>{};
    for (final o in orders) {
      counts[o.status] = (counts[o.status] ?? 0) + 1;
    }
    final present =
        OrderStatus.values.where((s) => (counts[s] ?? 0) > 0).toList();
    final maxCount =
        counts.values.fold<int>(0, (m, v) => v > m ? v : m).clamp(1, 1 << 30);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            for (final s in present) ...[
              _StatusBar(
                label: s.label,
                count: counts[s]!,
                fraction: counts[s]! / maxCount,
                color: AppStatusPalette.forOrder(s.value),
              ),
              if (s != present.last)
                const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.label,
    required this.count,
    required this.fraction,
    required this.color,
  });

  final String label;
  final int count;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 32,
          child: Text(
            Formatters.qty(count),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppSpacing.huge),
      child: LoadingView(message: 'Loading your command center…'),
    );
  }
}
