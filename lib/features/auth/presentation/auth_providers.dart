import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/app_user.dart';

/// Streams the raw Firebase auth state.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Resolves the [AppUser] profile (role, party link) for the signed-in account.
/// Emits `null` when signed out or the profile document is missing.
final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  final authUser = ref.watch(authStateProvider).valueOrNull;
  if (authUser == null) return null;
  return ref.watch(authRepositoryProvider).loadProfile(authUser.uid);
});
