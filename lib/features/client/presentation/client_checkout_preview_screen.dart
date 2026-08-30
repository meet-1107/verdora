import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_bottom_order_bar.dart';
import '../../../core/widgets/app_delivery_card.dart';
import '../../../core/widgets/app_info_banner.dart';
import '../../../core/widgets/app_order_totals_card.dart';
import '../../../core/widgets/app_product_review_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../discounts/logic/discount_resolver.dart';
import '../../discounts/presentation/discount_providers.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/domain/order.dart';
import '../../orders/domain/order_status.dart';
import '../../orders/presentation/order_providers.dart';
import '../../parties/presentation/party_providers.dart';
import '../../products/domain/product.dart';
import '../../products/domain/variant.dart';
import '../../products/presentation/product_providers.dart';
import '../application/cart_provider.dart';
import '../domain/cart_item.dart';
import 'client_cart_screen.dart';
import 'client_order_submitted_screen.dart';

/// Checkout Preview = Purchase Order Confirmation. Final review before the order
/// becomes a pending purchase request for admin approval. No payment. UI only.
class ClientCheckoutPreviewScreen extends ConsumerStatefulWidget {
  const ClientCheckoutPreviewScreen({super.key, this.initialNote = ''});
  final String initialNote;

  @override
  ConsumerState<ClientCheckoutPreviewScreen> createState() =>
      _ClientCheckoutPreviewScreenState();
}

