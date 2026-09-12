import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_filter_chip_bar.dart';
import '../../../core/widgets/app_lazy_list.dart';
import '../../../core/widgets/app_order_timeline.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_skeleton_loader.dart';
import '../../../core/widgets/app_status_chip.dart';
import '../../../core/widgets/state_views.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/domain/order.dart';
import '../../orders/domain/order_status.dart';
import '../../orders/presentation/order_detail_screen.dart';
import '../../orders/presentation/order_providers.dart';
import '../../invoices/logic/invoice_pdf.dart';
import '../../settings/domain/company_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../application/cart_provider.dart';
import 'client_cart_screen.dart';
import 'client_categories_screen.dart';
import 'client_order_detail_screen.dart';

/// My Orders — a B2B order-management dashboard (not a "my packages" list).
/// Health analytics, status counts, filters and per-order tracking. UI only.
class ClientOrdersScreen extends ConsumerStatefulWidget {
  const ClientOrdersScreen({super.key});

  @override
  ConsumerState<ClientOrdersScreen> createState() =>
      _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends ConsumerState<ClientOrdersScreen> {
  final _search = TextEditingController();
  String _query = '';
  OrderStatus? _filter; // null = all

  static const _filters = <OrderStatus?>[
    null,
    OrderStatus.pending,
    OrderStatus.approved,
    OrderStatus.packing,
    OrderStatus.dispatched,
    OrderStatus.cancelled,
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(clientOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('My Orders'),
            Text(
              ordersAsync.when(
                data: (o) => '${o.length} total orders',
                loading: () => 'Loading…',
                error: (_, __) => '',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ClientCategoriesScreen())),
        icon: const Icon(Icons.add),
        label: const Text('New Order'),
      ),
      body: ordersAsync.when(
        loading: () => const AppSkeletonList(rowHeight: 150),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(clientOrdersProvider)),
        data: (orders) {
          if (orders.isEmpty) {
            return EmptyView(
              message: 'No orders found.\nYour submitted orders will appear '
                  'here.',
              icon: Icons.receipt_long_outlined,
              action: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ClientCategoriesScreen())),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Start ordering'),
              ),
            );
          }

          final counts = <OrderStatus, int>{};
          for (final o in orders) {
            counts[o.status] = (counts[o.status] ?? 0) + 1;
          }

