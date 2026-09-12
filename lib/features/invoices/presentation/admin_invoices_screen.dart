import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_skeleton_loader.dart';
import '../../../core/widgets/state_views.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_providers.dart';
import '../../orders/presentation/order_detail_screen.dart';
import '../../settings/domain/company_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../logic/invoice_pdf.dart';

/// Admin invoices — all company orders that carry an invoice number, in one
/// place: search, view, download and share. Reads existing providers.
class AdminInvoicesScreen extends ConsumerStatefulWidget {
  const AdminInvoicesScreen({super.key});

  @override
  ConsumerState<AdminInvoicesScreen> createState() =>
      _AdminInvoicesScreenState();
}

class _AdminInvoicesScreenState extends ConsumerState<AdminInvoicesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _hasInvoice(Order o) => o.invoiceNo != null;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(companyOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: ordersAsync.when(
        loading: () => const AppSkeletonList(rowHeight: 150),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(companyOrdersProvider)),
        data: (orders) {
          final invoiced = orders.where(_hasInvoice).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(2000))
                .compareTo(a.createdAt ?? DateTime(2000)));

          var list = invoiced;
          if (_query.isNotEmpty) {
            list = invoiced.where((o) {
              return (o.invoiceNo ?? '').toLowerCase().contains(_query) ||
                  (o.orderNo ?? '').toLowerCase().contains(_query) ||
                  o.partyName.toLowerCase().contains(_query);
            }).toList();
          }

          if (invoiced.isEmpty) {
            return const EmptyView(
              message: 'No invoices yet.\nInvoices appear once orders are '
                  'approved.',
              icon: Icons.receipt_long_outlined,
            );
          }

          // Group by month (newest first).
          final groups = <String, List<Order>>{};
          for (final o in list) {
            groups.putIfAbsent(Formatters.monthYear(o.createdAt), () => [])
                .add(o);
          }

          final now = DateTime.now();
          final monthAmount = invoiced
              .where((o) =>
                  o.createdAt != null &&
                  o.createdAt!.year == now.year &&
                  o.createdAt!.month == now.month)
              .fold<double>(0, (s, o) => s + o.grandTotal);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.huge),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _miniStat('Invoices', '${invoiced.length}',
                        Icons.receipt_long, AppColors.success),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _miniStat(
                        'This month',
                        Formatters.moneyCompact(monthAmount),
                        Icons.account_balance_wallet_outlined,
                        AppColors.info),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSearchBar(
                controller: _search,
                hint: 'Search invoice, order no. or dealer',
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
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
                      }),
                      child: const Text('Clear search'),
                    ),
                  ),
                )
              else
                for (final entry in groups.entries) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
                      ),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(label,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _open(Order o) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailScreen(order: o)));

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
  });

  final Order order;
  final VoidCallback onView;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                        Text(order.invoiceNo ?? '—',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontSize: 18)),
                        Text(
                            '${order.partyName.isEmpty ? 'Dealer' : order.partyName}'
                            ' · ${Formatters.date(order.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: const Text('Generated',
                        style: TextStyle(
                            color: AppColors.success,
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
                  _action(context, Icons.download, 'Download', onDownload),
                  _action(context, Icons.share_outlined, 'Share', onShare),
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
