/// A sellable variant of a product (`variants/{id}`), e.g. "20 mm".
///
/// [currentStock] is a CACHE maintained by inventory transactions — it is never
/// the source of truth. The authoritative stock is the sum of
/// `inventory_transactions` for this variant (see [InventoryTransaction]).
class Variant {
  const Variant({
    required this.id,
    required this.companyId,
    required this.productId,
    required this.attributes,
    required this.rate,
    this.pack = 1,
    this.boxPack = 1,
    this.sku,
    this.barcode,
    this.currentStock = 0,
    this.minStock = 0,
    this.maxStock = 0,
    this.status = 'active',
  });

  final String id;
  final String companyId;
  final String productId;

  /// Dynamic per-variant attributes (Size, Color, Length…) as key/value pairs.
  final Map<String, String> attributes;
  final double rate;
  final int pack;
  final int boxPack;
  final String? sku;
  final String? barcode;
  final int currentStock;
  final int minStock;
  final int maxStock;
  final String status;

  bool get isLowStock => currentStock <= minStock;

  factory Variant.fromMap(String id, Map<String, dynamic> map) {
    return Variant(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      productId: map['productId'] as String? ?? '',
      attributes: (map['attributes'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          const {},
      rate: (map['rate'] as num?)?.toDouble() ?? 0,
      pack: (map['pack'] as num?)?.toInt() ?? 1,
      boxPack: (map['boxPack'] as num?)?.toInt() ?? 1,
      sku: map['sku'] as String?,
      barcode: map['barcode'] as String?,
      // Stock is never negative in the app; clamp any stray negative cache to 0.
      currentStock: () {
        final s = (map['currentStock'] as num?)?.toInt() ?? 0;
        return s < 0 ? 0 : s;
      }(),
      minStock: (map['minStock'] as num?)?.toInt() ?? 0,
      maxStock: (map['maxStock'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'productId': productId,
        'attributes': attributes,
        'rate': rate,
        'pack': pack,
        'boxPack': boxPack,
        'sku': sku,
        'barcode': barcode,
        'currentStock': currentStock,
        'minStock': minStock,
        'maxStock': maxStock,
        'status': status,
      };
}
