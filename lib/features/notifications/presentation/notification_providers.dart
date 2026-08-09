import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/notification_repository.dart';
import '../domain/app_notification.dart';

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(currentUserProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watchForUser(uid);
});

final unreadNotificationsProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return list.where((n) => !n.read).length;
});
