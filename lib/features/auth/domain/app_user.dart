import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import 'user_role.dart';

/// A user document (`users/{uid}`). Links a Firebase Auth account to a role
/// and, for clients, to their party record.
class AppUser extends Equatable {
  const AppUser({
    required this.uid,
    required this.companyId,
    required this.role,
    required this.name,
    this.email,
    this.phone,
    this.partyId,
    this.status = 'active',
    this.createdAt,
  });

  final String uid;
  final String companyId;
  final UserRole role;
  final String name;
  final String? email;
  final String? phone;

  /// For client users, the id of their `parties/{partyId}` record.
  final String? partyId;
  final String status;
  final DateTime? createdAt;

  bool get isActive => status == 'active';

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      companyId: map['companyId'] as String? ?? 'default',
      role: UserRole.fromValue(map['role'] as String?),
      name: map['name'] as String? ?? '',
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      partyId: map['partyId'] as String?,
      status: map['status'] as String? ?? 'active',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'role': role.value,
        'name': name,
        'email': email,
        'phone': phone,
        'partyId': partyId,
        'status': status,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
      };

  @override
  List<Object?> get props => [uid, companyId, role, status, partyId];
}
