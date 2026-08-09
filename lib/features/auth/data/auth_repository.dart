import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/app_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
  );
});

class AuthRepository {
  AuthRepository(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// Admins sign in with their real email.
  Future<void> signInAdmin({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Clients sign in with a Party ID which is mapped to a synthetic email.
  Future<void> signInClient({
    required String partyId,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: partyIdToEmail(partyId),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Loads the `users/{uid}` profile document for the signed-in account.
  Future<AppUser?> loadProfile(String uid) async {
    final doc = await _db.collection(Collections.users).doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.id, doc.data()!);
  }

  static String partyIdToEmail(String partyId) {
    final normalized = partyId.trim().toLowerCase();
    return '$normalized@${AppConstants.partyEmailDomain}';
  }
}
