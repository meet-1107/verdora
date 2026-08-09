import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/company_settings.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(firestoreProvider));
});

class SettingsRepository {
  SettingsRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String companyId) =>
      _db.collection(Collections.settings).doc(companyId);

  Stream<CompanySettings> watch(String companyId) {
    return _doc(companyId)
        .snapshots()
        .map((d) => CompanySettings.fromMap(companyId, d.data() ?? const {}));
  }

  Future<void> save(CompanySettings s) =>
      _doc(s.companyId).set(s.toMap(), SetOptions(merge: true));
}
