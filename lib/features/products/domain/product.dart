import 'package:cloud_firestore/cloud_firestore.dart';

/// A product (`products/{id}`). Product-level attributes are DYNAMIC key/value
/// pairs so the same app fits any industry (plumbing, electrical, hardware…).
/// Sizes/rates/stock live on [Variant], never on the product itself.
class Product {
  const Product({
    required this.id,
    required this.companyId,
    required this.categoryId,
    required this.name,
    this.subcategoryId,
    this.description = '',
    this.imageUrls = const [],
    this.attributes = const [],
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String categoryId;
  final String? subcategoryId;
  final String name;
  final String description;
  final List<String> imageUrls;

  /// Dynamic attributes, e.g. [{key: 'Material', value: 'UPVC'}].
  final List<ProductAttribute> attributes;
  final String status; // active | archived
  final DateTime? createdAt;

  factory Product.fromMap(String id, Map<String, dynamic> map) {
    return Product(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      categoryId: map['categoryId'] as String? ?? '',
      subcategoryId: map['subcategoryId'] as String?,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      imageUrls: (map['imageUrls'] as List?)?.cast<String>() ?? const [],
      attributes: (map['attributes'] as List?)
              ?.map((e) =>
                  ProductAttribute.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      status: map['status'] as String? ?? 'active',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'categoryId': categoryId,
        'subcategoryId': subcategoryId,
        'name': name,
        'description': description,
        'imageUrls': imageUrls,
        'attributes': attributes.map((a) => a.toMap()).toList(),
        'status': status,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
      };
}

class ProductAttribute {
  const ProductAttribute({required this.key, required this.value});
  final String key;
  final String value;

  factory ProductAttribute.fromMap(Map<String, dynamic> map) =>
      ProductAttribute(
        key: map['key'] as String? ?? '',
        value: map['value'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {'key': key, 'value': value};
}
