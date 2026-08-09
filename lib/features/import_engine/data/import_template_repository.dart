import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/import_models.dart';

final importTemplateRepositoryProvider =
    Provider<ImportTemplateRepository>((ref) {
  return ImportTemplateRepository(ref.watch(firestoreProvider));
});

/// Saved column-mapping templates so a supplier's format is mapped once and
/// reused (e.g. "PVC Factory Format").
class ImportTemplateRepository {
  ImportTemplateRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Collections.importTemplates);

  Stream<List<ImportTemplate>> watch(String companyId, String target) {
    return _col
        .where('companyId', isEqualTo: companyId)
        .where('target', isEqualTo: target)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => ImportTemplate.fromMap(d.id, d.data())).toList());
  }

  Future<void> save(ImportTemplate t) => _col.add(t.toMap());
  Future<void> delete(String id) => _col.doc(id).delete();
}

/// Templates for the current company + target collection.
final importTemplatesProvider =
    StreamProvider.family<List<ImportTemplate>, String>((ref, target) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref
      .watch(importTemplateRepositoryProvider)
      .watch(user.companyId, target);
});
