import 'package:cloud_firestore/cloud_firestore.dart';

/// The unit categories a raw material can be measured in, each mapped to its
/// specific units. Picking a category (e.g. Weight) narrows the unit choice
/// (kg / gram / mg …).
const rawMaterialUnitTypes = <String, List<String>>{
  'Pieces': ['pcs', 'nos', 'dozen', 'box', 'pack'],
  'Weight': ['kg', 'gram', 'mg', 'ton', 'quintal'],
  'Length': ['meter', 'cm', 'mm', 'feet', 'inch'],
  'Size': ['sq feet', 'sq meter', 'sq inch', 'sq cm'],
  'Volume': ['litre', 'ml', 'gallon', 'cubic meter'],
};

/// A raw material used in production (`raw_materials/{id}`). Stock is a double so
/// fractional units (e.g. 12.5 kg) are supported; whole values display without
/// decimals.
class RawMaterial {
  const RawMaterial({
    required this.id,
    required this.companyId,
    required this.name,
    this.imageUrl = '',
    this.attributes = const {},
    this.unitType = 'Pieces',
    this.unit = 'pcs',
    this.currentStock = 0,
    this.minStock = 0,
    this.note,
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String imageUrl;

  /// Free-form key/value details (e.g. Grade: A, Colour: White).
  final Map<String, String> attributes;

  /// One of [rawMaterialUnitTypes] keys (Pieces / Weight / Length / Size /
  /// Volume) and the chosen specific [unit].
  final String unitType;
  final String unit;

  final double currentStock;
  final double minStock;
  final String? note;
  final String status;
  final DateTime? createdAt;

  bool get isLowStock => currentStock <= minStock;

  /// Stock formatted without trailing zeros, suffixed with the unit.
  String get stockLabel => '${_fmt(currentStock)} $unit';
  static String fmt(double v) => _fmt(v);
  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  factory RawMaterial.fromMap(String id, Map<String, dynamic> m) => RawMaterial(
        id: id,
        companyId: m['companyId'] as String? ?? 'default',
        name: m['name'] as String? ?? '',
        imageUrl: m['imageUrl'] as String? ?? '',
        attributes: (m['attributes'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
        unitType: m['unitType'] as String? ?? 'Pieces',
        unit: m['unit'] as String? ?? 'pcs',
        currentStock: (m['currentStock'] as num?)?.toDouble() ?? 0,
        minStock: (m['minStock'] as num?)?.toDouble() ?? 0,
        note: m['note'] as String?,
        status: m['status'] as String? ?? 'active',
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'name': name,
        'imageUrl': imageUrl,
        'attributes': attributes,
        'unitType': unitType,
        'unit': unit,
        'currentStock': currentStock,
        'minStock': minStock,
        'note': note,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Fields an edit may change (stock is managed via dedicated stock actions).
  Map<String, dynamic> toUpdateMap() => {
        'name': name,
        'imageUrl': imageUrl,
        'attributes': attributes,
        'unitType': unitType,
        'unit': unit,
        'minStock': minStock,
        'note': note,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// A stock movement for a raw material (`raw_material_transactions/{id}`).
/// Positive quantity = stock in, negative = correction down.
class RawMaterialTxn {
  const RawMaterialTxn({
    required this.id,
    required this.rawMaterialId,
    required this.quantity,
    required this.type, // opening | add | adjust
    this.note,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String rawMaterialId;
  final double quantity;
  final String type;
  final String? note;
  final String? createdBy;
  final DateTime? createdAt;

  factory RawMaterialTxn.fromMap(String id, Map<String, dynamic> m) =>
      RawMaterialTxn(
        id: id,
        rawMaterialId: m['rawMaterialId'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        type: m['type'] as String? ?? 'adjust',
        note: m['note'] as String?,
        createdBy: m['createdBy'] as String?,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );
}
