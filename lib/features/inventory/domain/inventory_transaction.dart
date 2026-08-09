import 'package:cloud_firestore/cloud_firestore.dart';

/// Transaction types that move stock. Positive quantities add stock,
/// negative quantities remove it.
enum InventoryTxnType {
  opening('opening'),
  purchase('purchase'),
  production('production'),
  adjustment('adjustment'),
  damage('damage'),
  order('order'),
  ret('return'),
  correction('correction');

  const InventoryTxnType(this.value);
  final String value;

  static InventoryTxnType fromValue(String? v) =>
      InventoryTxnType.values.firstWhere(
        (t) => t.value == v,
        orElse: () => InventoryTxnType.adjustment,
      );
}

/// An immutable stock movement (`inventory_transactions/{id}`).
///
/// Stock is NEVER edited directly. A variant's true stock is the SUM of the
/// [quantity] of all its transactions. This gives a complete audit trail and
/// makes reporting (damage, returns, purchases) trivial.
class InventoryTransaction {
  const InventoryTransaction({
    required this.id,
    required this.companyId,
    required this.variantId,
    required this.type,
    required this.quantity,
    this.refType,
    this.refId,
    this.note,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String variantId;
  final InventoryTxnType type;

  /// Signed quantity: positive = stock in, negative = stock out.
  final int quantity;
  final String? refType; // order | purchase | manual
  final String? refId;
  final String? note;
  final String? createdBy;
  final DateTime? createdAt;

  factory InventoryTransaction.fromMap(String id, Map<String, dynamic> map) {
    return InventoryTransaction(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      variantId: map['variantId'] as String? ?? '',
      type: InventoryTxnType.fromValue(map['type'] as String?),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      refType: map['refType'] as String?,
      refId: map['refId'] as String?,
      note: map['note'] as String?,
      createdBy: map['createdBy'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'variantId': variantId,
        'type': type.value,
        'quantity': quantity,
        'refType': refType,
        'refId': refId,
        'note': note,
        'createdBy': createdBy,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
      };
}
