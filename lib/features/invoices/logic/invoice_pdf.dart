import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../orders/domain/order.dart';
import '../../products/domain/variant.dart';
import '../../settings/domain/company_settings.dart';

/// Builds a printable A4 invoice PDF for an order. [variants] supplies per-line
/// weights (order items don't store weight) for the total-weight line.
Future<Uint8List> buildInvoicePdf({
  required Order order,
  required List<OrderItem> items,
  required CompanySettings settings,
  List<Variant> variants = const [],
}) async {
  final doc = pw.Document();
  // No currency symbol on the PDF (the ₹ glyph isn't in the default PDF font and
  // renders as a box) and no decimals — whole rupees, Indian digit grouping.
  final nf = NumberFormat('#,##0', 'en_IN');
  String money(num v) => nf.format(v.truncateToDouble());
  final dateStr =
      DateFormat('dd MMM yyyy').format(order.createdAt ?? DateTime(2000));
  final byId = {for (final v in variants) v.id: v};
  final weightText = _totalWeightText(items, byId);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        _header(settings),
        pw.SizedBox(height: 16),
        _meta(order, dateStr, weightText),
        pw.SizedBox(height: 16),
        _itemsTable(items, byId, money),
        pw.SizedBox(height: 12),
        _totals(order, items, money),
        if (settings.terms.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Text('Terms & Conditions',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(settings.terms,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
        pw.SizedBox(height: 24),
        pw.Text('This is a computer-generated proforma invoice.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(CompanySettings s) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(s.name.isEmpty ? 'Company' : s.name,
              style:
                  pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          if (s.address.isNotEmpty)
            pw.Text(s.address, style: const pw.TextStyle(fontSize: 9)),
          if (s.phone.isNotEmpty)
            pw.Text('Phone: ${s.phone}',
                style: const pw.TextStyle(fontSize: 9)),
          if (s.gstNumber.isNotEmpty)
            pw.Text('GST: ${s.gstNumber}',
                style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
      pw.Text('PROFORMA INVOICE',
          style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green800)),
    ],
  );
}

pw.Widget _meta(Order order, String dateStr, String weightText) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Bill To',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(order.partyName),
        ],
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('PO No: ${_poNumber(order)}'),
          pw.Text('Date: $dateStr'),
          pw.Text('Status: ${order.status.label}'),
          pw.SizedBox(height: 3),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: pw.BoxDecoration(
              color: PdfColors.green50,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text('Total weight: $weightText',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                    color: PdfColors.green800)),
          ),
        ],
      ),
    ],
  );
}

/// Total shipment weight resolved from each line's variant. Grams, shown in kg
/// once it reaches 1000 g. Returns '-' when no line has a weight.
String _totalWeightText(List<OrderItem> items, Map<String, Variant> byId) {
  double grams = 0;
  for (final it in items) {
    final v = byId[it.variantId];
    if (v == null) continue;
    final w = double.tryParse(v.attributes['Weight'] ?? '') ?? 0;
    final u = (v.attributes['Weight Unit'] ?? '').trim().toLowerCase();
    grams += (u == 'kg' ? w * 1000 : w) * it.quantity;
  }
  if (grams <= 0) return '-';
  String f(double x) =>
      x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(2);
  return grams >= 1000 ? '${f(grams / 1000)} kg' : '${f(grams)} gm';
}

/// A short purchase-order number: `<party short code>-<daily seq>`, e.g.
/// `GOPAL-05`. Derived from the order's party code + the running number in the
/// order id (falls back to the party name / `01`).
String _poNumber(Order order) {
  var code = (order.partyCode != null && order.partyCode!.isNotEmpty)
      ? order.partyCode!
      : order.partyName
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toUpperCase();
  if (code.isEmpty) code = 'PO';
  if (code.length > 10) code = code.substring(0, 10);

  var seq = '01';
  final on = order.orderNo;
  if (on != null && on.contains('-')) {
    final n = int.tryParse(on.split('-').last);
    if (n != null) seq = n.toString().padLeft(2, '0');
  }
  return '$code-$seq';
}

