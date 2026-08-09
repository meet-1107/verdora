import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/party.dart';

final partyRepositoryProvider = Provider<PartyRepository>((ref) {
  return PartyRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
  );
});

class PartyRepository {
  PartyRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Collections.parties);

  Stream<List<Party>> watchAll(String companyId) {
    return _col
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map((s) => s.docs.map((d) => Party.fromMap(d.id, d.data())).toList());
  }

  /// Creates the party record AND attempts to provision its client login via
  /// the `createClientUser` Cloud Function.
  ///
  /// The party record is ALWAYS saved. If the login can't be created (e.g. the
  /// Cloud Function isn't deployed — it needs the Blaze plan), the party is
  /// kept and a [PartyLoginPendingException] is thrown so the UI can tell the
  /// admin the login is pending rather than losing the party they just entered.
  Future<void> createWithLogin({
    required Party party,
    required String password,
  }) async {
    // Store the login password on the party doc so the admin can view/share it.
    final docRef = await _col.add({...party.toMap(), 'loginPassword': password});
    try {
      final callable = _functions.httpsCallable('createClientUser');
      await callable.call<Map<String, dynamic>>({
        'loginCode': party.partyCode,
        'partyId': docRef.id,
        'password': password,
        'name': party.name,
        'companyId': party.companyId,
        'phone': party.phone,
      });
    } catch (e) {
      throw PartyLoginPendingException(e.toString());
    }
  }

  Future<void> update(Party party) => _col.doc(party.id).update(party.toMap());

  /// Creates OR resets this dealer's login via the `provisionClientLogin` Cloud
  /// Function, then stores the (new) password on the party so the admin can
  /// view it. Fixes dealers created before Functions were deployed and resets
  /// forgotten passwords. Throws [PartyLoginPendingException] if the function is
  /// unreachable (not deployed).
  Future<void> provisionLogin({
    required Party party,
    required String password,
  }) async {
    try {
      final callable = _functions.httpsCallable('provisionClientLogin');
      await callable.call<Map<String, dynamic>>({
        'loginCode': party.partyCode,
        'partyId': party.id,
        'password': password,
        'name': party.name,
        'companyId': party.companyId,
        'phone': party.phone,
      });
    } catch (e) {
      throw PartyLoginPendingException(e.toString());
    }
    await _col.doc(party.id).update({'loginPassword': password});
  }

  /// Sets a party's global (default) discount percent — the baseline applied to
  /// all of that dealer's products unless a more specific rule overrides it.
  Future<void> setDefaultDiscount(String id, double percent) =>
      _col.doc(id).update({'defaultDiscount': percent});

  Future<void> setStatus(String id, String status) =>
      _col.doc(id).update({'status': status});

  /// Permanently deletes a party AND revokes its client login(s).
  ///
  /// Every linked user doc (matched by `partyId`) is deleted in the same batch,
  /// which immediately cuts off the dealer's access — the app resolves a
  /// signed-in user through their `users` doc, so removing it locks them out on
  /// their next app open / auth refresh. (The Firebase Auth account itself can
  /// only be removed by a Cloud Function, which isn't deployed; deleting the
  /// user doc is sufficient to block all access in this app.)
  Future<void> deleteWithAccess(String partyId) async {
    final linkedUsers = await _db
        .collection(Collections.users)
        .where('partyId', isEqualTo: partyId)
        .get();
    final batch = _db.batch();
    for (final doc in linkedUsers.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_col.doc(partyId));
    await batch.commit();
  }
}

/// Thrown when a party record was saved but its login could not be provisioned
/// (usually because Cloud Functions are not deployed yet).
class PartyLoginPendingException implements Exception {
  PartyLoginPendingException(this.details);
  final String details;
  @override
  String toString() => 'PartyLoginPendingException: $details';
}
