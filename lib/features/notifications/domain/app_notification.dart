import 'package:cloud_firestore/cloud_firestore.dart';

/// An in-app notification (`notifications/{id}`). Created by Cloud Functions
/// (order status changes) or admin broadcasts.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.title,
    required this.body,
    this.type = 'general',
    this.refId,
    this.read = false,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String userId;
  final String title;
  final String body;
  final String type;
  final String? refId;
  final bool read;
  final DateTime? createdAt;

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      userId: map['userId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      type: map['type'] as String? ?? 'general',
      refId: map['refId'] as String?,
      read: map['read'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