pw.Widget _itemsTable(
    List<OrderItem> items, Map<String, Variant> byId, String Function(num) money) {
  // Size value WITHOUT its unit (e.g. "1", "1.1/2"); falls back to the stored
  // label with any trailing unit word stripped.
  String sizeValue(OrderItem it) {
    final s = (byId[it.variantId]?.attributes['Size'] ?? '').trim();
    if (s.isNotEmpty) return s;
    return it.variantLabel
        .replaceAll(
            RegExp(r'\s*(inch(es)?|mm|cm|ft|feet)\b', caseSensitive: false), '')
        .trim();
  }

  // Length value (only shown when a variant provides it).
  String lengthValue(OrderItem it) {
    final v = byId[it.variantId];
    if (v == null) return '';
    final l = (v.attributes['Length'] ?? '').trim();
    if (l.isEmpty) return '';
    final lu = (v.attributes['Length Unit'] ?? '').trim();
    return lu.isEmpty ? l : '$l $lu';
  }

  // Group product-wise: all variants of the same product appear together.
  final sorted = [...items]
    ..sort((a, b) {
      final c =
          a.productName.toLowerCase().compareTo(b.productName.toLowerCase());
      return c != 0
          ? c
          : a.variantLabel.toLowerCase().compareTo(b.variantLabel.toLowerCase());
    });

  final showLength = sorted.any((it) => lengthValue(it).isNotEmpty);

  final headers = <String>[
    '#',
    'Product',
    'Size',
    if (showLength) 'Length',
    'Qty',
    'Rate',
    'Disc%',
    'Amount',
  ];
  final data = <List<String>>[];
  for (var i = 0; i < sorted.length; i++) {
    final it = sorted[i];
    data.add([
      '${i + 1}',
      it.productName, // product name on every row (no blanks)
      sizeValue(it),
      if (showLength) lengthValue(it),
      '${it.quantity}',
      money(it.rate),
      it.discountPercent == 0 ? '-' : '${it.discountPercent}',
      money(it.total),
    ]);
  }

  // Right-align the numeric columns (Qty, Rate, Disc%, Amount).
  final numericStart = showLength ? 4 : 3;
  final alignments = <int, pw.Alignment>{0: pw.Alignment.centerLeft};
  for (var i = numericStart; i < headers.length; i++) {
    alignments[i] = pw.Alignment.centerRight;
  }

  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: data,
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
    cellStyle: const pw.TextStyle(fontSize: 9),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.green50),
    cellAlignments: alignments,
  );
}

pw.Widget _totals(
    Order order, List<OrderItem> items, String Function(num) money) {
  // Two-stage discount split: product-level discount vs the order-wide cash
  // (global) discount, derived from stored totals + line totals.
  final afterProduct = items.fold<double>(0, (s, it) => s + it.total);
  final productDiscount =
      (order.subtotal - afterProduct).clamp(0, double.infinity).toDouble();
  final cashDiscount = (order.discountTotal - productDiscount)
      .clamp(0, double.infinity)
      .toDouble();
  final pct = order.globalDiscountPercent;
  final pctStr = pct == pct.roundToDouble()
      ? pct.toStringAsFixed(0)
      : pct.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  pw.Widget row(String label, num value, {bool bold = false}) {
    final style = pw.TextStyle(
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontSize: bold ? 12 : 10);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(money(value), style: style)
      ],
    );
  }

  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 240,
      child: pw.Column(children: [
        row('Subtotal', order.subtotal),
        if (productDiscount > 0.01) row('Product discount', -productDiscount),
        if (cashDiscount > 0.01) row('Cash discount ($pctStr%)', -cashDiscount),
        if (order.taxTotal > 0) row('Tax', order.taxTotal),
        pw.Divider(),
        row('Grand Total', order.grandTotal, bold: true),
      ]),
    ),
  );
}