          var list = _filter == null
              ? orders
              : orders.where((o) => o.status == _filter).toList();
          if (_query.isNotEmpty) {
            list = list.where((o) {
              return ('${o.orderNo ?? ''} ${o.invoiceNo ?? ''}')
                      .toLowerCase()
                      .contains(_query) ||
                  o.status.label.toLowerCase().contains(_query) ||
                  Formatters.date(o.createdAt).toLowerCase().contains(_query);
            }).toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HealthCard(orders: orders),
                    const SizedBox(height: AppSpacing.lg),
                    _summaryCards(counts),
                    const SizedBox(height: AppSpacing.lg),
                    AppSearchBar(
                      controller: _search,
                      hint: 'Search order, invoice or date',
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppFilterChipBar(
                      labels: [for (final f in _filters) f?.label ?? 'All'],
                      selectedIndex: _filters.indexOf(_filter),
                      onSelected: (i) => setState(() => _filter = _filters[i]),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxl),
                        child: EmptyView(
                          message: 'No matching orders.',
                          icon: Icons.search_off,
                          action: FilledButton.tonal(
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                              _filter = null;
                            }),
                            child: const Text('Clear search'),
                          ),
                        ),
                      )
                    : AppLazyListView<Order>(
                        items: list,
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0,
                            AppSpacing.lg, AppSpacing.huge),
                        separatorHeight: AppSpacing.md,
                        itemBuilder: (context, o, index) => _OrderCard(
                          order: o,
                          onTap: () => _openDetail(o),
                          onDuplicate: () => _duplicate(o),
                          onInvoice: () => _invoice(o),
                          onLongPress: () => _actions(o),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCards(Map<OrderStatus, int> counts) {
    Widget card(OrderStatus s, IconData icon) => Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: AppDashboardCard(
            width: 130,
            icon: icon,
            value: '${counts[s] ?? 0}',
            subtitle: s.label,
            color: AppStatusPalette.forOrder(s.value),
            onTap: () => setState(() => _filter = s),
          ),
        );
    return SizedBox(
      height: 140,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          card(OrderStatus.pending, Icons.schedule),
          card(OrderStatus.approved, Icons.check_circle_outline),
          card(OrderStatus.packing, Icons.inventory_2_outlined),
          card(OrderStatus.dispatched, Icons.local_shipping_outlined),
          card(OrderStatus.cancelled, Icons.cancel_outlined),
        ],
      ),
    );
  }

  // ---- actions ----
  void _openDetail(Order o, {int tab = 0}) => Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => ClientOrderDetailScreen(order: o, initialTab: tab)));

  Future<List<OrderItem>> _items(String orderId) =>
      ref.read(orderRepositoryProvider).watchItems(orderId).first;

  Future<void> _duplicate(Order o) async {
    try {
      final items = await _items(o.id);
      for (final it in items) {
        ref.read(cartProvider.notifier).addVariant(
              variantId: it.variantId,
              productName: it.productName,
              variantLabel: it.variantLabel,
              rate: it.rate,
              qty: it.quantity,
              discountPercent: it.discountPercent,
            );
      }
      if (mounted) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ClientCartScreen()));
      }
    } catch (e) {
      _snack('Could not duplicate: $e');
    }
  }

  Future<void> _invoice(Order o) async {
    if (o.invoiceNo == null) {
      _snack('Invoice will be available after approval.');
      return;
    }
    try {
      final items = await _items(o.id);
      final variants = ref.read(allVariantsProvider).valueOrNull ?? const [];
      final settings = ref.read(companySettingsProvider).valueOrNull ??
          CompanySettings(companyId: o.companyId);
      await Printing.layoutPdf(
        onLayout: (_) => buildInvoicePdf(
            order: o, items: items, settings: settings, variants: variants),
        name: o.invoiceNo ?? 'invoice',
      );
    } catch (e) {
      _snack('Could not open invoice: $e');
    }
  }

  void _actions(Order o) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timeline),
              title: const Text('Track order'),
              onTap: () {
                Navigator.pop(context);
                _openDetail(o, tab: 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Invoice'),
              onTap: () {
                Navigator.pop(context);
                _invoice(o);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Duplicate order'),
              onTap: () {
                Navigator.pop(context);
                _duplicate(o);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}

/// This-month health analytics (submitted / approved / … / completion rate).
class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final month = orders
        .where((o) =>
            o.createdAt != null &&
            o.createdAt!.year == now.year &&
            o.createdAt!.month == now.month)
        .toList();
    int c(OrderStatus s) => month.where((o) => o.status == s).length;
    final submitted = month.length;
    final fulfilled = c(OrderStatus.dispatched);
    final rate = submitted == 0 ? 0 : ((fulfilled / submitted) * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text('This month', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('$rate% dispatched',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: AppColors.success)),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                _stat(theme, 'Submitted', submitted),
                _stat(theme, 'Approved', c(OrderStatus.approved)),
                _stat(theme, 'Packing', c(OrderStatus.packing)),
                _stat(theme, 'Dispatched', c(OrderStatus.dispatched)),
                _stat(theme, 'Cancelled', c(OrderStatus.cancelled)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(ThemeData theme, String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Rich order card with amount + a lifecycle timeline. Swipe left = duplicate,
/// swipe right = invoice, long-press = actions.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onTap,
    required this.onDuplicate,
    required this.onInvoice,
    required this.onLongPress,
  });

  final Order order;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onInvoice;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('order_${order.id}'),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onInvoice();
        } else {
          onDuplicate();
        }
        return false;
      },
      background: _bg(context, Icons.picture_as_pdf_outlined, AppColors.info,
          left: true),
      secondaryBackground:
          _bg(context, Icons.copy, AppColors.primary, left: false),
      child: Card(
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.displayId,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontSize: 17),
                          ),
                          Text(Formatters.dateTime(order.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AppStatusChip(
                            label: order.status.label,
                            statusValue: order.status.value),
                        if (order.isBackorder) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
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
                        ],
                      ],
                    ),
                  ],
                ),
                if (order.isBackorder && order.backorderOfNo != null) ...[
                  const SizedBox(height: 6),
                  Text('From short order ${order.backorderOfNo}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB45309),
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Text('${order.itemCount} product(s)',
                        style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    Text(Formatters.money(order.grandTotal),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        )),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppOrderTimeline(statusValue: order.status.value),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bg(BuildContext context, IconData icon, Color color,
      {required bool left}) {
    return Container(
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Icon(icon, color: color),
    );
  }
}

/// Shared order list tile (compact) — used by the home dashboard's recent list
/// (client) and the admin orders list. [onTap] overrides the default
/// destination (admin → order detail; client → order tracking).
/// An order row, arranged top-down: company (party) name → PO No → date & time
/// → total amount → total weight, with a status chip. Weight is resolved from
/// the order's line items + variants. Used in the same layout for every status.
class OrderTile extends ConsumerWidget {
  const OrderTile({
    super.key,
    required this.order,
    this.showParty = false,
    this.onTap,
  });
  final Order order;
  final bool showParty; // admin lists show the dealer name as the heading
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final items = ref.watch(orderItemsProvider(order.id)).valueOrNull ?? const [];
    final vlist = ref.watch(allVariantsProvider).valueOrNull ?? const [];
    final byId = {for (final v in vlist) v.id: v};
    final weight = orderTotalWeightText(items, byId);

    // Heading = company/party name on admin, order no. on the client's own list.
    final heading = showParty ? order.partyName : order.displayId;

    Widget muted(String text) => Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant));

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ??
            () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(order: order)),
                ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(heading.isEmpty ? '—' : heading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    if (showParty) muted('PO No: ${order.displayId}'),
                    muted(Formatters.dateTime(order.createdAt)),
                    const SizedBox(height: 4),
                    Text('Total: ${Formatters.money(order.grandTotal)}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (weight != '-')
                      Text('Total weight: $weight',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AppStatusChip(
                      label: order.status.label,
                      statusValue: order.status.value),
                  if (order.isBackorder) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Backorder',
                          style: TextStyle(
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.w700,
                              fontSize: 10)),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Icon(Icons.chevron_right,
                      size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
