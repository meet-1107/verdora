import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A product category (`categories/{id}`). Categories are fully dynamic and
/// company-scoped so the same app serves any wholesale business.
class Category extends Equatable {
  const Category({
    required this.id,
    required this.companyId,
    required this.name,
    this.description = '',
    this.imageUrl,
    this.sortOrder = 0,
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String description;
  final String? imageUrl;
  final int sortOrder;
  final String status; // active | archived
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  Category copyWith({
    String? name,
    String? description,
    String? imageUrl,
    int? sortOrder,
    String? status,
  }) {
    return Category(
      id: id,
      companyId: companyId,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      sortOrder: sortOrder ?? this.sortOrder,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory Category.fromMap(String id, Map<String, dynamic> map) {
    return Category(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      imageUrl: map['imageUrl'] as String?,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'active',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'sortOrder': sortOrder,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toUpdateMap() => {
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'sortOrder': sortOrder,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props => [id, companyId, name, status, sortOrder];
}
