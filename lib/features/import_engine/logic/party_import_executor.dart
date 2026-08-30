import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/import_models.dart';
import 'party_import_config.dart';

final partyImportExecutorProvider = Provider<ImportExecutor>((ref) {
  return PartyImportExecutor(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
  );
});

/// Imports parties. New parties also get a client login provisioned via the
/// `createClientUser` Cloud Function (password from the sheet, or a generated
/// default). Existing parties (matched by Party ID) are updated in place —
/// their login is left untouched.
class PartyImportExecutor implements ImportExecutor {
  PartyImportExecutor(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  @override
  Future<List<ImportRowResult>> run({
    required String companyId,
    required ParsedTable table,
    required Map<String, String> mapping,
    required ImportMode mode,
  }) async {
    final results = <ImportRowResult>[];

    // Preload existing parties keyed by lower-cased partyCode.
    final existing = <String, DocumentReference>{};
    final snap = await _db
        .collection(Collections.parties)
        .where('companyId', isEqualTo: companyId)
        .get();
    for (final d in snap.docs) {
      final code = (d.data()['partyCode'] ?? '').toString().toLowerCase();
      if (code.isNotEmpty) existing[code] = d.reference;
    }

    final callable = _functions.httpsCallable('createClientUser');

    for (var i = 0; i < table.rows.length; i++) {
      final row = table.rows[i];
      final rowNo = i + 1;
      String? cell(String f) =>
          mapping[f] == null ? null : row[mapping[f]]?.trim();

      final code = cell(PartyImportConfig.partyCode) ?? '';
      final name = cell(PartyImportConfig.name) ?? '';
      if (code.isEmpty || name.isEmpty) {
        results.add(ImportRowResult(
            rowNumber: rowNo,
            status: ImportRowStatus.error,
            message: 'Missing Party ID or Name'));
        continue;
      }

      final data = <String, dynamic>{
        'companyId': companyId,
        'partyCode': code,
        'name': name,
        'ownerName': cell(PartyImportConfig.ownerName),
        'phone': cell(PartyImportConfig.phone),
        'whatsapp': cell(PartyImportConfig.whatsapp),
        'email': cell(PartyImportConfig.email),
        'gstNumber': cell(PartyImportConfig.gstNumber),
        'address': cell(PartyImportConfig.address),
        'city': cell(PartyImportConfig.city),
        'state': cell(PartyImportConfig.state),
        'pincode': cell(PartyImportConfig.pincode),
        'transport': cell(PartyImportConfig.transport),
        'paymentTerms': cell(PartyImportConfig.paymentTerms),
        'creditLimit':
            double.tryParse(cell(PartyImportConfig.creditLimit) ?? '') ?? 0,
        'defaultDiscount':
            double.tryParse(cell(PartyImportConfig.defaultDiscount) ?? '') ?? 0,
        'status': 'active',
      };

      final match = existing[code.toLowerCase()];

      try {
        if (match != null) {
          if (mode == ImportMode.addOnly) {
            results.add(ImportRowResult(
                rowNumber: rowNo,
                status: ImportRowStatus.skipped,
                message: 'Party ID $code already exists'));
            continue;
          }
          await match.update(data);
          results.add(ImportRowResult(
              rowNumber: rowNo,
              status: ImportRowStatus.ok,
              message: 'Updated'));
        } else {
          if (mode == ImportMode.updateOnly) {
            results.add(ImportRowResult(
                rowNumber: rowNo,
                status: ImportRowStatus.skipped,
                message: 'No existing Party ID to update'));
            continue;
          }
          final ref = await _db
              .collection(Collections.parties)
              .add({...data, 'createdAt': FieldValue.serverTimestamp()});
          existing[code.toLowerCase()] = ref;

          final pwd = _passwordFor(cell(PartyImportConfig.password), code);
          try {
            await callable.call<Map<String, dynamic>>({
              'loginCode': code,
              'partyId': ref.id,
              'password': pwd,
              'name': name,
              'companyId': companyId,
              'phone': cell(PartyImportConfig.phone),
            });
            results.add(ImportRowResult(
                rowNumber: rowNo,
                status: ImportRowStatus.ok,
                message: 'Created + login'));
          } catch (e) {
            // Login failed (e.g. duplicate email): roll back the party doc.
            await ref.delete();
            existing.remove(code.toLowerCase());
            results.add(ImportRowResult(
                rowNumber: rowNo,
                status: ImportRowStatus.error,
                message: 'Login not created: $e'));
          }
        }
      } catch (e) {
        results.add(ImportRowResult(
            rowNumber: rowNo, status: ImportRowStatus.error, message: '$e'));
      }
    }
    return results;
  }

  /// Firebase requires >= 6 chars. Use the sheet password when given, else a
  /// per-party default derived from the Party ID.
  String _passwordFor(String? provided, String code) {
    if (provided != null && provided.length >= 6) return provided;
    final base = code.replaceAll(RegExp(r'\s'), '');
    return base.length >= 6 ? base : '$base@2026';
  }
}
