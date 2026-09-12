import 'package:cloud_firestore/cloud_firestore.dart';

import 'raw_material.dart' show fmtQty;

/// A variant of a raw material (`raw_material_variants/{id}`), e.g. Nut Bolt →
/// "1/2 inch", "3/4 inch". Each variant carries its own unit and stock.
class RawMaterialVariant {
  const RawMaterialVariant({
    required this.id,
    required this.companyId,
    required this.rawMaterialId,
    required this.label,
    this.attributes = const {},
    this.unitType = 'Pieces',
    this.unit = 'pcs',
    this.currentStock = 0,
    this.minStock = 0,
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String rawMaterialId;

  /// Human label for the variant, e.g. "1/2 inch".
  final String label;

  /// Free-form details (Grade, Colour, Thread…).
  final Map<String, String> attributes;
  final String unitType;
  final String unit;
  final double currentStock;
  final double minStock;
  final String status;
  final DateTime? createdAt;

  bool get isOutOfStock => currentStock <= 0;

  /// Low (but not out): at or below the minimum while still in stock.
  bool get isLowStock => currentStock > 0 && currentStock <= minStock;
  String get stockLabel => '${fmtQty(currentStock)} $unit';

  factory RawMaterialVariant.fromMap(String id, Map<String, dynamic> m) =>
      RawMaterialVariant(
        id: id,
        companyId: m['companyId'] as String? ?? 'default',
        rawMaterialId: m['rawMaterialId'] as String? ?? '',
        label: m['label'] as String? ?? '',
        attributes: (m['attributes'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
        unitType: m['unitType'] as String? ?? 'Pieces',
        unit: m['unit'] as String? ?? 'pcs',
        currentStock: (m['currentStock'] as num?)?.toDouble() ?? 0,
        minStock: (m['minStock'] as num?)?.toDouble() ?? 0,
        status: m['status'] as String? ?? 'active',
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'rawMaterialId': rawMaterialId,
        'label': label,
        'attributes': attributes,
        'unitType': unitType,
        'unit': unit,
        'currentStock': currentStock,
        'minStock': minStock,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toUpdateMap() => {
        'label': label,
        'attributes': attributes,
        'unitType': unitType,
        'unit': unit,
        'minStock': minStock,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
