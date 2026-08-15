import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_category_card.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_greeting.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/app_notification_button.dart';
import '../../../core/widgets/app_quick_action_card.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_skeleton_loader.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../categories/presentation/category_providers.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/domain/order_status.dart';
import '../../orders/presentation/order_providers.dart';
import '../../parties/presentation/party_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import 'client_catalog_screen.dart';
import 'client_categories_screen.dart';
import 'client_invoices_screen.dart';
import 'client_order_detail_screen.dart';
import 'client_orders_screen.dart';

/// Client home — a premium business dashboard (not a shopping homepage).
/// Reads existing providers only; no business logic changes. Composed entirely
/// from the shared `App*` component library.
class ClientHomeDashboardScreen extends ConsumerWidget {
  const ClientHomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final party = ref.watch(currentPartyProvider).valueOrNull;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final ordersAsync = ref.watch(clientOrdersProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final unread = ref.watch(unreadNotificationsProvider);

    final name = (party?.name.isNotEmpty ?? false)
        ? party!.name
        : (user?.name.isNotEmpty ?? false)
            ? user!.name
            : 'there';

    // Skeleton while first load resolves — never a blank screen.
    final showSkeleton = ordersAsync.isLoading &&
        ref.watch(categoriesProvider).isLoading;

    final logo =
        appImageProvider(ref.watch(companySettingsProvider).valueOrNull?.logoUrl);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: logo == null ? AppSpacing.lg : 4,
        leadingWidth: logo == null ? null : 60,
        leading: logo == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: AppSpacing.md),
                child: Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant),
                  ),
                  child: Image(image: logo, fit: BoxFit.contain),
                ),
              ),
        title: AppGreeting(name: name, compact: true),
        actions: [
          AppNotificationButton(
            count: unread,
            onTap: () => context.go('/client/notifications'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg, left: 4),
            child: GestureDetector(
              onTap: () => context.go('/client/profile'),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCatalog(context),
        icon: const Icon(Icons.add_shopping_cart_outlined),
        label: const Text('New Order'),
      ),
      body: showSkeleton
          ? const AppSkeletonDashboard()
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(clientOrdersProvider);
                ref.invalidate(categoriesProvider);
                ref.invalidate(currentPartyProvider);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.huge,
                ),
                children: [
                  Text(
                    "Ready to place today's order?",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SummaryRow(ordersAsync: ordersAsync),
                  const SizedBox(height: AppSpacing.xxl),
                  AppSearchBar(
                    hint: 'Search products',
                    readOnly: true,
                    onTap: () => _openCatalog(context),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  const AppSectionHeader(title: 'Quick actions'),
                  _QuickActions(onNewOrder: () => _openCatalog(context)),
                  const SizedBox(height: AppSpacing.xxl),
                  if (categories.isNotEmpty) ...[
                    AppSectionHeader(
                      title: 'Categories',
                      action: TextButton(
                        onPressed: () => _openCatalog(context),
                        child: const Text('View all'),
                      ),
                    ),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount:
                            categories.where((c) => c.isActive).length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.md),
                        itemBuilder: (context, i) {
                          final c = categories
                              .where((c) => c.isActive)
                              .toList()[i];
                          return AppCategoryCard(
                            name: c.name,
                            imageUrl: c.imageUrl,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ClientCatalogScreen(
                                  initialCategoryId: c.id,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                  AppSectionHeader(
                    title: 'Recent orders',
                    action: TextButton(
                      onPressed: () => context.go('/client/orders'),
                      child: const Text('View all'),
                    ),
                  ),
                  _RecentOrders(
                    ordersAsync: ordersAsync,
                    onBrowse: () => _openCatalog(context),
                  ),
                ],
              ),
            ),
    );
  }

  // "Place order" opens the fast Categories grid.
  void _openCatalog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientCategoriesScreen()),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.ordersAsync});
  final AsyncValue<List<Order>> ordersAsync;

  @override
  Widget build(BuildContext context) {
    final orders = ordersAsync.valueOrNull ?? const [];
    final pending =
        orders.where((o) => o.status == OrderStatus.pending).length;
    final approved =
        orders.where((o) => o.status == OrderStatus.approved).length;
    final now = DateTime.now();
    // Only dispatched orders count toward this month's total.
    final monthTotal = orders
        .where((o) =>
            o.status == OrderStatus.dispatched &&
            o.createdAt != null &&
            o.createdAt!.year == now.year &&
            o.createdAt!.month == now.month)
        .fold<double>(0, (sum, o) => sum + o.grandTotal);

    return SizedBox(
      height: 118,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          AppDashboardCard(
            icon: Icons.schedule,
            value: '$pending',
            subtitle: 'Pending',
            color: AppStatusPalette.pending,
          ),
          const SizedBox(width: AppSpacing.md),
          AppDashboardCard(
            icon: Icons.check_circle_outline,
            value: '$approved',
            subtitle: 'Approved',
            color: AppStatusPalette.approved,
          ),
          const SizedBox(width: AppSpacing.md),
          AppDashboardCard(
            icon: Icons.account_balance_wallet_outlined,
            value: Formatters.money(monthTotal),
            subtitle: 'Dispatched this month',
            color: AppColors.info,
            width: 200,
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onNewOrder});
  final VoidCallback onNewOrder;

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.add_shopping_cart_outlined, 'Place order', onNewOrder),
      (
        Icons.receipt_long_outlined,
        'My orders',
        () => context.go('/client/orders'),
      ),
      (
        Icons.receipt_long_outlined,
        'Invoices',
        () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ClientInvoicesScreen())),
      ),
      (Icons.person_outline, 'Profile', () => context.go('/client/profile')),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 2.4,
      children: [
        for (final a in actions)
          AppQuickActionCard(icon: a.$1, label: a.$2, onTap: a.$3),
      ],
    );
  }
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.ordersAsync, required this.onBrowse});
  final AsyncValue<List<Order>> ordersAsync;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return ordersAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: LoadingView(),
      ),
      error: (e, _) => ErrorView(error: e),
      data: (orders) {
        if (orders.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: EmptyView(
              message: 'No orders yet.\nStart your first order by browsing '
                  'categories.',
              icon: Icons.receipt_long_outlined,
              action: FilledButton.icon(
                onPressed: onBrowse,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Browse Categories'),
              ),
            ),
          );
        }
        final recent = orders.take(5).toList();
        return Column(
          children: [
            for (final o in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: OrderTile(
                  order: o,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ClientOrderDetailScreen(order: o),
                  )),
                ),
              ),
          ],
        );
      },
    );
  }
}
