import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_delivery_card.dart';
import '../../../core/widgets/app_hero_status_card.dart';
import '../../../core/widgets/app_info_banner.dart';
import '../../../core/widgets/app_invoice_card.dart';
import '../../../core/widgets/app_order_totals_card.dart';
import '../../../core/widgets/app_product_review_card.dart';
import '../../../core/widgets/app_progress_indicator.dart';
import '../../../core/widgets/app_status_chip.dart';
import '../../../core/widgets/app_support_card.dart';
import '../../../core/widgets/app_timeline_step.dart';
import '../../../core/widgets/state_views.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../invoices/logic/invoice_pdf.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/domain/order.dart';
import '../../orders/domain/order_status.dart';
import '../../orders/presentation/order_providers.dart';
import '../../parties/presentation/party_providers.dart';
import '../../settings/domain/company_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../application/cart_provider.dart';
import 'client_cart_screen.dart';

/// Unified Order Details — a single source of truth for a submitted purchase
/// order, organised into Details / Timeline / Invoice tabs. UI redesign only.
class ClientOrderDetailScreen extends ConsumerStatefulWidget {
  const ClientOrderDetailScreen({
    super.key,
    required this.order,
    this.initialTab = 0,
  });

  final Order order;
  final int initialTab; // 0 Details, 1 Timeline, 2 Invoice

  @override
  ConsumerState<ClientOrderDetailScreen> createState() =>
      _ClientOrderDetailScreenState();
}