class _ClientCheckoutPreviewScreenState
    extends ConsumerState<ClientCheckoutPreviewScreen> {
  late final TextEditingController _notes =
      TextEditingController(text: widget.initialNote);
  bool _confirmed = false;
  bool _submitting = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);
    final party = ref.watch(orderPartyProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    // Watch discount inputs so the totals refresh live, then re-resolve.
    ref.watch(discountsProvider);
    ref.watch(allVariantsProvider);
    ref.watch(productsProvider);
    final t = _recompute();
    final subtotal = t.subtotal;
    final discount = t.productDiscount + t.globalDiscount;
    final total = t.grandTotal;
    final totalQty = ref.watch(cartCountProvider);

    // Empty state should never happen; bounce back to the order.
    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review Order')),
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Your order is empty. Go back.'),
          ),
        ),
      );
    }

    final orders = ref.watch(clientOrdersProvider).valueOrNull ?? const [];
    final List<OrderItem> lastItems = orders.isNotEmpty
        ? (ref.watch(orderItemsProvider(orders.first.id)).valueOrNull ??
            const <OrderItem>[])
        : const <OrderItem>[];
    final changes = _computeChanges(cart, lastItems);

    final address = [
      party?.address,
      party?.city,
      party?.state,
      party?.pincode,
    ].where((e) => e != null && e.isNotEmpty).join(', ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Review Order'),
            Text('Confirm before submitting',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'PDF preview',
            onPressed: () => _previewPdf(cart, party?.name ?? user?.name ?? ''),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const AppInfoBanner(
                  icon: Icons.receipt_long,
                  title: 'Review your order',
                  color: AppColors.primary,
                  message: 'Please verify all products before submitting.',
                ),
                const SizedBox(height: AppSpacing.lg),
                AppDeliveryCard(
                  partyName: party?.name ?? user?.name ?? 'Your account',
                  address: address,
                  phone: party?.phone,
                  transport: party?.transport,
                ),
                const SizedBox(height: AppSpacing.lg),
                _orderMetaCard(
                    theme, cart.length, totalQty, _estimatedWeightText(), total),
                if (changes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _changesCard(theme, changes),
                ],
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: Text('Products (${cart.length})',
                          style: theme.textTheme.titleMedium),
                    ),
                    TextButton.icon(
                      onPressed: _editOrder,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final c in cart)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppProductReviewCard(
                      name: c.productName,
                      variantLabel: c.variantLabel,
                      quantity: Formatters.qty(c.quantity),
                      rate: Formatters.money(c.rate),
                      total: Formatters.money(c.total),
                      discount: c.discountPercent > 0
                          ? '${_pct(c.discountPercent)}%'
                          : null,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                AppOrderTotalsCard(
                  rows: [
                    ('Total amount', Formatters.money(subtotal)),
                    if (t.productDiscount > 0)
                      ('Product discount',
                          '- ${Formatters.money(t.productDiscount)}'),
                    if (t.globalDiscount > 0)
                      ('Cash discount (${_pct(t.globalPercent)}%)',
                          '- ${Formatters.money(t.globalDiscount)}'),
                    ('GST (${_pct(AppConstants.gstRate)}%)',
                        '+ ${Formatters.money(t.tax)}'),
                  ],
                  grandTotalLabel: 'Final amount',
                  grandTotalValue: Formatters.money(total),
                ),
                if (discount > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppInfoBanner(
                    icon: Icons.savings_outlined,
                    title: 'You saved ${Formatters.money(discount)}',
                    color: AppColors.success,
                    message: 'Applied with your dealer discount.',
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  controller: _notes,
                  maxLines: 3,
                  maxLength: 250,
                  decoration: const InputDecoration(
                    labelText: 'Additional notes (optional)',
                    hintText: 'e.g. Deliver urgently',
                    alignLabelWithHint: true,
                  ),
                ),
                CheckboxListTile(
                  value: _confirmed,
                  onChanged: (v) => setState(() => _confirmed = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                      'I confirm that all order information is correct.'),
                ),
                Text(
                  'Orders are subject to administrator approval.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          AppBottomOrderBar(
            totalLabel: 'Grand total',
            totalValue: Formatters.money(total),
            actionLabel: 'Submit Order',
            enabled: _confirmed,
            loading: _submitting,
            onAction: _submit,
          ),
        ],
      ),
    );
  }

  // ---- order meta ----
  Widget _orderMetaCard(ThemeData theme, int products, int qty,
      String weightText, double total) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            _metaRow(theme, 'Order number',
                'Assigned on approval'),
            _metaRow(theme, 'Date', Formatters.date(DateTime.now())),
            _metaRow(theme, 'Products', '$products'),
            _metaRow(theme, 'Total quantity', Formatters.qty(qty)),
            _metaRow(theme, 'Estimated weight', weightText),
            _metaRow(theme, 'Estimated amount', Formatters.money(total),
                bold: true),
          ],
        ),
      ),
    );
  }

  /// Total shipment weight of the cart, resolved from each line's variant
  /// (grams, shown in kg once it reaches 1000 g). '-' when no line has a weight.
  String _estimatedWeightText() {
    final cart = ref.read(cartProvider);
    final variants =
        ref.read(allVariantsProvider).valueOrNull ?? const <Variant>[];
    final byId = {for (final v in variants) v.id: v};
    double grams = 0;
    for (final c in cart) {
      final v = byId[c.variantId];
      if (v == null) continue;
      final w = double.tryParse(v.attributes['Weight'] ?? '') ?? 0;
      final unit = (v.attributes['Weight Unit'] ?? '').trim().toLowerCase();
      grams += (unit == 'kg' ? w * 1000 : w) * c.quantity;
    }
    if (grams <= 0) return '-';
    String f(double x) => x == x.roundToDouble()
        ? x.toStringAsFixed(0)
        : x.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    return grams >= 1000 ? '${f(grams / 1000)} kg' : '${f(grams)} gm';
  }

  Widget _metaRow(ThemeData theme, String label, String value,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style: bold
                  ? theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                  : theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  // ---- changes since last order ----
  Widget _changesCard(ThemeData theme, List<_Change> changes) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Changes since last order',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final c in changes.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(c.icon, size: 18, color: c.color),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(c.text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_Change> _computeChanges(
      List<CartItem> cart, List<OrderItem> lastItems) {
    if (lastItems.isEmpty) return const [];
    final last = {for (final it in lastItems) it.variantId: it};
    final currentIds = {for (final c in cart) c.variantId};
    final changes = <_Change>[];
    for (final c in cart) {
      final prev = last[c.variantId];
      if (prev == null) {
        changes.add(_Change.added('${c.productName} ${c.variantLabel}'.trim()));
      } else if (c.quantity > prev.quantity) {
        changes.add(_Change.increased(
            c.productName, prev.quantity, c.quantity));
      } else if (c.quantity < prev.quantity) {
        changes.add(_Change.decreased(
            c.productName, prev.quantity, c.quantity));
      }
    }
    for (final it in lastItems) {
      if (!currentIds.contains(it.variantId)) {
        changes.add(_Change.removed('${it.productName} ${it.variantLabel}'.trim()));
      }
    }
    return changes;
  }

  // ---- submit ----
  Future<void> _submit() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Submit purchase order?',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Once submitted, your administrator will review this order.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;

    final cart = ref.read(cartProvider);
    final user = ref.read(currentUserProvider).valueOrNull;
    final party = ref.read(orderPartyProvider);
    // True when an admin is placing this order on behalf of a dealer.
    final onBehalf = ref.read(actingPartyProvider) != null;
    if (user == null || party == null) {
      _snack('No party selected for this order.');
      return;
    }
    setState(() => _submitting = true);
    try {
      // Re-resolve discounts against the current party + rules so the submitted
      // order always reflects them, even for lines added before a discount was
      // set.
      final t = _recompute();
      final order = Order(
        id: '',
        companyId: user.companyId,
        partyId: party.id,
        partyName: party.name,
        status: OrderStatus.pending,
        subtotal: t.subtotal,
        discountTotal: t.productDiscount + t.globalDiscount,
        taxTotal: t.tax,
        grandTotal: t.grandTotal,
        globalDiscountPercent: t.globalPercent,
        itemCount: cart.length,
        note: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        placedByAdmin: onBehalf,
        createdByUid: onBehalf ? user.uid : null,
      );
      final items = [
        for (final c in cart)
          OrderItem(
            id: '',
            companyId: user.companyId,
            orderId: '',
            variantId: c.variantId,
            productName: c.productName,
            variantLabel: c.variantLabel,
            rate: c.rate,
            quantity: c.quantity,
            // Line stores only the product-specific discount; the global % is an
            // order-level deduction applied to the after-product total.
            discountPercent:
                t.specificByVariant[c.variantId] ?? c.discountPercent,
          ),
      ];
      final result = await ref.read(orderRepositoryProvider).createOrder(
            order: order,
            items: items,
            clientCode: party.partyCode.isEmpty ? party.id : party.partyCode,
          );
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      if (onBehalf) {
        // Admin flow: clear the acting party and return to the admin panel.
        ref.read(actingPartyProvider.notifier).state = null;
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Order ${result.orderNo} created for ${party.name}.')));
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ClientOrderSubmittedScreen(reference: result.orderNo)),
        );
      }
    } catch (e) {
      _snack('Unable to submit: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _previewPdf(List<CartItem> cart, String partyName) async {
    final t = _recompute();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Text('Purchase Order (Preview)',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Party: $partyName'),
        pw.Text('Date: ${Formatters.date(DateTime.now())}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const ['Product', 'Size', 'Qty', 'Rate', 'Total'],
          data: [
            for (final c in cart)
              [
                c.productName,
                c.variantLabel,
                '${c.quantity}',
                c.rate.toStringAsFixed(2),
                c.total.toStringAsFixed(2),
              ],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green50),
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('GST (${_pct(AppConstants.gstRate)}%): '
                  '${t.tax.toStringAsFixed(2)}'),
              pw.SizedBox(height: 2),
              pw.Text(
                'Grand total: ${t.grandTotal.toStringAsFixed(2)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Returns to the Order Summary so the dealer can change products / sizes /
  /// quantities. (This screen is pushed from the Order Summary, so popping lands
  /// there; if reached some other way, open the Order Summary directly.)
  void _editOrder() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacement(
          MaterialPageRoute(builder: (_) => const ClientCartScreen()));
    }
  }

  /// Re-resolves each cart line's discount against the CURRENT party + rules
  /// (Product > Subcategory > Category > party global) and returns the order
  /// totals plus the resolved percent per variant.
  ({
    double subtotal,
    double productDiscount,
    double globalPercent,
    double globalDiscount,
    double taxable,
    double tax,
    double grandTotal,
    Map<String, double> specificByVariant,
  }) _recompute() {
    final cart = ref.read(cartProvider);
    final party = ref.read(orderPartyProvider);
    final resolver =
        DiscountResolver(ref.read(discountsProvider).valueOrNull ?? const []);
    final variants =
        ref.read(allVariantsProvider).valueOrNull ?? const <Variant>[];
    final products =
        ref.read(productsProvider).valueOrNull ?? const <Product>[];
    final variantById = {for (final v in variants) v.id: v};
    final productById = {for (final p in products) p.id: p};

    var subtotal = 0.0, productDiscount = 0.0, afterProduct = 0.0;
    final specificByVariant = <String, double>{};
    for (final c in cart) {
      var specific = 0.0;
      final v = variantById[c.variantId];
      final p = v != null ? productById[v.productId] : null;
      if (v != null && p != null) {
        specific = resolver.resolveSpecific(DiscountContext(
          variantId: v.id,
          productId: p.id,
          categoryId: p.categoryId,
          subcategoryId: p.subcategoryId ?? '',
          partyId: party?.id ?? '',
        ));
      }
      specificByVariant[c.variantId] = specific;
      final gross = c.rate * c.quantity;
      final lineDisc = gross * specific / 100;
      subtotal += gross;
      productDiscount += lineDisc;
      afterProduct += gross - lineDisc;
    }
    final globalPct = party?.defaultDiscount ?? 0;
    final globalDiscount = afterProduct * globalPct / 100;
    // GST is charged on the net amount left after every discount.
    final taxable = afterProduct - globalDiscount;
    final tax = taxable * AppConstants.gstRate / 100;
    return (
      subtotal: subtotal,
      productDiscount: productDiscount,
      globalPercent: globalPct,
      globalDiscount: globalDiscount,
      taxable: taxable,
      tax: tax,
      grandTotal: taxable + tax,
      specificByVariant: specificByVariant,
    );
  }

  static String _pct(double p) => p % 1 == 0 ? p.toStringAsFixed(0) : '$p';
}

class _Change {
  const _Change(this.icon, this.color, this.text);
  final IconData icon;
  final Color color;
  final String text;

  factory _Change.increased(String name, int from, int to) =>
      _Change(Icons.arrow_upward, AppColors.success, '$name  $from → $to');
  factory _Change.decreased(String name, int from, int to) =>
      _Change(Icons.arrow_downward, AppColors.warning, '$name  $from → $to');
  factory _Change.added(String name) =>
      _Change(Icons.add_circle_outline, AppColors.success, 'New: $name');
  factory _Change.removed(String name) =>
      _Change(Icons.remove_circle_outline, AppColors.error, 'Removed: $name');
}
