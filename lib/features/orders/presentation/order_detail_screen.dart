import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_status_chip.dart';
import '../../../core/widgets/state_views.dart';
import '../../activity/data/activity_repository.dart';
import '../../activity/presentation/activity_logs_screen.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../categories/presentation/category_providers.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../invoices/logic/invoice_pdf.dart';
import '../../notifications/data/notification_repository.dart';
import '../../parties/domain/party.dart';
import '../../products/domain/product.dart';
import '../../products/domain/variant.dart';
import '../../products/presentation/product_providers.dart';
import '../../subcategories/presentation/subcategory_providers.dart';
import '../../parties/presentation/party_providers.dart';
import '../../settings/domain/company_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/order_repository.dart';
import '../domain/order.dart';
import '../domain/order_status.dart';
import 'order_providers.dart';

/// Order Command Center — one page to process an order end to end: review the
/// dealer, products and timeline, then approve / reject / advance status without
/// leaving the screen. The order is watched live so status changes reflect
/// in-place. Business logic is unchanged (approve/markDispatched/setStatus).
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.order});
  final Order order;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  bool _busy = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Live order (so status updates reflect after an action) with the passed-in
  /// order as fallback.
  Order _liveOrder() {
    final all = ref.watch(companyOrdersProvider).valueOrNull;
    if (all != null) {
      for (final o in all) {
        if (o.id == widget.order.id) return o;
      }
    }
    return widget.order;
  }

  Future<void> _act(Future<void> Function() action, String ok) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(Order o) => o.displayId;
  String? get _uid => ref.read(currentUserProvider).valueOrNull?.uid;

  void _approve(Order o) {
    final repo = ref.read(orderRepositoryProvider);
    final logger = ref.read(activityLoggerProvider);
    final notifier = ref.read(notificationRepositoryProvider);
    _act(() async {
      final invoice = await repo.approve(o.id, modified: o.modified);
      await logger.record('order.approved', target: _label(o));
      await notifier.notifyParty(
        companyId: o.companyId,
        partyId: o.partyId,
        title: o.modified ? 'Order modified & approved' : 'Order approved',
        body: '✅ Your order ${o.displayId} has been '
            '${o.modified ? 'modified and approved' : 'approved'}. '
            'Invoice $invoice.',
      );
    }, 'Order approved — client notified.');
  }

  void _packing(Order o) {
    final repo = ref.read(orderRepositoryProvider);
    final logger = ref.read(activityLoggerProvider);
    _act(() async {
      await repo.startPacking(o.id);
      await logger.record('order.packing', target: _label(o));
      await _notifyStatus(o, OrderStatus.packing);
    }, 'Packing started — client notified.');
  }

  void _advance(Order o, OrderStatus next) {
    final repo = ref.read(orderRepositoryProvider);
    final logger = ref.read(activityLoggerProvider);
    // Packing goes through a dialog so the admin can pack only what's available
    // and split the short items into a pending backorder.
    if (next == OrderStatus.packed) {
      _packSplit(o);
      return;
    }
    // Stock is deducted when the order is DISPATCHED (the packed quantities).
    if (next == OrderStatus.dispatched) {
      _act(() async {
        await repo.markDispatched(o, createdBy: _uid);
        await logger.record('order.dispatched', target: _label(o));
        await _notifyStatus(o, OrderStatus.dispatched);
      }, 'Dispatched — stock deducted, client notified.');
      return;
    }
    _act(() async {
      await repo.setStatus(o.id, next);
      await logger.record('order.${next.value}', target: _label(o));
      await _notifyStatus(o, next);
    }, 'Marked ${next.label} — client notified.');
  }

  /// Confirms Mark Packed. The pack quantity per line comes from the Products
  /// tab: an UNPICKED line packs 0 (fully backordered); a picked line packs its
  /// (possibly edited-down) quantity. Anything short of the agreed quantity is
  /// listed for confirmation, then split into a PENDING backorder.
  Future<void> _packSplit(Order o) async {
    final items = ref.read(orderItemsProvider(o.id)).valueOrNull ?? const [];
    if (items.isEmpty) return;

    // Pack now = picked ? current qty : 0 (capped at the agreed quantity).
    final packByItem = <String, int>{
      for (final it in items)
        it.id: it.picked
            ? (it.quantity > it.orderedTotal ? it.orderedTotal : it.quantity)
            : 0,
    };
    // Build the short-list for the confirmation message.
    final shorts = <({String label, int short})>[];
    var anyPack = false;
    for (final it in items) {
      final pack = packByItem[it.id]!;
      if (pack > 0) anyPack = true;
      final short = it.orderedTotal - pack;
      if (short > 0) {
        shorts.add((
          label: [it.productName, it.variantLabel]
              .where((s) => s.trim().isNotEmpty)
              .join(' · '),
          short: short,
        ));
      }
    }

    if (!anyPack) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pick at least one item before marking packed.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _PackConfirmDialog(shorts: shorts),
    );
    if (confirmed != true) return;

    final repo = ref.read(orderRepositoryProvider);
    final logger = ref.read(activityLoggerProvider);
    await _act(() async {
      final back = await repo.packWithBackorder(order: o, packByItem: packByItem);
      await logger.record('order.packed', target: _label(o));
      await _notifyStatus(o, OrderStatus.packed);
      if (back != null) {
        await ref.read(notificationRepositoryProvider).notifyParty(
              companyId: o.companyId,
              partyId: o.partyId,
              title: 'Some items backordered',
              body: 'A few items of order ${o.displayId} were short and moved '
                  'to a new pending order ${back.orderNo}. They will be sent '
                  'once back in stock.',
            );
      }
    },
        shorts.isEmpty
            ? 'Packed — client notified.'
            : 'Packed — short items moved to a pending backorder.');
  }

  /// Sends the dealer an in-app notification describing a status change. Approve
  /// / reject / edit send their own richer messages; this covers every other
  /// transition (packing, packed, dispatched, delivered, completed, …).
  Future<void> _notifyStatus(Order o, OrderStatus status) {
    return ref.read(notificationRepositoryProvider).notifyParty(
          companyId: o.companyId,
          partyId: o.partyId,
          title: 'Order ${status.label}',
          body: _statusBody(o.displayId, status),
        );
  }

  String _statusBody(String id, OrderStatus s) {
    switch (s) {
      case OrderStatus.packing:
        return '📦 Your order $id is now being packed.';
      case OrderStatus.packed:
        return '📦 Your order $id is packed and ready to dispatch.';
      case OrderStatus.dispatched:
        return '🚚 Your order $id has been dispatched.';
      case OrderStatus.delivered:
        return '✅ Your order $id has been delivered.';
      case OrderStatus.completed:
        return '🎉 Your order $id is now completed.';
      case OrderStatus.cancelled:
        return '⚠️ Your order $id has been cancelled.';
      case OrderStatus.returned:
        return '↩️ Your order $id has been marked as returned.';
      default:
        return 'Your order $id status changed to ${s.label}.';
    }
  }

  Future<void> _reject(Order o) async {
    final reason = await _promptReason(
        title: 'Reject order',
        message: 'Are you sure you want to reject / cancel this order? '
            'The dealer will be notified. This cannot be undone.',
        hint: 'Reason (shared with dealer)');
    if (reason == null) return;
    if (reason.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('A rejection reason is required.')));
      }
      return;
    }
    final repo = ref.read(orderRepositoryProvider);
    final logger = ref.read(activityLoggerProvider);
    final notifier = ref.read(notificationRepositoryProvider);
    _act(() async {
      await repo.reject(o.id, reason);
      await logger.record('order.rejected', target: _label(o));
      await notifier.notifyParty(
        companyId: o.companyId,
        partyId: o.partyId,
        title: 'Order rejected',
        body: '❌ Your order ${o.displayId} was rejected. Reason: $reason',
      );
    }, 'Order rejected — client notified.');
  }

  Future<void> _deleteOrder(Order o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete order'),
        content: Text(
          o.stockDeducted
              ? 'Delete this order permanently? This cannot be undone. '
                  'The dispatched quantities will be returned to stock.'
              : 'Delete this order permanently? This cannot be undone.',
        ),
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
    setState(() => _busy = true);
    try {
      await ref.read(orderRepositoryProvider).deleteOrder(o.id, createdBy: _uid);
      await ref
          .read(activityLoggerProvider)
          .record('order.deleted', target: _label(o));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Order deleted.')));
        Navigator.pop(context); // leave the (now-gone) detail screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        setState(() => _busy = false);
      }
    }
  }

  /// Cancels an order (status → cancelled) and notifies the dealer. Kept in the
  /// menu alongside Change status / Delete for quick access.
  Future<void> _cancelOrder(Order o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel order'),
        content: const Text('Cancel this order? The dealer will be notified.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep order')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(orderRepositoryProvider);
    final logger = ref.read(activityLoggerProvider);
    final notifier = ref.read(notificationRepositoryProvider);
    _act(() async {
      await repo.setStatus(o.id, OrderStatus.cancelled);
      await logger.record('order.cancelled', target: _label(o));
      await notifier.notifyParty(
        companyId: o.companyId,
        partyId: o.partyId,
        title: 'Order cancelled',
        body: '⚠️ Your order ${o.displayId} has been cancelled.',
      );
    }, 'Order cancelled — client notified.');
  }

  /// Runs the correct handler for any chosen status (flexible/manual change).
  void _applyStatus(Order o, OrderStatus s) {
    switch (s) {
      case OrderStatus.approved:
        _approve(o);
      case OrderStatus.packing:
        _packing(o);
      case OrderStatus.rejected:
        _reject(o);
      default:
        _advance(o, s);
    }
  }

  Future<void> _promptChangeStatus(Order o) async {
    final chosen = await showModalBottomSheet<OrderStatus>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('Change status',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final s in OrderStatus.values)
              if (s != o.status &&
                  s != OrderStatus.delivered &&
                  s != OrderStatus.completed &&
                  s != OrderStatus.returned)
                ListTile(
                  leading: Icon(Icons.circle,
                      size: 14, color: AppStatusPalette.forOrder(s.value)),
                  title: Text(s.label),
                  onTap: () => Navigator.pop(sheetContext, s),
                ),
          ],
        ),
      ),
    );
    if (chosen != null) _applyStatus(o, chosen);
  }

  Future<String?> _promptReason(
      {required String title, required String hint, String? message}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) ...[
              Text(message,
                  style: Theme.of(dialogContext).textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(labelText: hint),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('No, keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Yes, reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _printInvoice(Order order) async {
    final items =
        ref.read(orderItemsProvider(order.id)).valueOrNull ?? const [];
    final variants = ref.read(allVariantsProvider).valueOrNull ?? const [];
    final settings = ref.read(companySettingsProvider).valueOrNull ??
        CompanySettings(companyId: order.companyId);
    try {
      await Printing.layoutPdf(
        onLayout: (_) => buildInvoicePdf(
            order: order,
            items: items,
            settings: settings,
            variants: variants),
        name: order.invoiceNo ?? 'invoice',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open invoice: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _liveOrder();
    final isAdmin =
        ref.watch(currentUserProvider).valueOrNull?.role.isAdminSide ?? false;
    final party = _partyFor(order);

    // Warehouse pick completion — "Mark Packed" is blocked until every line
    // has been pulled from the warehouse.
    final items =
        ref.watch(orderItemsProvider(order.id)).valueOrNull ?? const [];
    final pickComplete = items.isNotEmpty && items.every((i) => i.picked);

    // Dispatched (or later) → the whole order is read-only.
    final locked = _orderLocked(order.status);

    return Scaffold(
      appBar: AppBar(
        title: Text(order.displayId),
        actions: [
          if (order.invoiceNo != null)
            IconButton(
              tooltip: 'Invoice PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _printInvoice(order),
            ),
          if (isAdmin &&
              (!locked || OrderRepository.canAdminDelete(order.status)))
            Builder(builder: (context) {
              final canCancel = !locked &&
                  order.status != OrderStatus.cancelled &&
                  order.status != OrderStatus.rejected;
              return PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'status') _promptChangeStatus(order);
                  if (v == 'cancel') _cancelOrder(order);
                  if (v == 'delete') _deleteOrder(order);
                },
                itemBuilder: (_) => [
                  if (!locked)
                    const PopupMenuItem(
                        value: 'status', child: Text('Change status…')),
                  if (canCancel)
                    const PopupMenuItem(
                        value: 'cancel',
                        child: Text('Cancel order',
                            style: TextStyle(color: AppColors.error))),
                  if (OrderRepository.canAdminDelete(order.status))
                    const PopupMenuItem(
                        value: 'delete', child: Text('Delete order')),
                ],
              );
            }),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Column(
          children: [
            _HeroCard(
              order: order,
              party: party,
              isAdmin: isAdmin,
              busy: _busy,
              pickComplete: pickComplete,
              onApprove: () => _approve(order),
              onReject: () => _reject(order),
              onPacking: () => _packing(order),
              onAdvance: (s) => _advance(order, s),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Products'),
                  Tab(text: 'Timeline'),
                  Tab(text: 'Invoice'),
                  Tab(text: 'Activity'),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _OverviewTab(order: order, party: party),
                  // Dispatched orders are read-only (no qty/pick edits).
                  _ProductsTab(order: order, isAdmin: isAdmin && !locked),
                  _TimelineTab(order: order),
                  _InvoiceTab(
                    order: order,
                    onPrint: () => _printInvoice(order),
                    canApprove: isAdmin && order.status == OrderStatus.pending,
                    onApprove: () => _approve(order),
                  ),
                  _ActivityTab(order: order),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Party? _partyFor(Order order) {
    final parties = ref.watch(partiesProvider).valueOrNull;
    if (parties == null) return null;
    for (final p in parties) {
      if (p.id == order.partyId || p.partyCode == order.partyId) return p;
    }
    return null;
  }
}

/// Total order weight resolved from each line's variant (cart items don't store
/// weight). Sums in grams and shows kg once it reaches 1000 g, else grams.
/// Returns '-' when no line has a weight.
String orderTotalWeightText(
    List<OrderItem> items, Map<String, Variant> variantsById) {
  double grams = 0;
  for (final it in items) {
    final v = variantsById[it.variantId];
    if (v == null) continue;
    final w = double.tryParse(v.attributes['Weight'] ?? '') ?? 0;
    final unit = (v.attributes['Weight Unit'] ?? '').trim().toLowerCase();
    grams += (unit == 'kg' ? w * 1000 : w) * it.quantity;
  }
  if (grams <= 0) return '-';
  String fmt(double x) =>
      x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(2);
  return grams >= 1000 ? '${fmt(grams / 1000)} kg' : '${fmt(grams)} gm';
}

/// Once an order is dispatched (or beyond) it is frozen: no quantity edits,
/// no product changes and no further status changes.
bool _orderLocked(OrderStatus s) => const {
      OrderStatus.dispatched,
      OrderStatus.delivered,
      OrderStatus.completed,
      OrderStatus.returned,
    }.contains(s);

// ---------------------------------------------------------------------------
// Hero card + actions
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.order,
    required this.party,
    required this.isAdmin,
    required this.busy,
    required this.pickComplete,
    required this.onApprove,
    required this.onReject,
    required this.onPacking,
    required this.onAdvance,
  });

  final Order order;
  final Party? party;
  final bool isAdmin;
  final bool busy;

  /// True when every line has been picked from the warehouse. "Mark Packed" is
  /// disabled until this is true (only relevant while the order is packing).
  final bool pickComplete;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onPacking;
  final ValueChanged<OrderStatus> onAdvance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(party?.name ?? order.partyName,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                        '${party?.partyCode ?? order.partyId} · '
                        '${Formatters.date(order.createdAt)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    if (order.placedByAdmin)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.admin_panel_settings_outlined,
                                size: 14, color: scheme.primary),
                            const SizedBox(width: 4),
                            Text('Placed by admin',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              AppStatusChip(
                  label: order.status.label, statusValue: order.status.value),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Grand total',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  Text(Formatters.money(order.grandTotal),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const Spacer(),
              Text('${order.itemCount} item(s)',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          if (isAdmin &&
              !_orderLocked(order.status) &&
              order.status.nextStates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                // Cancel lives in the ⋮ menu, so don't repeat it inline.
                for (final next in order.status.nextStates)
                  if (next != OrderStatus.cancelled)
                    _actionButton(context, next),
              ],
            ),
            if (order.status == OrderStatus.packing) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Mark Packed lets you pack the available quantity; short '
                        'items move to a pending backorder.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ],
          ],
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.md),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext context, OrderStatus next) {
    switch (next) {
      case OrderStatus.approved:
        return FilledButton.icon(
          onPressed: onApprove,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Approve'),
        );
      case OrderStatus.rejected:
        return OutlinedButton.icon(
          onPressed: onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
          ),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Reject'),
        );
      case OrderStatus.packing:
        return FilledButton.icon(
          onPressed: onPacking,
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: const Text('Start packing'),
        );
      case OrderStatus.cancelled:
        return OutlinedButton.icon(
          onPressed: () => onAdvance(next),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          icon: const Icon(Icons.block, size: 18),
          label: const Text('Cancel'),
        );
      case OrderStatus.packed:
        // Packing opens a dialog to choose the available quantity per line, so
        // it's always available (the dialog handles short items → backorder).
        return FilledButton.tonalIcon(
          onPressed: () => onAdvance(next),
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: const Text('Mark Packed'),
        );
      default:
        return FilledButton.tonalIcon(
          onPressed: () => onAdvance(next),
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: Text('Mark ${next.label}'),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Overview tab
// ---------------------------------------------------------------------------

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.order, required this.party});
  final Order order;
  final Party? party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Total order weight (resolved from each line's variant), shown in every
    // status so admins always see the shipment weight.
    final items =
        ref.watch(orderItemsProvider(order.id)).valueOrNull ?? const [];
    final vlist = ref.watch(allVariantsProvider).valueOrNull ?? const [];
    final byId = {for (final v in vlist) v.id: v};
    final weightText = orderTotalWeightText(items, byId);

    // Two-stage discount split: product-level discount vs the order-wide cash
    // (global) discount. Derived from stored totals + line totals.
    final afterProduct = items.fold<double>(0, (s, it) => s + it.total);
    final productDiscount =
        (order.subtotal - afterProduct).clamp(0, double.infinity).toDouble();
    final cashDiscount = (order.discountTotal - productDiscount)
        .clamp(0, double.infinity)
        .toDouble();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _DealerCard(party: party, order: order),
        if (order.isBackorder) ...[
          const SizedBox(height: AppSpacing.md),
          _BackorderBanner(
            icon: Icons.assignment_return_outlined,
            color: const Color(0xFF1565C0),
            text: 'Backorder of ${order.backorderOfNo ?? 'a previous order'} '
                '— these items were short on that order.',
          ),
        ],
        if (order.backorderId != null) ...[
          const SizedBox(height: AppSpacing.md),
          _BackorderBanner(
            icon: Icons.inventory_2_outlined,
            color: AppColors.warning,
            text: 'Some items were short and moved to backorder '
                '${order.backorderNo ?? ''}.',
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        // Total weight sits above the order summary — always shown, in every
        // status ("—" when no line has a weight set).
        _WeightCard(weightText: weightText == '-' ? '—' : weightText),
        const SizedBox(height: AppSpacing.md),
        _SummaryCard(
          order: order,
          productDiscount: productDiscount,
          cashDiscount: cashDiscount,
        ),
        if (order.note != null && order.note!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _InfoCard(title: 'Notes', child: Text(order.note!)),
        ],
      ],
    );
  }
}

/// A compact card showing the order's total shipment weight, placed above the
/// order summary.
class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.weightText});
  final String weightText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
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
            Text(weightText,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _DealerCard extends StatelessWidget {
  const _DealerCard({required this.party, required this.order});
  final Party? party;
  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(IconData icon, String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Text('$label: ', style: theme.textTheme.bodySmall),
            Expanded(
                child: Text(value,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }

    return _InfoCard(
      title: 'Dealer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(party?.name ?? order.partyName,
              style: theme.textTheme.titleMedium),
          row(Icons.badge_outlined, 'Party ID',
              party?.partyCode ?? order.partyId),
          row(Icons.person_outline, 'Owner', party?.ownerName),
          row(Icons.phone_outlined, 'Phone', party?.phone),
          row(Icons.email_outlined, 'Email', party?.email),
          row(Icons.receipt_outlined, 'GST', party?.gstNumber),
          row(Icons.location_city_outlined, 'City', party?.city),
          if (party != null && party!.creditLimit > 0)
            row(Icons.account_balance_wallet_outlined, 'Credit limit',
                Formatters.money(party!.creditLimit)),
          if (party != null && party!.defaultDiscount > 0)
            row(Icons.percent_outlined, 'Cash discount',
                '${party!.defaultDiscount}%'),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.order,
    required this.productDiscount,
    required this.cashDiscount,
  });
  final Order order;
  final double productDiscount;
  final double cashDiscount;

  static String _pct(double p) => p == p.roundToDouble()
      ? p.toStringAsFixed(0)
      : p.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Order summary',
      child: Column(
        children: [
          _amountRow(context, 'Subtotal', order.subtotal),
          if (productDiscount > 0.01)
            _amountRow(context, 'Product discount', -productDiscount),
          if (cashDiscount > 0.01)
            _amountRow(
                context,
                'Cash discount (${_pct(order.globalDiscountPercent)}%)',
                -cashDiscount),
          if (order.taxTotal > 0)
            _amountRow(context, 'GST (${_pct(AppConstants.gstRate)}%)',
                order.taxTotal),
          const Divider(),
          _amountRow(context, 'Grand total', order.grandTotal, bold: true),
        ],
      ),
    );
  }
}

