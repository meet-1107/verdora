// `Order` is also exported by cloud_firestore; hide it so our domain Order wins.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../inventory/domain/inventory_transaction.dart';
import '../domain/order.dart';
import '../domain/order_status.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(ref.watch(firestoreProvider));
});

class OrderRepository {
  OrderRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection(Collections.orders);
  CollectionReference<Map<String, dynamic>> get _orderItems =>
      _db.collection(Collections.orderItems);

  /// Creates an order header + its line items atomically and assigns a unique,
  /// human-facing Order ID of the form `CODE-YYYYMMDD-NNNN` (client code + date
  /// + that client's running number for the day). The daily sequence is kept in
  /// a per-client/per-day counter doc, incremented inside the same transaction
  /// so two orders never collide. Returns `(id, orderNo)`.
  Future<({String id, String orderNo})> createOrder({
    required Order order,
    required List<OrderItem> items,
    required String clientCode,
  }) async {
    final code = _cleanCode(clientCode);
    final dateKey = _dateKey(DateTime.now());
    final counterRef = _db
        .collection(Collections.orderCounters)
        .doc('${order.companyId}_${code}_$dateKey');
    final orderRef = _orders.doc();

    final orderNo = await _db.runTransaction<String>((tx) async {
      final snap = await tx.get(counterRef);
      final next = ((snap.data()?['seq'] as num?)?.toInt() ?? 0) + 1;
      tx.set(
        counterRef,
        {'seq': next, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      final no = '$code-$dateKey-${next.toString().padLeft(4, '0')}';
      tx.set(orderRef, {
        ...order.toCreateMap(),
        'orderNo': no,
        'partyCode': code,
      });
      for (final item in items) {
        tx.set(_orderItems.doc(), {...item.toMap(), 'orderId': orderRef.id});
      }
      return no;
    });
    return (id: orderRef.id, orderNo: orderNo);
  }

  static String _cleanCode(String code) {
    final c = code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return c.isEmpty ? 'ORD' : c;
  }

  static String _dateKey(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}';
  }

  Stream<List<Order>> watchForParty(String partyId) {
    return _orders
        .where('partyId', isEqualTo: partyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Order.fromMap(d.id, d.data())).toList());
  }

