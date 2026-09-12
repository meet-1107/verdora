// `Order` is also exported by cloud_firestore; hide it so our domain Order wins.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
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

  /// Every line item in the company (admin reports & backup).
  Stream<List<OrderItem>> watchAllItems(String companyId) {
    return _orderItems.where('companyId', isEqualTo: companyId).snapshots().map(
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

  /// Marks an order **packed**. Stock is NOT touched here — it is deducted only
  /// on DISPATCH (see [markDispatched]).
  Future<void> markPacked(Order order, {String? createdBy}) =>
      setStatus(order.id, OrderStatus.packed);

  /// Moves an order to "dispatched" and, the first time, removes each line's
  /// quantity from stock. Stock is deducted on DISPATCH so nothing leaves the
  /// books until the goods actually ship. [Order.stockDeducted] guards against
  /// double-counting.
  Future<void> markDispatched(Order order, {String? createdBy}) =>
      _deductStockAndSetStatus(order, OrderStatus.dispatched,
          createdBy: createdBy, reason: 'dispatch');

  /// Dispatches only the quantities in [dispatchByItem] (itemId → qty to send
  /// now). Any shortfall (ordered − dispatched, per line) is split off into a
  /// NEW approved order — a "backorder" — linked to this order, so the missing
  /// pieces are remembered and fulfilled later. The original order is reduced to
  /// the dispatched quantities and marked dispatched (stock deducted for those).
  ///
  /// Returns the backorder's ids, or null when nothing was short (a normal full
  /// dispatch).
  Future<({String id, String orderNo})?> dispatchWithBackorder({
    required Order order,
    required Map<String, int> dispatchByItem,
    String? createdBy,
  }) async {
    final itemsSnap =
        await _orderItems.where('orderId', isEqualTo: order.id).get();
    final items =
        itemsSnap.docs.map((d) => OrderItem.fromMap(d.id, d.data())).toList();

    // Split each line into dispatched-now and short quantities.
    final shortItems = <OrderItem>[];
    var anyDispatched = false;
    for (final it in items) {
      final raw = dispatchByItem[it.id] ?? it.quantity;
      final send = raw < 0 ? 0 : (raw > it.quantity ? it.quantity : raw);
      final short = it.quantity - send;
      if (send > 0) anyDispatched = true;
      if (short > 0) {
        shortItems.add(OrderItem(
          id: '',
          companyId: it.companyId,
          orderId: '',
          variantId: it.variantId,
          productName: it.productName,
          variantLabel: it.variantLabel,
          rate: it.rate,
          quantity: short,
          discountPercent: it.discountPercent,
          taxPercent: it.taxPercent,
        ));
      }
    }

    if (!anyDispatched) {
      throw Exception('Nothing to dispatch — set a quantity for at least one '
          'line.');
    }

    // No shortage → ordinary full dispatch.
    if (shortItems.isEmpty) {
      await markDispatched(order, createdBy: createdBy);
      return null;
    }

    // 1) Create the backorder (approved, ready to pack) with the short lines.
    final backTotals = _totalsFor(shortItems, order.globalDiscountPercent);
    final backHeader = Order(
      id: '',
      companyId: order.companyId,
      partyId: order.partyId,
      partyName: order.partyName,
      partyCode: order.partyCode,
      status: OrderStatus.approved,
      globalDiscountPercent: order.globalDiscountPercent,
      subtotal: backTotals.subtotal,
      discountTotal: backTotals.discountTotal,
      taxTotal: backTotals.taxTotal,
      grandTotal: backTotals.grandTotal,
      itemCount: shortItems.length,
      note: 'Backorder of ${order.orderNo ?? order.displayId}',
      placedByAdmin: order.placedByAdmin,
      createdByUid: order.createdByUid,
      backorderOf: order.id,
      backorderOfNo: order.orderNo,
    );
    final back = await createOrder(
      order: backHeader,
      items: shortItems,
      clientCode: order.partyCode ?? order.partyName,
    );
    // Give the backorder its own invoice number + approval timestamp.
    await _orders.doc(back.id).update({
      'invoiceNo': _invoiceNumber(back.id),
      'approvedAt': FieldValue.serverTimestamp(),
    });

    // 2) Reduce the original order to the dispatched quantities.
    final batch = _db.batch();
    final dispatched = <OrderItem>[];
    for (final it in items) {
      final raw = dispatchByItem[it.id] ?? it.quantity;
      final send = raw < 0 ? 0 : (raw > it.quantity ? it.quantity : raw);
      if (send <= 0) {
        batch.delete(_orderItems.doc(it.id)); // fully backordered
        continue;
      }
      dispatched.add(OrderItem(
        id: it.id,
        companyId: it.companyId,
        orderId: it.orderId,
        variantId: it.variantId,
        productName: it.productName,
        variantLabel: it.variantLabel,
        rate: it.rate,
        quantity: send,
        discountPercent: it.discountPercent,
        taxPercent: it.taxPercent,
        picked: it.picked,
      ));
      if (send != it.quantity) {
        batch.update(_orderItems.doc(it.id),
            {'quantity': send, 'total': it.rate * send * (1 - it.discountPercent / 100)});
      }
    }
    final totals = _totalsFor(dispatched, order.globalDiscountPercent);
    batch.update(_orders.doc(order.id), {
      'subtotal': totals.subtotal,
      'discountTotal': totals.discountTotal,
      'taxTotal': totals.taxTotal,
      'grandTotal': totals.grandTotal,
      'itemCount': dispatched.length,
      'modified': true,
      'backorderId': back.id,
      'backorderNo': back.orderNo,
      'statusNote': '${shortItems.length} item(s) short — moved to '
          '${back.orderNo}',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    // 3) Dispatch the original (deducts stock + raw materials for the sent qty).
    await markDispatched(order, createdBy: createdBy);
    return back;
  }

  /// Two-stage totals for a set of lines: per-line product discount, then the
  /// order-level global %, then GST — mirroring [updateItemQuantity].
  ({double subtotal, double discountTotal, double taxTotal, double grandTotal})
      _totalsFor(List<OrderItem> lines, double globalPct) {
    var subtotal = 0.0, productDiscount = 0.0, afterProduct = 0.0;
    for (final it in lines) {
      final gross = it.rate * it.quantity;
      final discAmt = gross * it.discountPercent / 100;
      subtotal += gross;
      productDiscount += discAmt;
      afterProduct += gross - discAmt;
    }
    final globalDiscount = afterProduct * globalPct / 100;
    final taxable = afterProduct - globalDiscount;
    final tax = taxable * AppConstants.gstRate / 100;
    return (
      subtotal: subtotal,
      discountTotal: productDiscount + globalDiscount,
      taxTotal: tax,
      grandTotal: taxable + tax,
    );
  }

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
    final rawDelta = <String, double>{};
    for (final entry in qtyByVariant.entries) {
      final ref = _db.collection(Collections.variants).doc(entry.key);
      final snap = await ref.get();
      final raw = (snap.data()?['currentStock'] as num?)?.toInt() ?? 0;
      final current = raw < 0 ? 0 : raw; // treat any stray negative as 0
      // Never let stock go below zero.
      final newStock = (current - entry.value) < 0 ? 0 : current - entry.value;
      final applied = current - newStock; // pieces actually removed (>= 0)
      if (applied <= 0) continue;

      // Consume this variant's raw materials for the pieces actually removed.
      _accumulateBom(snap.data(), applied, rawDelta);

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

    await _applyRawConsumption(batch, order.companyId, rawDelta,
        reason: 'Consumed on $reason'
            '${order.invoiceNo != null ? ' (${order.invoiceNo})' : ''}',
        refId: order.id,
        createdBy: createdBy);

    batch.update(_orders.doc(order.id), {
      'status': status.value,
      'stockDeducted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Accumulates raw-material consumption for a product variant into [rawDelta]
  /// (keyed by raw-material variant id; negative = consume, positive = restore).
  /// [piecesRemoved] is how many units left product stock (> 0 consumes raw;
  /// < 0, i.e. a restore, returns raw).
  void _accumulateBom(Map<String, dynamic>? variantData, int piecesRemoved,
      Map<String, double> rawDelta) {
    if (variantData == null || piecesRemoved == 0) return;
    final bom = variantData['bom'];
    if (bom is! List) return;
    for (final e in bom) {
      if (e is! Map) continue;
      final id = e['rawVariantId'] as String? ?? '';
      final qty = (e['qty'] as num?)?.toDouble() ?? 0;
      if (id.isEmpty || qty <= 0) continue;
      final delta = -piecesRemoved * qty; // removed → negative (consume)
      rawDelta.update(id, (v) => v + delta, ifAbsent: () => delta);
    }
  }

  /// Applies the accumulated [rawDelta] to `raw_material_variants` stock (clamped
  /// at zero) and logs one `raw_material_transactions` entry per affected
  /// variant, all into [batch].
  Future<void> _applyRawConsumption(
    WriteBatch batch,
    String companyId,
    Map<String, double> rawDelta, {
    required String reason,
    String? refId,
    String? createdBy,
  }) async {
    for (final entry in rawDelta.entries) {
      if (entry.value == 0) continue;
      final ref =
          _db.collection(Collections.rawMaterialVariants).doc(entry.key);
      final snap = await ref.get();
      if (!snap.exists) continue;
      final current = (snap.data()?['currentStock'] as num?)?.toDouble() ?? 0;
      final desired = current + entry.value;
      final newStock = desired < 0 ? 0.0 : desired;
      final applied = newStock - current;
      if (applied == 0) continue;
      batch.update(ref, {
        'currentStock': newStock,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(
        _db.collection(Collections.rawMaterialTransactions).doc(),
        {
          'companyId': companyId,
          'rawMaterialId': snap.data()?['rawMaterialId'],
          'variantId': entry.key,
          'quantity': applied,
          'type': 'consume',
          'note': reason,
          'refType': 'order',
          'refId': refId,
          'createdBy': createdBy,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    }
  }

  /// Whether a **client** may still delete an order — only before it is
  /// dispatched. (Admins can go further; see [canAdminDelete].)
  static bool canDelete(OrderStatus status) =>
      status != OrderStatus.dispatched &&
      status != OrderStatus.delivered &&
      status != OrderStatus.completed &&
      status != OrderStatus.returned;

  /// Whether an **admin** may delete an order. Permitted up to and including
  /// the final `dispatched` state (its stock is returned on delete); only the
  /// retired terminal states stay protected so historical records are intact.
  static bool canAdminDelete(OrderStatus status) =>
      status != OrderStatus.delivered &&
      status != OrderStatus.completed &&
      status != OrderStatus.returned;

  /// Deletes an order and all of its line items atomically. Callers must gate
  /// on [canDelete] (client) or [canAdminDelete] (admin) first. If the order's
  /// stock was already deducted (it had been
  /// dispatched), every line's quantity is added back to inventory in the same
  /// batch — one `order` inventory transaction per variant for the audit trail —
  /// so deleting a dispatched order never leaves stock permanently short.
  Future<void> deleteOrder(String orderId, {String? createdBy}) async {
    final orderRef = _orders.doc(orderId);
    final orderSnap = await orderRef.get();
    final orderData = orderSnap.data() ?? const {};
    final stockDeducted = orderData['stockDeducted'] as bool? ?? false;
    final companyId = orderData['companyId'] as String? ?? 'default';
    final invoiceNo = orderData['invoiceNo'] as String?;

    final itemsSnap =
        await _orderItems.where('orderId', isEqualTo: orderId).get();
    final batch = _db.batch();

    // Return dispatched quantities to stock before the lines are removed.
    if (stockDeducted) {
      // Total pieces to restore per variant (a variant can span >1 line).
      final qtyByVariant = <String, int>{};
      for (final doc in itemsSnap.docs) {
        final item = OrderItem.fromMap(doc.id, doc.data());
        if (item.variantId.isEmpty || item.quantity <= 0) continue;
        qtyByVariant.update(item.variantId, (v) => v + item.quantity,
            ifAbsent: () => item.quantity);
      }
      final rawDelta = <String, double>{};
      for (final entry in qtyByVariant.entries) {
        final ref = _db.collection(Collections.variants).doc(entry.key);
        final snap = await ref.get();
        final raw = (snap.data()?['currentStock'] as num?)?.toInt() ?? 0;
        final current = raw < 0 ? 0 : raw; // treat any stray negative as 0
        // Returning pieces to product stock → return their raw materials too.
        _accumulateBom(snap.data(), -entry.value, rawDelta);
        batch.update(ref, {'currentStock': current + entry.value});
        batch.set(
          _db.collection(Collections.inventoryTransactions).doc(),
          {
            'companyId': companyId,
            'variantId': entry.key,
            'type': InventoryTxnType.order.value,
            'quantity': entry.value,
            'refType': 'order',
            'refId': orderId,
            'note': 'Restored on order delete'
                '${invoiceNo != null ? ' ($invoiceNo)' : ''}',
            'createdBy': createdBy,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }
      await _applyRawConsumption(batch, companyId, rawDelta,
          reason: 'Returned on order delete'
              '${invoiceNo != null ? ' ($invoiceNo)' : ''}',
          refId: orderId,
          createdBy: createdBy);
    }

    for (final doc in itemsSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(orderRef);
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
      {String? createdBy, bool markModified = true}) async {
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
    final rawDelta = <String, double>{};

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
      // Mirror the raw-material movement: stock added back returns raw,
      // stock removed consumes raw. piecesRemoved = -applied.
      _accumulateBom(snap.data(), -applied, rawDelta);
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
    // Re-apply 18% GST on the net amount so the edited order's final amount
    // stays tax-inclusive (matches how it was created).
    final taxable = afterProduct - globalDiscount;
    final tax = taxable * AppConstants.gstRate / 100;
    final grandTotal = taxable + tax;
    await _applyRawConsumption(batch, companyId, rawDelta,
        reason: 'Order edit after packing'
            '${invoiceNo != null ? ' ($invoiceNo)' : ''}',
        refId: orderId,
        createdBy: createdBy);

    batch.update(_orders.doc(orderId), {
      'subtotal': subtotal,
      'discountTotal': productDiscount + globalDiscount,
      'taxTotal': tax,
      'grandTotal': grandTotal,
      'itemCount': count,
      if (markModified) 'modified': true,
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
