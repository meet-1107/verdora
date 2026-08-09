import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/party_repository.dart';
import '../domain/party.dart';

final partiesProvider = StreamProvider<List<Party>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(partyRepositoryProvider).watchAll(user.companyId);
});

/// The party record for the signed-in client (via their linked partyId). Live
/// so discount / detail changes made by the admin reach the dealer immediately
/// (e.g. a global discount applies to the very next order without re-login).
final currentPartyProvider = StreamProvider<Party?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final partyId = user?.partyId;
  if (partyId == null) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .collection(Collections.parties)
      .doc(partyId)
      .snapshots()
      .map((doc) =>
          doc.exists ? Party.fromMap(doc.id, doc.data()!) : null);
});
