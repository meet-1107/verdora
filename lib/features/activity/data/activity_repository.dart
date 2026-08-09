import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/activity_log.dart';

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return ActivityRepository(ref.watch(firestoreProvider));
});

class ActivityRepository {
  ActivityRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Collections.logs);

  Future<void> log({
    required String companyId,
    required String userId,
    required String userName,
    required String action,
    String? target,
  }) {
    return _col.add({
      'companyId': companyId,
      'userId': userId,
      'userName': userName,
      'action': action,
      'target': target,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<ActivityLog>> watchRecent(String companyId, {int limit = 200}) {
    return _col
        .where('companyId', isEqualTo: companyId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => ActivityLog.fromMap(d.id, d.data())).toList());
  }
}

/// Convenience: logs an action using the signed-in admin's identity.
final activityLoggerProvider = Provider<ActivityLogger>((ref) {
  return ActivityLogger(ref);
});

class ActivityLogger {
  ActivityLogger(this._ref);
  final Ref _ref;

  Future<void> record(String action, {String? target}) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    await _ref.read(activityRepositoryProvider).log(
          companyId: user.companyId,
          userId: user.uid,
          userName: user.name,
          action: action,
          target: target,
        );
  }
}
