import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A subcategory (`subcategories/{id}`) belonging to a parent [categoryId].
class Subcategory extends Equatable {
  const Subcategory({
    required this.id,
    required this.companyId,
    required this.categoryId,
    required this.name,
    this.description = '',
    this.imageUrl,
    this.sortOrder = 0,
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String categoryId;
  final String name;
  final String description;
  final String? imageUrl;
  final int sortOrder;
  final String status;
  final DateTime? createdAt;

  bool get isActive => status == 'active';

  Subcategory copyWith({
    String? categoryId,
    String? name,
    String? description,
    String? imageUrl,
    int? sortOrder,
    String? status,
  }) {
    return Subcategory(
      id: id,
      companyId: companyId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      sortOrder: sortOrder ?? this.sortOrder,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  factory Subcategory.fromMap(String id, Map<String, dynamic> map) {
    return Subcategory(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      categoryId: map['categoryId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      imageUrl: map['imageUrl'] as String?,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'active',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'categoryId': categoryId,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'sortOrder': sortOrder,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toUpdateMap() => {
        'categoryId': categoryId,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'sortOrder': sortOrder,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props => [id, companyId, categoryId, name, status];
}