  Stream<List<Order>> watchForCompany(String companyId) {
    return _orders
        .where('companyId', isEqualTo: companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Order.fromMap(d.id, d.data())).toList());
  }

  Stream<List<OrderItem>> watchItems(String orderId) {
    return _orderItems.where('orderId', isEqualTo: orderId).snapshots().map(
        (s) => s.docs.map((d) => OrderItem.fromMap(d.id, d.data())).toList());
  }

  /// Approves an order client-side: assigns an invoice number and advances the
  /// status. Stock is NOT touched here — it is deducted when packing starts
  /// (see [markDispatched]). Runs without Cloud Functions so it works on the Spark
  /// plan. Returns the assigned invoice number.
  Future<String> approve(String orderId, {bool modified = false}) async {
    final invoiceNo = _invoiceNumber(orderId);
    await _orders.doc(orderId).update({
      'status': (modified ? OrderStatus.modifiedApproved : OrderStatus.approved)
          .value,
      'invoiceNo': invoiceNo,
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return invoiceNo;
  }

  /// Rejects an order with a mandatory reason (surfaced to the dealer).
  Future<void> reject(String orderId, String reason) {
    return _orders.doc(orderId).update({
      'status': OrderStatus.rejected.value,
      'rejectionReason': reason,
      'statusNote': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Flags an already-approved order as edited so it reads "Modified & Approved".
  Future<void> markModified(String orderId) {
    return _orders.doc(orderId).update({
      'modified': true,
      'status': OrderStatus.modifiedApproved.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks an order **packed** and, the first time, removes each line's quantity
  /// from stock. Stock is deducted at PACKING-COMPLETE (packed) so the warehouse
  /// count reflects goods pulled for shipping. [Order.stockDeducted] guards
  /// against double-counting.
  Future<void> markPacked(Order order, {String? createdBy}) =>
      _deductStockAndSetStatus(order, OrderStatus.packed,
          createdBy: createdBy, reason: 'packed');

  /// Moves an order to "dispatched". If stock wasn't already deducted at packing
  /// (e.g. the order jumped straight to dispatched), it is deducted here.
  Future<void> markDispatched(Order order, {String? createdBy}) =>
      _deductStockAndSetStatus(order, OrderStatus.dispatched,
          createdBy: createdBy, reason: 'dispatch');

  /// Sets [status] and, the first time only, deducts every line's quantity from
  /// stock in one atomic batch (variant cache + an `order` inventory
  /// transaction per line). Re-entrant: if [Order.stockDeducted] is already
  /// true it just advances the status.
  Future<void> _deductStockAndSetStatus(
    Order order,
    OrderStatus status, {
    String? createdBy,
    required String reason,
  }) async {
    // Already deducted → just ensure the status.
    if (order.stockDeducted) {
      await setStatus(order.id, status);
      return;
    }

    final itemsSnap =
        await _orderItems.where('orderId', isEqualTo: order.id).get();

    // Total pieces to remove per variant (a variant can appear on >1 line).
    final qtyByVariant = <String, int>{};
    for (final doc in itemsSnap.docs) {
      final item = OrderItem.fromMap(doc.id, doc.data());
      if (item.variantId.isEmpty || item.quantity <= 0) continue;
      qtyByVariant.update(item.variantId, (v) => v + item.quantity,
          ifAbsent: () => item.quantity);
    }

    final batch = _db.batch();
    for (final entry in qtyByVariant.entries) {
      final ref = _db.collection(Collections.variants).doc(entry.key);
      final snap = await ref.get();
      final raw = (snap.data()?['currentStock'] as num?)?.toInt() ?? 0;
      final current = raw < 0 ? 0 : raw; // treat any stray negative as 0
      // Never let stock go below zero.
      final newStock = (current - entry.value) < 0 ? 0 : current - entry.value;
      final applied = current - newStock; // pieces actually removed (>= 0)
      if (applied <= 0) continue;

      batch.update(ref, {'currentStock': newStock});
      batch.set(
        _db.collection(Collections.inventoryTransactions).doc(),
        {
          'companyId': order.companyId,
          'variantId': entry.key,
          'type': InventoryTxnType.order.value,
          'quantity': -applied,
          'refType': 'order',
          'refId': order.id,
          'note': 'Auto-deducted on $reason'
              '${order.invoiceNo != null ? ' (${order.invoiceNo})' : ''}',
          'createdBy': createdBy,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    }

    batch.update(_orders.doc(order.id), {
      'status': status.value,
      'stockDeducted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Whether an order may still be deleted — only before it is dispatched.
  static bool canDelete(OrderStatus status) =>
      status != OrderStatus.dispatched &&
      status != OrderStatus.delivered &&
      status != OrderStatus.completed &&
      status != OrderStatus.returned;

  /// Deletes an order and all of its line items atomically. Callers must check
  /// [canDelete] first (dispatched/delivered orders must not be removed).
  Future<void> deleteOrder(String orderId) async {
    final itemsSnap =
        await _orderItems.where('orderId', isEqualTo: orderId).get();
    final batch = _db.batch();
    for (final doc in itemsSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_orders.doc(orderId));
    await batch.commit();
  }

  /// Admin edit: change a line's quantity (e.g. when stock is short) and
  /// recompute the whole order's totals atomically. If [newQty] <= 0 the line is
  /// removed. Returns the new grand total.
  ///
  /// If stock was already deducted (order is packed/onward), the change is also
  /// applied to inventory: increasing the quantity removes the extra pieces from
  /// stock, decreasing (or removing) the line adds them back — each as its own
  /// `order` inventory transaction so the audit trail stays correct.
  Future<double> updateItemQuantity(
      String orderId, String itemId, int newQty,
      {String? createdBy}) async {
    // Two-stage totals: line totals carry only the product discount; the stored
    // global % is re-applied to the after-product subtotal.
    final orderSnap = await _orders.doc(orderId).get();
    final orderData = orderSnap.data() ?? const {};
    final globalPct =
        (orderData['globalDiscountPercent'] as num?)?.toDouble() ?? 0;
    final stockDeducted = orderData['stockDeducted'] as bool? ?? false;
    final companyId = orderData['companyId'] as String? ?? 'default';
    final invoiceNo = orderData['invoiceNo'] as String?;
    final itemsSnap =
        await _orderItems.where('orderId', isEqualTo: orderId).get();
    final batch = _db.batch();

    // Applies an inventory delta for the edited line (only after stock has been
    // deducted). +pieces added back to stock, −pieces removed. Stock is clamped
    // at zero so it never goes negative.
    Future<void> applyStockDelta(String variantId, int stockDelta) async {
      if (!stockDeducted || variantId.isEmpty || stockDelta == 0) return;
      final ref = _db.collection(Collections.variants).doc(variantId);
      final snap = await ref.get();
      final raw = (snap.data()?['currentStock'] as num?)?.toInt() ?? 0;
      final current = raw < 0 ? 0 : raw; // treat any stray negative as 0
      final desired = current + stockDelta;
      final newStock = desired < 0 ? 0 : desired;
      final applied = newStock - current; // actual change (>=/<= 0)
      if (applied == 0) return;
      batch.update(ref, {'currentStock': newStock});
      batch.set(
        _db.collection(Collections.inventoryTransactions).doc(),
        {
          'companyId': companyId,
          'variantId': variantId,
          'type': InventoryTxnType.order.value,
          'quantity': applied,
          'refType': 'order',
          'refId': orderId,
          'note': 'Order edit after packing'
              '${invoiceNo != null ? ' ($invoiceNo)' : ''}',
          'createdBy': createdBy,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    }

    var subtotal = 0.0, productDiscount = 0.0, afterProduct = 0.0;
    var count = 0;
    for (final d in itemsSnap.docs) {
      final it = OrderItem.fromMap(d.id, d.data());
      final isTarget = d.id == itemId;
      if (isTarget && newQty <= 0) {
        // Line removed → return its (already-deducted) pieces to stock.
        await applyStockDelta(it.variantId, it.quantity);
        batch.delete(d.reference);
        continue;
      }
      final qty = isTarget ? newQty : it.quantity;
      final gross = it.rate * qty;
      final discAmt = gross * it.discountPercent / 100;
      final lineTotal = gross - discAmt;
      subtotal += gross;
      productDiscount += discAmt;
      afterProduct += lineTotal;
      count++;
      if (isTarget) {
        // stockDelta = old − new: more ordered removes stock (negative),
        // less ordered restores stock (positive).
        await applyStockDelta(it.variantId, it.quantity - newQty);
        batch.update(d.reference, {'quantity': newQty, 'total': lineTotal});
      }
    }
    final globalDiscount = afterProduct * globalPct / 100;
    final grandTotal = afterProduct - globalDiscount;
    batch.update(_orders.doc(orderId), {
      'subtotal': subtotal,
      'discountTotal': productDiscount + globalDiscount,
      'grandTotal': grandTotal,
      'itemCount': count,
      'modified': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return grandTotal;
  }

  /// Marks (or unmarks) an order line as picked from the warehouse during
  /// packing. Purely a fulfillment checklist flag; totals are untouched.
  Future<void> setItemPicked(String itemId, bool picked) {
    return _orderItems.doc(itemId).update({
      'picked': picked,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks several order lines picked/unpicked at once (product-wide "select
  /// all"). No-op for an empty list.
  Future<void> setItemsPicked(Iterable<String> itemIds, bool picked) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_orderItems.doc(id), {
        'picked': picked,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Non-deducting status transitions (reject, packing, packed, delivered…).
  /// Dispatch should go through [markDispatched] so stock is deducted.
  Future<void> setStatus(String orderId, OrderStatus status, {String? note}) {
    return _orders.doc(orderId).update({
      'status': status.value,
      if (note != null) 'statusNote': note,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Readable, unique invoice number, e.g. `INV-260730-3F9AB`.
  String _invoiceNumber(String orderId) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(now.year % 100)}${two(now.month)}${two(now.day)}';
    final suffix = (orderId.length <= 5 ? orderId : orderId.substring(0, 5))
        .toUpperCase();
    return 'INV-$stamp-$suffix';
  }
}
