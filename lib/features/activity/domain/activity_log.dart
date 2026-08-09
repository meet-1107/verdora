import 'package:cloud_firestore/cloud_firestore.dart';

/// An audit-log entry (`logs/{id}`) recording an admin action.
class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.userName,
    required this.action,
    this.target,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String userId;
  final String userName;
  final String action; // e.g. 'order.approved'
  final String? target; // human-readable subject
  final DateTime? createdAt;

  factory ActivityLog.fromMap(String id, Map<String, dynamic> map) {
    return ActivityLog(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      userId: map['userId'] as String? ?? '',
      userName: map['userName'] as String? ?? '',
      action: map['action'] as String? ?? '',
      target: map['target'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
