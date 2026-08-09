import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/app_notification.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseMessagingProvider),
  );
});

class NotificationRepository {
  NotificationRepository(this._db, this._messaging);

  final FirebaseFirestore _db;
  final FirebaseMessaging _messaging;

  Stream<List<AppNotification>> watchForUser(String uid) {
    return _db
        .collection(Collections.notifications)
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AppNotification.fromMap(d.id, d.data()))
            .toList());
  }

  Future<void> markRead(String id) =>
      _db.collection(Collections.notifications).doc(id).update({'read': true});

  /// Permanently removes a notification. A recipient may delete their own; the
  /// UI commits this only after the undo window elapses.
  Future<void> delete(String id) =>
      _db.collection(Collections.notifications).doc(id).delete();

  /// Sends an in-app notification to every client of the company. Returns the
  /// number of recipients. (Push delivery is handled server-side where FCM
  /// tokens exist.)
  Future<int> broadcastToClients({
    required String companyId,
    required String title,
    required String body,
  }) async {
    final users = await _db
        .collection(Collections.users)
        .where('companyId', isEqualTo: companyId)
        .where('role', isEqualTo: 'client')
        .get();
    final batch = _db.batch();
    for (final u in users.docs) {
      final ref = _db.collection(Collections.notifications).doc();
      batch.set(ref, {
        'companyId': companyId,
        'userId': u.id,
        'title': title,
        'body': body,
        'type': 'broadcast',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return users.size;
  }

  /// Sends an in-app notification to the client user(s) linked to [partyId].
  Future<void> notifyParty({
    required String companyId,
    required String partyId,
    required String title,
    required String body,
  }) async {
    // Query by companyId only (no composite index needed) and filter locally.
    final users = await _db
        .collection(Collections.users)
        .where('companyId', isEqualTo: companyId)
        .get();
    final batch = _db.batch();
    var found = false;
    for (final u in users.docs) {
      if ((u.data()['partyId'] as String?) != partyId) continue;
      found = true;
      final ref = _db.collection(Collections.notifications).doc();
      batch.set(ref, {
        'companyId': companyId,
        'userId': u.id,
        'title': title,
        'body': body,
        'type': 'order',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    if (found) await batch.commit();
  }

  /// Requests notification permission, obtains the FCM token and stores it on
  /// the user document. Best-effort: silently no-ops if messaging is
  /// unavailable/unconfigured (e.g. web without a VAPID key).
  Future<void> registerToken(String uid) async {
    try {
      await _messaging.requestPermission();
      // On web the VAPID key is required; on Android/iOS it is ignored.
      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? AppConstants.webPushVapidKey : null,
      );
      if (token == null) return;
      await _db.collection(Collections.users).doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
    } catch (_) {
      // Messaging not configured on this platform — ignore.
    }
  }
}
