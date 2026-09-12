import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_filter_chip_bar.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_skeleton_loader.dart';
import '../../../core/widgets/state_views.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../invoices/logic/invoice_pdf.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/domain/order.dart';
import '../../orders/domain/order_status.dart';
import '../../orders/presentation/order_providers.dart';
import '../../settings/domain/company_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../application/cart_provider.dart';
import 'client_cart_screen.dart';
import 'client_categories_screen.dart';
import 'client_order_detail_screen.dart';

/// Invoices — an ERP-style invoice management module over approved orders
/// (which carry an invoice number). UI redesign only; reads existing providers.
class ClientInvoicesScreen extends ConsumerStatefulWidget {
  const ClientInvoicesScreen({super.key});

  @override
  ConsumerState<ClientInvoicesScreen> createState() =>
      _ClientInvoicesScreenState();
}

class _ClientInvoicesScreenState extends ConsumerState<ClientInvoicesScreen> {
  final _search = TextEditingController();
  String _query = '';
  int _filter = 1; // 0 All, 1 Generated, 2 Pending

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _hasInvoice(Order o) => o.invoiceNo != null;
  bool _isPending(Order o) => o.invoiceNo == null && !o.status.isTerminal;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(clientOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Invoices'),
            Text(
              ordersAsync.when(
                data: (o) =>
                    '${o.where(_hasInvoice).length} invoices generated',
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
      body: ordersAsync.when(
        loading: () => const AppSkeletonList(rowHeight: 150),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(clientOrdersProvider)),
        data: (orders) {
          if (orders.isEmpty) {
            return EmptyView(
              message: 'No invoices found.\nInvoices appear after approved '
                  'orders are processed.',
              icon: Icons.receipt_long_outlined,
              action: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ClientCategoriesScreen())),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Start ordering'),
              ),
            );
          }

          final now = DateTime.now();
          final generated = orders.where(_hasInvoice).toList();
          final monthAmount = generated
              .where((o) =>
                  o.createdAt != null &&
                  o.createdAt!.year == now.year &&
                  o.createdAt!.month == now.month)
              .fold<double>(0, (s, o) => s + o.grandTotal);

          // Apply filter + search.
          var list = switch (_filter) {
            1 => orders.where(_hasInvoice).toList(),
            2 => orders.where(_isPending).toList(),
            _ => orders,
          };
          if (_query.isNotEmpty) {
            list = list.where((o) {
              return (o.invoiceNo ?? '').toLowerCase().contains(_query) ||
                  Formatters.date(o.createdAt).toLowerCase().contains(_query);
            }).toList();
          }

          // Group by month (newest first).
          final groups = <String, List<Order>>{};
          for (final o in list) {
            groups.putIfAbsent(Formatters.monthYear(o.createdAt), () => [])
                .add(o);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.huge),
            children: [
              _summary(orders, generated.length, monthAmount),
              const SizedBox(height: AppSpacing.lg),
              AppSearchBar(
                controller: _search,
                hint: 'Search invoice or date',
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: AppSpacing.md),
              AppFilterChipBar(
                labels: const ['All', 'Generated', 'Pending'],
                selectedIndex: _filter,
                onSelected: (i) => setState(() => _filter = i),
              ),
              const SizedBox(height: AppSpacing.md),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxl),
                  child: EmptyView(
                    message: 'No matching invoices.',
                    icon: Icons.search_off,
                    action: FilledButton.tonal(
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                        _filter = 1;
                      }),
                      child: const Text('Clear search'),
                    ),
                  ),
                )
              else
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm),
                    child: Text(entry.key,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  for (final o in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _InvoiceCard(
                        order: o,
                        onView: () => _open(o),
                        onDownload: () => _invoice(o),
                        onShare: () => _invoice(o, share: true),
                        onRepeat: () => _repeat(o),
                      ),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _summary(List<Order> orders, int generated, double monthAmount) {
    final pending = orders.where(_isPending).length;
    return SizedBox(
      height: 156,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          AppDashboardCard(
            width: 140,
            icon: Icons.receipt_long,
            value: '$generated',
            subtitle: 'Generated',
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.md),
          AppDashboardCard(
            width: 140,
            icon: Icons.hourglass_empty,
            value: '$pending',
            subtitle: 'Pending',
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.md),
          AppDashboardCard(
            width: 190,
            icon: Icons.account_balance_wallet_outlined,
            value: Formatters.moneyCompact(monthAmount),
            subtitle: 'This month',
            color: AppColors.info,
          ),
        ],
      ),
    );
  }

  void _open(Order o) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClientOrderDetailScreen(order: o, initialTab: 2)));

  Future<void> _invoice(Order o, {bool share = false}) async {
    if (o.invoiceNo == null) {
      _snack('Invoice will be available after approval.');
      return;
    }
    try {
      final items =
          await ref.read(orderRepositoryProvider).watchItems(o.id).first;
      final variants = ref.read(allVariantsProvider).valueOrNull ?? const [];
      final s = ref.read(companySettingsProvider).valueOrNull ??
          CompanySettings(companyId: o.companyId);
      final bytes = await buildInvoicePdf(
          order: o, items: items, settings: s, variants: variants);
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: '${o.invoiceNo}.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) => bytes, name: o.invoiceNo!);
      }
    } catch (e) {
      _snack('Could not open invoice: $e');
    }
  }

  Future<void> _repeat(Order o) async {
    try {
      final items =
          await ref.read(orderRepositoryProvider).watchItems(o.id).first;
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
      _snack('Could not repeat: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.order,
    required this.onView,
    required this.onDownload,
    required this.onShare,
    required this.onRepeat,
  });

  final Order order;
  final VoidCallback onView;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final generated = order.invoiceNo != null;
    final negative = order.status.isTerminal &&
        order.status != OrderStatus.completed &&
        !generated;
    final (color, label) = negative
        ? (AppColors.error, order.status.label)
        : generated
            ? (AppColors.success, 'Generated')
            : (AppColors.warning, 'Pending');

    return Card(
      child: InkWell(
        onTap: onView,
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
                        Text(order.invoiceNo ?? 'Awaiting invoice',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontSize: 18)),
                        Text(Formatters.date(order.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12)),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.xl),
              Row(
                children: [
                  Text('${order.itemCount} product(s)',
                      style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  Text(Formatters.money(order.grandTotal),
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  _action(context, Icons.visibility_outlined, 'View', onView),
                  if (generated) ...[
                    _action(
                        context, Icons.download, 'Download', onDownload),
                    _action(
                        context, Icons.share_outlined, 'Share', onShare),
                  ],
                  _action(context, Icons.refresh, 'Repeat', onRepeat),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