Widget _amountRow(BuildContext context, String label, double value,
    {bool bold = false}) {
  final style = bold
      ? Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w800)
      : Theme.of(context).textTheme.bodyMedium;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(Formatters.money(value), style: style),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6)),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Products tab
// ---------------------------------------------------------------------------

class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab({required this.order, required this.isAdmin});
  final Order order;
  final bool isAdmin;

  @override
  ConsumerState<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<_ProductsTab> {
  final Set<String> _expanded = {}; // expanded product groups (by group key)

  Order get order => widget.order;
  bool get isAdmin => widget.isAdmin;

  /// Warehouse pick checklist is available to admins only while an order is in
  /// packing/packed. It is hidden in approved/modified-approved (picking hasn't
  /// started) and once dispatched.
  static const _pickStages = {
    OrderStatus.packing,
    OrderStatus.packed,
  };
  bool get _canPick => isAdmin && _pickStages.contains(order.status);

  Future<void> _togglePick(OrderItem it, bool picked) async {
    try {
      await ref.read(orderRepositoryProvider).setItemPicked(it.id, picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  Future<void> _togglePickAll(List<OrderItem> items, bool picked) async {
    try {
      await ref
          .read(orderRepositoryProvider)
          .setItemsPicked(items.map((e) => e.id), picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  Widget _sectionHeader(String title, {required bool category}) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          left: category ? 0 : 8, top: category ? 4 : 8, bottom: 6),
      child: Row(
        children: [
          Icon(category ? Icons.folder_rounded : Icons.account_tree_rounded,
              size: category ? 18 : 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (category
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.titleSmall)
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(orderItemsProvider(order.id));
    final variantsById = {
      for (final v in ref.watch(allVariantsProvider).valueOrNull ?? const [])
        v.id: v
    };
    final products = ref.watch(productsProvider).valueOrNull ?? const <Product>[];
    final productById = {for (final p in products) p.id: p};
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final catName = {for (final c in cats) c.id: c.name};
    final subcats = ref.watch(subcategoriesProvider).valueOrNull ?? const [];
    final subName = {for (final s in subcats) s.id: s.name};

    // Length value (only shown when a variant provides it).
    String lengthOf(OrderItem it) {
      final v = variantsById[it.variantId];
      if (v == null) return '-';
      final l = (v.attributes['Length'] ?? '').trim();
      final lu = (v.attributes['Length Unit'] ?? '').trim();
      if (l.isEmpty) return '-';
      return lu.isEmpty ? l : '$l $lu';
    }

    // Size value WITHOUT its unit; falls back to the stored variant label.
    String sizeOf(OrderItem it) {
      final v = variantsById[it.variantId];
      final s = (v?.attributes['Size'] ?? '').trim();
      return s.isEmpty ? it.variantLabel : s;
    }

    // Admin-set pack capacities (pieces). 0 = not set.
    int boxSizeOf(OrderItem it) => variantsById[it.variantId]?.boxPack ?? 0;
    int packSizeOf(OrderItem it) => variantsById[it.variantId]?.pack ?? 0;

    return items.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
          error: e, onRetry: () => ref.invalidate(orderItemsProvider(order.id))),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView(message: 'No line items on this order.');
        }

        // Bucket line items under their product; unmatched fall back to name.
        final itemsByProduct = <String, List<OrderItem>>{};
        final unknown = <String, List<OrderItem>>{};
        for (final it in list) {
          final v = variantsById[it.variantId];
          final p = v != null ? productById[v.productId] : null;
          if (p == null) {
            unknown.putIfAbsent(it.productName, () => []).add(it);
          } else {
            itemsByProduct.putIfAbsent(p.id, () => []).add(it);
          }
        }

        // Category → Subcategory → Product tree.
        final tree = <String, Map<String, List<String>>>{};
        for (final pid in itemsByProduct.keys) {
          final p = productById[pid]!;
          tree
              .putIfAbsent(p.categoryId, () => {})
              .putIfAbsent(p.subcategoryId ?? '', () => [])
              .add(pid);
        }

        _OrderProductGroup group(
                String key, String name, List<OrderItem> its) =>
            _OrderProductGroup(
              productName: name,
              items: its,
              isAdmin: isAdmin,
              lengthOf: lengthOf,
              sizeOf: sizeOf,
              boxSizeOf: boxSizeOf,
              packSizeOf: packSizeOf,
              canPick: _canPick,
              onTogglePick: _togglePick,
              onTogglePickAll: _togglePickAll,
              expanded: _expanded.contains(key),
              onToggle: () => setState(() => _expanded.contains(key)
                  ? _expanded.remove(key)
                  : _expanded.add(key)),
              onEdit: (it) => _editQty(
                context,
                it,
                stock: variantsById[it.variantId]?.currentStock,
                boxSize: boxSizeOf(it),
                packSize: packSizeOf(it),
              ),
            );

        final children = <Widget>[];
        final catIds = tree.keys.toList()
          ..sort((a, b) => (catName[a] ?? '')
              .toLowerCase()
              .compareTo((catName[b] ?? '').toLowerCase()));
        for (final catId in catIds) {
          children
              .add(_sectionHeader(catName[catId] ?? 'Category', category: true));
          final subMap = tree[catId]!;
          final subIds = subMap.keys.toList()
            ..sort((a, b) {
              if (a.isEmpty) return 1;
              if (b.isEmpty) return -1;
              return (subName[a] ?? '')
                  .toLowerCase()
                  .compareTo((subName[b] ?? '').toLowerCase());
            });
          for (final subId in subIds) {
            if (subId.isNotEmpty) {
              children.add(_sectionHeader(subName[subId] ?? 'Subcategory',
                  category: false));
            }
            final pids = subMap[subId]!
              ..sort((a, b) => productById[a]!
                  .name
                  .toLowerCase()
                  .compareTo(productById[b]!.name.toLowerCase()));
            for (final pid in pids) {
              children.add(Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: group(pid, productById[pid]!.name, itemsByProduct[pid]!),
              ));
            }
          }
        }
        for (final e in unknown.entries) {
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: group(e.key, e.key, e.value),
          ));
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: children,
        );
      },
    );
  }

  Future<void> _editQty(
    BuildContext context,
    OrderItem it, {
    int? stock,
    required int boxSize,
    required int packSize,
  }) async {
    final res = await showDialog<int>(
      context: context,
      builder: (_) => _QtyPackDialog(
        label: it.variantLabel,
        initialQty: it.quantity,
        boxSize: boxSize,
        packSize: packSize,
        stock: stock,
      ),
    );
    if (res == null) return;
    // Sentinel from the dialog's "Delete size" button.
    if (res < 0) {
      if (context.mounted) await _confirmDeleteLine(context, it);
      return;
    }
    final newQty = res;
    if (newQty == it.quantity) return;
    try {
      final repo = ref.read(orderRepositoryProvider);
      final uid = ref.read(currentUserProvider).valueOrNull?.uid;
      await repo.updateItemQuantity(order.id, it.id, newQty, createdBy: uid);
      // If the order was already approved, edits flip it to Modified & Approved.
      if (order.status == OrderStatus.approved ||
          order.status == OrderStatus.modifiedApproved) {
        await repo.markModified(order.id);
      }
      await ref.read(notificationRepositoryProvider).notifyParty(
            companyId: order.companyId,
            partyId: order.partyId,
            title: 'Order updated',
            body:
                '✏️ ${order.displayId}: ${it.productName} (${it.variantLabel}) '
                'quantity ${Formatters.qty(it.quantity)} → '
                '${Formatters.qty(newQty)}. Please review.',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Quantity updated — client notified.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  /// Admin: delete a whole line (variant) from the order, with confirmation.
  /// Totals recompute automatically. Allowed until the order is dispatched.
  Future<void> _confirmDeleteLine(BuildContext context, OrderItem it) async {
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
      final repo = ref.read(orderRepositoryProvider);
      final uid = ref.read(currentUserProvider).valueOrNull?.uid;
      await repo.updateItemQuantity(order.id, it.id, 0, createdBy: uid);
      if (order.status == OrderStatus.approved ||
          order.status == OrderStatus.modifiedApproved) {
        await repo.markModified(order.id);
      }
      await ref.read(notificationRepositoryProvider).notifyParty(
            companyId: order.companyId,
            partyId: order.partyId,
            title: 'Order updated',
            body: '🗑️ ${order.displayId}: ${it.productName} '
                '(${it.variantLabel}) was removed. Please review.',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Variant removed — client notified.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

/// A collapsible product group for the order's Products tab: tap the product
/// name to reveal a Size · Length · Rate · Qty · Amount table for its variants.
/// The collapsed header shows the variant count, total quantity and line total.
class _OrderProductGroup extends StatelessWidget {
  const _OrderProductGroup({
    required this.productName,
    required this.items,
    required this.isAdmin,
    required this.lengthOf,
    required this.sizeOf,
    required this.boxSizeOf,
    required this.packSizeOf,
    required this.canPick,
    required this.onTogglePick,
    required this.onTogglePickAll,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
  });

  final String productName;
  final List<OrderItem> items;
  final bool isAdmin;
  final String Function(OrderItem it) lengthOf;
  final String Function(OrderItem it) sizeOf;
  final int Function(OrderItem it) boxSizeOf;
  final int Function(OrderItem it) packSizeOf;
  final bool canPick;
  final void Function(OrderItem it, bool picked) onTogglePick;
  final void Function(List<OrderItem> items, bool picked) onTogglePickAll;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(OrderItem it) onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = items.fold<double>(0, (s, it) => s + it.total);
    final qty = items.fold<int>(0, (s, it) => s + it.quantity);
    final pickedCount = items.where((it) => it.picked).length;
    final allPicked = pickedCount == items.length;

    return Card(
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(productName,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                            '${items.length} size(s) · '
                            '${Formatters.qty(qty)} pcs',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (canPick) ...[
                    _PickBadge(picked: pickedCount, total: items.length),
                    const SizedBox(width: 8),
                  ],
                  Text(Formatters.money(total),
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: allPicked && canPick
                              ? const Color(0xFF16A34A)
                              : theme.colorScheme.primary)),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Builder(builder: (context) {
                    final showLength = items.any((it) => lengthOf(it) != '-');
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                      child: Column(
                        children: [
                          _OrderTableHeader(
                            showLength: showLength,
                            canPick: canPick,
                            allPicked: allPicked,
                            onToggleAll: () =>
                                onTogglePickAll(items, !allPicked),
                          ),
                          for (final it in items)
                            _OrderLineRow(
                              item: it,
                              size: sizeOf(it),
                              length: lengthOf(it),
                              showLength: showLength,
                              boxSize: boxSizeOf(it),
                              packSize: packSizeOf(it),
                              isAdmin: isAdmin,
                              canPick: canPick,
                              onTogglePick: (v) => onTogglePick(it, v),
                              onEdit: () => onEdit(it),
                            ),
                        ],
                      ),
                    );
                  })
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _OrderTableHeader extends StatelessWidget {
  const _OrderTableHeader({
    required this.showLength,
    this.canPick = false,
    this.allPicked = false,
    this.onToggleAll,
  });
  final bool showLength;
  final bool canPick;
  final bool allPicked;
  final VoidCallback? onToggleAll;
  static const _style = TextStyle(
      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (canPick)
            SizedBox(
              width: 34,
              child: InkWell(
                onTap: onToggleAll,
                borderRadius: BorderRadius.circular(20),
                child: Tooltip(
                  message: allPicked ? 'Unselect all' : 'Select all',
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: allPicked ? Colors.white : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: allPicked
                        ? Icon(Icons.check,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                  ),
                ),
              ),
            ),
          const Expanded(flex: 3, child: Text('SIZE', style: _style)),
          if (showLength)
            const Expanded(flex: 3, child: Text('LENGTH', style: _style)),
          const Expanded(
              flex: 3,
              child: Padding(
                padding: EdgeInsets.only(right: 10),
                child: Text('QTY', style: _style, textAlign: TextAlign.right),
              )),
        ],
      ),
    );
  }
}

/// A compact "picked / total" progress pill for a product group header. Turns
/// green when every line has been pulled from the warehouse.
class _PickBadge extends StatelessWidget {
  const _PickBadge({required this.picked, required this.total});
  final int picked;
  final int total;

  static const _green = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final done = picked == total && total > 0;
    final color = done ? _green : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14, color: color),
          const SizedBox(width: 4),
          Text('$picked/$total',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Splits a piece quantity into whole boxes + packs + loose pieces, using the
/// admin-set capacities (pieces per box / per pack). Greedy: boxes first.
({int boxes, int packs, int loose}) _packSplit(
    int qty, int boxSize, int packSize) {
  final box = boxSize <= 0 ? 0 : boxSize;
  final pack = packSize <= 0 ? 1 : packSize;
  if (qty <= 0) return (boxes: 0, packs: 0, loose: 0);
  final boxes = (box > 0 && box >= pack) ? qty ~/ box : 0;
  final afterBoxes = qty - boxes * box;
  final packs = afterBoxes ~/ pack;
  final loose = afterBoxes - packs * pack;
  return (boxes: boxes, packs: packs, loose: loose);
}

/// Builds the "how many box / pack" caption for a line, or '' when the variant
/// has no meaningful pack/box capacity set (pack = box = 1).
String _packBreakdown(int qty, int boxSize, int packSize) {
  if (boxSize <= 1 && packSize <= 1) return '';
  final s = _packSplit(qty, boxSize, packSize);
  final parts = <String>[];
  if (boxSize > 1) parts.add('${s.boxes} box');
  if (packSize > 1) parts.add('${s.packs} pack');
  if (s.loose > 0) parts.add('${s.loose} pcs');
  return parts.isEmpty ? '' : parts.join(' · ');
}

class _OrderLineRow extends StatelessWidget {
  const _OrderLineRow({
    required this.item,
    required this.size,
    required this.length,
    required this.showLength,
    required this.boxSize,
    required this.packSize,
    required this.isAdmin,
    required this.canPick,
    required this.onTogglePick,
    required this.onEdit,
  });
  final OrderItem item;
  final String size;
  final String length;
  final bool showLength;
  final int boxSize;
  final int packSize;
  final bool isAdmin;
  final bool canPick;
  final ValueChanged<bool> onTogglePick;
  final VoidCallback onEdit;

  Widget _val(String text, int flex,
          {bool bold = false, Color? color, Alignment align = Alignment.centerLeft}) =>
      Expanded(
        flex: flex,
        child: Align(
          alignment: align,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: align,
            child: Text(text,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: color)),
          ),
        ),
      );

  static const _green = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final breakdown = _packBreakdown(item.quantity, boxSize, packSize);
    final picked = item.picked;
    // Leading pick checkbox — a green check once pulled from the warehouse.
    final pickBox = SizedBox(
      width: 34,
      child: InkWell(
        onTap: () => onTogglePick(!picked),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: picked ? _green : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
                color: picked ? _green : scheme.outline, width: 2),
          ),
          child: picked
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
    // Admins can tap the quantity to change it.
    final qtyCell = Expanded(
      flex: 3,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          onTap: isAdmin ? onEdit : null,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(Formatters.qty(item.quantity),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isAdmin ? scheme.primary : null)),
                if (isAdmin) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.edit_outlined, size: 16, color: scheme.primary),
                ],
              ],
            ),
          ),
        ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: (canPick && picked) ? _green.withValues(alpha: 0.07) : null,
        border: Border(
            bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (canPick) pickBox,
              _val(size, 3, bold: true, color: scheme.onSurface),
              if (showLength) _val(length, 3, color: scheme.onSurfaceVariant),
              qtyCell,
            ],
          ),
          if (breakdown.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 3, left: canPick ? 34 : 0),
              child: Text('📦 $breakdown',
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }
}