class _ClientOrderDetailScreenState
    extends ConsumerState<ClientOrderDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: 3, vsync: this, initialIndex: widget.initialTab);

  static const _steps = [
    'Order received',
    'Approved',
    'Packing',
    'Packed',
    'Dispatched',
  ];

  Order get order => widget.order;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _deleteOrder() async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete order'),
        content: const Text('Delete this order? This cannot be undone. '
            'Orders can only be deleted before they are dispatched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(orderRepositoryProvider).deleteOrder(order.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Order deleted.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(companySettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Order Details'),
            Text(order.displayId,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (order.invoiceNo != null)
            IconButton(
              tooltip: 'Download invoice',
              onPressed: () => _invoice(settings),
              icon: const Icon(Icons.download),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'repeat') _repeat();
              if (v == 'delete') _deleteOrder();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'repeat', child: Text('Repeat order')),
              if (OrderRepository.canDelete(order.status))
                const PopupMenuItem(
                    value: 'delete', child: Text('Delete order')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.displayId,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    AppStatusChip(
                        label: order.status.label,
                        statusValue: order.status.value),
                  ],
                ),
              ),
              TabBar(
                controller: _tab,
                tabs: const [
                  Tab(text: 'Details'),
                  Tab(text: 'Timeline'),
                  Tab(text: 'Invoice'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _detailsTab(),
          _timelineTab(),
          _invoiceTab(settings),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  // ---------------------------------------------------------------------------
  // Details tab
  // ---------------------------------------------------------------------------
  Widget _detailsTab() {
    final theme = Theme.of(context);
    final items = ref.watch(orderItemsProvider(order.id));
    final party = ref.watch(currentPartyProvider).valueOrNull;

    // Split the stored discount into product-level vs the order-wide global %.
    final lines = items.valueOrNull ?? const <OrderItem>[];
    final afterProduct = lines.fold<double>(0, (s, it) => s + it.total);
    final productDiscount =
        (order.subtotal - afterProduct).clamp(0, double.infinity).toDouble();
    final globalDiscount = (order.discountTotal - productDiscount)
        .clamp(0, double.infinity)
        .toDouble();

    // Total order weight (resolved from each line's variant), shown in every
    // status.
    final variants = ref.watch(allVariantsProvider).valueOrNull ?? const [];
    final variantById = {for (final v in variants) v.id: v};
    double grams = 0;
    for (final it in lines) {
      final v = variantById[it.variantId];
      if (v == null) continue;
      final w = double.tryParse(v.attributes['Weight'] ?? '') ?? 0;
      final u = (v.attributes['Weight Unit'] ?? '').trim().toLowerCase();
      grams += (u == 'kg' ? w * 1000 : w) * it.quantity;
    }
    String? weightText;
    if (grams > 0) {
      String f(double x) =>
          x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(2);
      weightText = grams >= 1000 ? '${f(grams / 1000)} kg' : '${f(grams)} gm';
    }

    final address = [
      party?.address,
      party?.city,
      party?.state,
      party?.pincode,
    ].where((e) => e != null && e.isNotEmpty).join(', ');

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (order.status == OrderStatus.rejected &&
            (order.rejectionReason?.isNotEmpty ?? false)) ...[
          AppInfoBanner(
            icon: Icons.cancel_outlined,
            title: 'Order rejected',
            color: AppColors.error,
            message: order.rejectionReason!,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text('Order information', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                _info('Order ID', order.displayId),
                _info('Order date', Formatters.date(order.createdAt)),
                _info('Party', order.partyName),
                if (party?.paymentTerms != null &&
                    party!.paymentTerms!.isNotEmpty)
                  _info('Payment terms', party.paymentTerms!),
                if (party?.transport != null && party!.transport!.isNotEmpty)
                  _info('Transport', party.transport!),
                _info('Approval', order.status.label),
                _info('Invoice',
                    order.invoiceNo != null ? 'Generated' : 'Pending'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Ordered products (${order.itemCount})',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        items.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl), child: LoadingView()),
          error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(orderItemsProvider(order.id))),
          data: (list) => Column(
            children: [
              for (final it in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppProductReviewCard(
                    name: it.productName,
                    variantLabel: it.variantLabel,
                    quantity: Formatters.qty(it.quantity),
                    rate: Formatters.money(it.rate),
                    total: Formatters.money(it.total),
                    discount: it.discountPercent > 0
                        ? '${_pct(it.discountPercent)}%'
                        : null,
                    // Client may remove a line only while the order is still
                    // pending (before the admin approves it).
                    onDelete: order.status == OrderStatus.pending
                        ? () => _deleteLine(it, list.length)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Total weight sits above the order summary — always shown, in every
        // status ("—" when no line has a weight set).
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.scale_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Total weight', style: theme.textTheme.bodyLarge),
                const Spacer(),
                Text(weightText ?? '—',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppOrderTotalsCard(
          rows: [
            ('Total amount', Formatters.money(order.subtotal)),
            if (productDiscount > 0.01)
              ('Product discount', '- ${Formatters.money(productDiscount)}'),
            if (globalDiscount > 0.01)
              ('Cash discount (${_pct(order.globalDiscountPercent)}%)',
                  '- ${Formatters.money(globalDiscount)}'),
            if (order.taxTotal > 0)
              ('GST (${_pct(AppConstants.gstRate)}%)',
                  '+ ${Formatters.money(order.taxTotal)}'),
          ],
          grandTotalLabel: 'Final amount',
          grandTotalValue: Formatters.money(order.grandTotal),
        ),
        if (order.discountTotal > 0) ...[
          const SizedBox(height: AppSpacing.md),
          AppInfoBanner(
            icon: Icons.savings_outlined,
            title: 'You saved ${Formatters.money(order.discountTotal)}',
            color: AppColors.success,
            message: 'Applied with your dealer discount.',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppDeliveryCard(
          partyName: order.partyName,
          address: address,
          phone: party?.phone,
          transport: party?.transport,
        ),
        if (order.note != null && order.note!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order note', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(order.note!),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _info(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: theme.textTheme.titleMedium),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Timeline tab
  // ---------------------------------------------------------------------------
  Widget _timelineTab() {
    final theme = Theme.of(context);
    final settings = ref.watch(companySettingsProvider).valueOrNull;
    final meta = _meta(order.status);
    final negative = order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.rejected ||
        order.status == OrderStatus.returned;
    final progress = negative ? 0.0 : (meta.active / 5).clamp(0.0, 1.0);
    final lastUpdated = order.approvedAt ?? order.createdAt;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppHeroStatusCard(
          orderNumber: order.displayId,
          statusLabel: order.status.label,
          statusColor: meta.color,
          icon: meta.icon,
          description: meta.desc,
          nextStep: meta.next,
          lastUpdated:
              lastUpdated == null ? null : Formatters.dateTime(lastUpdated),
          pulse: !negative && order.status != OrderStatus.completed,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!negative)
          AppProgressIndicator(
            progress: progress,
            stageLabel: meta.desc,
            caption: meta.next != null ? 'Next: ${meta.next}' : null,
          ),
        const SizedBox(height: AppSpacing.xl),
        Text('Progress timeline', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.lg),
        if (negative)
          AppTimelineStep(
            title: order.status.label,
            state: TimelineState.done,
            isLast: true,
            description: 'This order is ${order.status.label.toLowerCase()}.',
          )
        else
          for (var i = 0; i < _steps.length; i++)
            AppTimelineStep(
              title: _steps[i],
              isLast: i == _steps.length - 1,
              state: i < meta.active
                  ? TimelineState.done
                  : i == meta.active
                      ? TimelineState.current
                      : TimelineState.future,
              description: _stepDesc(i, meta.active),
              timestamp: i == 0
                  ? Formatters.dateTime(order.createdAt)
                  : (i == 1 && order.approvedAt != null
                      ? Formatters.dateTime(order.approvedAt)
                      : null),
              updatedBy: i == 1 ? order.approvedByName : null,
            ),
        const SizedBox(height: AppSpacing.sm),
        AppSupportCard(
          phone: settings?.supportNumber.isNotEmpty == true
              ? settings!.supportNumber
              : settings?.phone,
          email: settings?.email,
          onTapContact: (v) {
            Clipboard.setData(ClipboardData(text: v));
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Copied: $v')));
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Invoice tab
  // ---------------------------------------------------------------------------
  Widget _invoiceTab(CompanySettings? settings) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppInvoiceCard(
          invoiceNumber: order.invoiceNo,
          amount: Formatters.money(order.grandTotal),
          generatedDate: order.approvedAt == null
              ? null
              : Formatters.date(order.approvedAt),
          onDownload: () => _invoice(settings),
          onShare: () => _invoice(settings, share: true),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  Widget _bottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
            top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _repeat,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Repeat order'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _tab.animateTo(1),
                  icon: const Icon(Icons.timeline),
                  label: const Text('Track order'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _invoice(CompanySettings? settings, {bool share = false}) async {
    if (order.invoiceNo == null) {
      _snack('Invoice will be available after approval.');
      return;
    }
    try {
      final items =
          await ref.read(orderRepositoryProvider).watchItems(order.id).first;
      final variants = ref.read(allVariantsProvider).valueOrNull ?? const [];
      final s = settings ?? CompanySettings(companyId: order.companyId);
      final bytes = await buildInvoicePdf(
          order: order, items: items, settings: s, variants: variants);
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: '${order.invoiceNo}.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) => bytes, name: order.invoiceNo!);
      }
    } catch (e) {
      _snack('Could not open invoice: $e');
    }
  }

  Future<void> _repeat() async {
    try {
      final items =
          await ref.read(orderRepositoryProvider).watchItems(order.id).first;
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

  /// Deletes a line from a still-pending order (with confirmation) and lets the
  /// order totals recompute automatically.
  Future<void> _deleteLine(OrderItem it, int totalLines) async {
    if (totalLines <= 1) {
      _snack('This is the only product. Cancel the whole order instead.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product variant'),
        content: Text(
            'Are you sure you want to delete "${it.productName} · ${it.variantLabel}" '
            'from this order? The total will be recalculated.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(orderRepositoryProvider)
          .updateItemQuantity(order.id, it.id, 0, markModified: false);
      _snack('Product removed. Total updated.');
    } catch (e) {
      _snack('Could not remove: $e');
    }
  }

  String? _stepDesc(int i, int active) {
    switch (i) {
      case 0:
        return 'Order placed and received.';
      case 1:
        return 'Order approved by the team.';
      case 2:
        return i == active
            ? 'Packing in progress.'
            : 'Warehouse will pack the order.';
      case 3:
        return 'Packed and ready to dispatch.';
      case 4:
        return 'Order dispatched.';
      case 5:
        return 'Order delivered.';
    }
    return null;
  }

  static String _pct(double p) => p % 1 == 0 ? p.toStringAsFixed(0) : '$p';

  ({IconData icon, Color color, String desc, String? next, int active}) _meta(
      OrderStatus s) {
    final color = AppStatusPalette.forOrder(s.value);
    switch (s) {
      case OrderStatus.pending:
        return (icon: Icons.schedule, color: color, desc: 'Awaiting admin approval', next: 'Approval', active: 1);
      case OrderStatus.approved:
        return (icon: Icons.check_circle, color: color, desc: 'Order approved', next: 'Packing', active: 2);
      case OrderStatus.packing:
        return (icon: Icons.inventory_2, color: color, desc: 'Packing in progress', next: 'Dispatch', active: 2);
      case OrderStatus.packed:
        return (icon: Icons.inventory, color: color, desc: 'Packed and ready', next: 'Dispatch', active: 3);
      case OrderStatus.dispatched:
        return (icon: Icons.local_shipping, color: color, desc: 'Order dispatched', next: null, active: 5);
      case OrderStatus.delivered:
        return (icon: Icons.task_alt, color: color, desc: 'Order dispatched', next: null, active: 5);
      case OrderStatus.completed:
        return (icon: Icons.verified, color: color, desc: 'Order dispatched', next: null, active: 5);
      case OrderStatus.cancelled:
        return (icon: Icons.cancel, color: color, desc: 'Order cancelled', next: null, active: 0);
      case OrderStatus.rejected:
        return (icon: Icons.block, color: color, desc: 'Order rejected', next: null, active: 0);
      default:
        return (icon: Icons.receipt_long, color: color, desc: order.status.label, next: null, active: 0);
    }
  }
}
