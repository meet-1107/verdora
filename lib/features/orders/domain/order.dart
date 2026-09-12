import 'package:cloud_firestore/cloud_firestore.dart';

import 'order_status.dart';

/// An order header (`orders/{id}`). Line items are stored separately in
/// `order_items` (see [OrderItem]) to keep documents small and reportable.
class Order {
  const Order({
    required this.id,
    required this.companyId,
    required this.partyId,
    required this.partyName,
    required this.status,
    this.orderNo,
    this.partyCode,
    this.invoiceNo,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.taxTotal = 0,
    this.grandTotal = 0,
    this.globalDiscountPercent = 0,
    this.itemCount = 0,
    this.note,
    this.rejectionReason,
    this.modified = false,
    this.createdAt,
    this.approvedAt,
    this.approvedByName,
    this.stockDeducted = false,
    this.placedByAdmin = false,
    this.createdByUid,
    this.backorderOf,
    this.backorderOfNo,
    this.backorderId,
    this.backorderNo,
  });

  final String id;
  final String companyId;
  final String partyId;
  final String partyName;
  final OrderStatus status;

  /// Human-facing unique order id, e.g. `ABC-20260807-0001` (client code + date
  /// + that client's daily running number). Assigned at submission.
  final String? orderNo;
  final String? partyCode;
  final String? invoiceNo;
  final double subtotal;

  /// Total money discounted = per-line product discounts + the order-level
  /// global discount.
  final double discountTotal;
  final double taxTotal;
  final double grandTotal;

  /// The party's global discount %, applied to the after-product-discount total.
  final double globalDiscountPercent;
  final int itemCount;
  final String? note;

  /// Reason the admin gave when rejecting (shown to the client).
  final String? rejectionReason;

  /// True once the admin edited the order (quantity/price/discount). Combined
  /// with an approved status this surfaces as "Modified & Approved".
  final bool modified;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final String? approvedByName;

  /// True once this order's quantities have been removed from stock (at
  /// packing). Guards against deducting the same order twice.
  final bool stockDeducted;

  /// True when an admin placed this order on behalf of the dealer (not the
  /// dealer signing in). [createdByUid] is the admin's uid.
  final bool placedByAdmin;
  final String? createdByUid;

  /// If this order was created to hold the short (undispatched) items of another
  /// order, these point back to that original order. [backorderId]/[backorderNo]
  /// (set on the ORIGINAL) point forward to the backorder that was split off.
  final String? backorderOf;
  final String? backorderOfNo;
  final String? backorderId;
  final String? backorderNo;

  bool get isBackorder => backorderOf != null;

  /// The best human-facing identifier to show for this order.
  String get displayId => orderNo ?? invoiceNo ?? 'Order';

  factory Order.fromMap(String id, Map<String, dynamic> map) {
    return Order(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      partyId: map['partyId'] as String? ?? '',
      partyName: map['partyName'] as String? ?? '',
      status: OrderStatus.fromValue(map['status'] as String?),
      orderNo: map['orderNo'] as String?,
      partyCode: map['partyCode'] as String?,
      invoiceNo: map['invoiceNo'] as String?,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      discountTotal: (map['discountTotal'] as num?)?.toDouble() ?? 0,
      taxTotal: (map['taxTotal'] as num?)?.toDouble() ?? 0,
      grandTotal: (map['grandTotal'] as num?)?.toDouble() ?? 0,
      globalDiscountPercent:
          (map['globalDiscountPercent'] as num?)?.toDouble() ?? 0,
      itemCount: (map['itemCount'] as num?)?.toInt() ?? 0,
      note: map['note'] as String?,
      rejectionReason: map['rejectionReason'] as String?,
      modified: map['modified'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      approvedAt: (map['approvedAt'] as Timestamp?)?.toDate(),
      approvedByName: map['approvedByName'] as String?,
      stockDeducted: map['stockDeducted'] as bool? ?? false,
      placedByAdmin: map['placedByAdmin'] as bool? ?? false,
      createdByUid: map['createdByUid'] as String?,
      backorderOf: map['backorderOf'] as String?,
      backorderOfNo: map['backorderOfNo'] as String?,
      backorderId: map['backorderId'] as String?,
      backorderNo: map['backorderNo'] as String?,
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'partyId': partyId,
        'partyName': partyName,
        'partyCode': partyCode,
        'status': status.value,
        'orderNo': orderNo,
        'invoiceNo': invoiceNo,
        'subtotal': subtotal,
        'discountTotal': discountTotal,
        'taxTotal': taxTotal,
        'grandTotal': grandTotal,
        'globalDiscountPercent': globalDiscountPercent,
        'itemCount': itemCount,
        'note': note,
        'modified': modified,
        'placedByAdmin': placedByAdmin,
        'createdByUid': createdByUid,
        'backorderOf': backorderOf,
        'backorderOfNo': backorderOfNo,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// A single line in an order (`order_items/{id}`).
class OrderItem {
  const OrderItem({
    required this.id,
    required this.companyId,
    required this.orderId,
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.rate,
    required this.quantity,
    this.discountPercent = 0,
    this.taxPercent = 0,
    this.picked = false,
  });

  final String id;
  final String companyId;
  final String orderId;
  final String variantId;
  final String productName;
  final String variantLabel;
  final double rate;
  final int quantity;
  final double discountPercent;
  final double taxPercent;

  /// Warehouse pick flag: true once this line's quantity has been pulled from
  /// the warehouse during packing (set by the admin on the order Products tab).
  final bool picked;

  double get gross => rate * quantity;
  double get discountAmount => gross * discountPercent / 100;
  double get taxable => gross - discountAmount;
  double get taxAmount => taxable * taxPercent / 100;
  double get total => taxable + taxAmount;

  factory OrderItem.fromMap(String id, Map<String, dynamic> map) {
    return OrderItem(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      orderId: map['orderId'] as String? ?? '',
      variantId: map['variantId'] as String? ?? '',
      productName: map['productName'] as String? ?? '',
      variantLabel: map['variantLabel'] as String? ?? '',
      rate: (map['rate'] as num?)?.toDouble() ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      discountPercent: (map['discountPercent'] as num?)?.toDouble() ?? 0,
      taxPercent: (map['taxPercent'] as num?)?.toDouble() ?? 0,
      picked: map['picked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'orderId': orderId,
        'variantId': variantId,
        'productName': productName,
        'variantLabel': variantLabel,
        'rate': rate,
        'quantity': quantity,
        'discountPercent': discountPercent,
        'taxPercent': taxPercent,
        'picked': picked,
        'total': total,
      };
}