/// Edit-quantity dialog with a two-way pack/box calculator (admin side).
///   • Enter a Quantity → it auto-splits into whole Box packs + Packs.
///   • Enter Box-pack / Pack counts → the Quantity auto-computes.
/// The Quantity field stays directly editable. Returns the new quantity.
class _QtyPackDialog extends StatefulWidget {
  const _QtyPackDialog({
    required this.label,
    required this.initialQty,
    required this.boxSize,
    required this.packSize,
    this.stock,
  });
  final String label;
  final int initialQty;
  final int boxSize; // pieces per box (0/1 = not set)
  final int packSize; // pieces per pack (0/1 = not set)
  final int? stock;

  @override
  State<_QtyPackDialog> createState() => _QtyPackDialogState();
}

class _QtyPackDialogState extends State<_QtyPackDialog> {
  late final int _box = widget.boxSize <= 0 ? 0 : widget.boxSize;
  late final int _pack = widget.packSize <= 0 ? 1 : widget.packSize;

  final _boxCtrl = TextEditingController();
  final _packCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _qtyCtrl.text = widget.initialQty > 0 ? '${widget.initialQty}' : '';
    _splitFromQty(widget.initialQty);
  }

  @override
  void dispose() {
    _boxCtrl.dispose();
    _packCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  int _read(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return (v == null || v < 0) ? 0 : v;
  }

  int get _qty => _read(_qtyCtrl);

  // Quantity → box/pack counts (programmatic .text set doesn't refire onChanged).
  void _splitFromQty(int q) {
    final s = _packSplit(q, _box, _pack);
    _boxCtrl.text = s.boxes == 0 ? '' : '${s.boxes}';
    _packCtrl.text = s.packs == 0 ? '' : '${s.packs}';
  }

  void _onQtyChanged(String raw) {
    setState(() => _splitFromQty(int.tryParse(raw.trim()) ?? 0));
  }

  // Box/pack counts → quantity.
  void _onCountsChanged() {
    setState(() {
      final q = _read(_boxCtrl) * _box + _read(_packCtrl) * _pack;
      _qtyCtrl.text = q <= 0 ? '' : '$q';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showBox = _box > 1;
    final showPack = _pack > 1;
    final split = _packSplit(_qty, _box, _pack);
    final leftover = split.loose;

    return AlertDialog(
      title: Text('Edit quantity · ${widget.label}'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 80)
            .clamp(280.0, 420.0)
            .toDouble(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.stock != null)
              Text('Available stock: ${Formatters.qty(widget.stock!)}',
                  style: TextStyle(
                      color: (widget.stock! < _qty)
                          ? AppColors.error
                          : scheme.onSurfaceVariant)),
            if (showBox || showPack) ...[
              const SizedBox(height: 4),
              Text(
                  [
                    if (showBox) 'Box pack = $_box pcs',
                    if (showPack) 'Pack = $_pack pcs',
                  ].join('   ·   '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.md),
              if (showBox)
                _CountField(
                    label: 'Box packs',
                    controller: _boxCtrl,
                    onChanged: _onCountsChanged),
              if (showBox) const SizedBox(height: AppSpacing.sm),
              if (showPack)
                _CountField(
                    label: 'Packs',
                    controller: _packCtrl,
                    onChanged: _onCountsChanged),
              const SizedBox(height: AppSpacing.md),
            ] else
              const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                    width: 92,
                    child: Text('Quantity', style: theme.textTheme.bodyMedium)),
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'pcs (0 removes the line)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _onQtyChanged,
                  ),
                ),
              ],
            ),
            if ((showBox || showPack) && _qty > 0 && leftover > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('$leftover pcs left over — not a whole pack.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        // Delete the whole line (returns a negative sentinel to the caller).
        TextButton(
          onPressed: () => Navigator.pop(context, -1),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Delete size'),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _qty),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A labelled count input with – / + steppers (for the pack dialog).
class _CountField extends StatelessWidget {
  const _CountField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  int get _value => int.tryParse(controller.text.trim()) ?? 0;

  void _set(int n) {
    final v = n < 0 ? 0 : n;
    controller.text = v == 0 ? '' : '$v';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget btn(IconData icon, VoidCallback onTap) => InkResponse(
          onTap: onTap,
          radius: 20,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18),
          ),
        );
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label, style: theme.textTheme.bodyMedium)),
        btn(Icons.remove, () => _set(_value - 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            width: 64,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                hintText: '0',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
        btn(Icons.add, () => _set(_value + 1)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline tab
// ---------------------------------------------------------------------------

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.order});
  final Order order;

  static const _flow = [
    OrderStatus.pending,
    OrderStatus.approved,
    OrderStatus.packing,
    OrderStatus.packed,
    OrderStatus.dispatched,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (order.status == OrderStatus.rejected ||
        order.status == OrderStatus.cancelled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cancel_outlined,
                  size: 48, color: AppColors.error),
              const SizedBox(height: AppSpacing.md),
              Text('Order ${order.status.label}',
                  style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      );
    }

    final currentIndex = _flow.indexOf(order.status);
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _flow.length,
      itemBuilder: (context, i) {
        final s = _flow[i];
        final done = i < currentIndex;
        final current = i == currentIndex;
        final color = done
            ? AppColors.success
            : current
                ? scheme.primary
                : scheme.outlineVariant;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: (done || current) ? color : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: done
                        ? const Icon(Icons.check, size: 15, color: Colors.white)
                        : null,
                  ),
                  if (i != _flow.length - 1)
                    Expanded(
                        child: Container(
                            width: 2,
                            color: done ? AppColors.success : scheme.outlineVariant)),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg, top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight:
                                current ? FontWeight.w800 : FontWeight.w500,
                            color: current ? scheme.primary : null)),
                    if (s == OrderStatus.pending && order.createdAt != null)
                      Text(Formatters.dateTime(order.createdAt),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    if (s == OrderStatus.approved && order.approvedAt != null)
                      Text(Formatters.dateTime(order.approvedAt),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Invoice tab
// ---------------------------------------------------------------------------

class _InvoiceTab extends StatelessWidget {
  const _InvoiceTab({
    required this.order,
    required this.onPrint,
    required this.canApprove,
    required this.onApprove,
  });
  final Order order;
  final VoidCallback onPrint;
  final bool canApprove;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (order.invoiceNo == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: AppSpacing.md),
              Text('No invoice yet',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text('An invoice number is assigned when the order is approved.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (canApprove) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Approve & generate'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _InfoCard(
          title: 'Invoice',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.invoiceNo!,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.xs),
              Text('Total ${Formatters.money(order.grandTotal)}',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onPrint,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Open / Print PDF'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Activity tab
// ---------------------------------------------------------------------------

class _ActivityTab extends ConsumerWidget {
  const _ActivityTab({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(activityLogsProvider);
    return logs.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
          error: e, onRetry: () => ref.invalidate(activityLogsProvider)),
      data: (all) {
        final mine = all
            .where((l) =>
                l.target == order.invoiceNo || l.target == order.id)
            .toList();
        if (mine.isEmpty) {
          return const EmptyView(
              message: 'No activity recorded for this order yet.');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: mine.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final l = mine[i];
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(l.action),
              subtitle: Text('${l.userName} · '
                  '${Formatters.dateTime(l.createdAt)}'),
            );
          },
        );
      },
    );
  }
}


// ---------------------------------------------------------------------------
// Pack confirmation — lists the short (edited-down / unpicked) variants that
// will move to a pending backorder.
// ---------------------------------------------------------------------------

class _PackConfirmDialog extends StatelessWidget {
  const _PackConfirmDialog({required this.shorts});
  final List<({String label, int short})> shorts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: const Text('Mark packed?'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 80).clamp(280.0, 460.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (shorts.isEmpty)
              Text('All items will be packed in full and moved to dispatch.',
                  style: theme.textTheme.bodyMedium)
            else ...[
              Text(
                'These items are short and will move to a new pending '
                'backorder:',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in shorts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.remove_circle_outline,
                                size: 16, color: AppColors.warning),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(s.label,
                                  style: theme.textTheme.bodySmall),
                            ),
                            const SizedBox(width: 6),
                            Text('short ${s.short}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                  'The available quantities will be packed and dispatched; the '
                  'short quantities stay pending for later.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Mark packed'),
        ),
      ],
    );
  }
}

/// A slim banner used on the Overview tab to show backorder linkage.
class _BackorderBanner extends StatelessWidget {
  const _BackorderBanner(
      {required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
