import 'package:cloud_firestore/cloud_firestore.dart';

/// The unit categories a raw material variant can be measured in, each mapped to
/// its specific units. Picking a category (e.g. Weight) narrows the unit choice
/// (kg / gram / mg …).
const rawMaterialUnitTypes = <String, List<String>>{
  'Pieces': ['pcs', 'nos', 'dozen', 'box', 'pack'],
  'Weight': ['kg', 'gram', 'mg', 'ton', 'quintal'],
  'Length': ['meter', 'cm', 'mm', 'feet', 'inch'],
  'Size': ['sq feet', 'sq meter', 'sq inch', 'sq cm'],
  'Volume': ['litre', 'ml', 'gallon', 'cubic meter'],
};

/// Formats a stock/quantity value without trailing zeros.
String fmtQty(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// A raw material (`raw_materials/{id}`) — the parent. Its measurable stock lives
/// in its [RawMaterialVariant]s (e.g. different grades / specs), each with its
/// own unit and stock.
class RawMaterial {
  const RawMaterial({
    required this.id,
    required this.companyId,
    required this.name,
    this.imageUrl = '',
    this.note,
    this.unitType = 'Pieces',
    this.unit = 'pcs',
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String imageUrl;
  final String? note;

  /// The material's unit of measure. Its variants inherit this — the unit is a
  /// material-level property (all sizes of a Nut Bolt are still counted in pcs).
  final String unitType;
  final String unit;
  final String status;
  final DateTime? createdAt;

  factory RawMaterial.fromMap(String id, Map<String, dynamic> m) => RawMaterial(
        id: id,
        companyId: m['companyId'] as String? ?? 'default',
        name: m['name'] as String? ?? '',
        imageUrl: m['imageUrl'] as String? ?? '',
        note: m['note'] as String?,
        unitType: m['unitType'] as String? ?? 'Pieces',
        unit: m['unit'] as String? ?? 'pcs',
        status: m['status'] as String? ?? 'active',
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'name': name,
        'imageUrl': imageUrl,
        'note': note,
        'unitType': unitType,
        'unit': unit,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toUpdateMap() => {
        'name': name,
        'imageUrl': imageUrl,
        'note': note,
        'unitType': unitType,
        'unit': unit,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// A stock movement for a raw material variant
/// (`raw_material_transactions/{id}`). Positive = stock in, negative = down.
class RawMaterialTxn {
  const RawMaterialTxn({
    required this.id,
    required this.rawMaterialId,
    required this.variantId,
    required this.quantity,
    required this.type, // opening | production | purchase | return | add | adjust
    this.note,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String rawMaterialId;
  final String variantId;
  final double quantity;
  final String type;
  final String? note;
  final String? createdBy;
  final DateTime? createdAt;

  factory RawMaterialTxn.fromMap(String id, Map<String, dynamic> m) =>
      RawMaterialTxn(
        id: id,
        rawMaterialId: m['rawMaterialId'] as String? ?? '',
        variantId: m['variantId'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        type: m['type'] as String? ?? 'adjust',
        note: m['note'] as String?,
        createdBy: m['createdBy'] as String?,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );
}
