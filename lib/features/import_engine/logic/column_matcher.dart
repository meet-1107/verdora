import '../domain/import_models.dart';

/// Auto-detects a column mapping by matching spreadsheet headers against each
/// field's label + synonyms. Returns `{fieldKey: header}` for confident matches
/// only; unmatched fields are left out so the admin can map them manually.
class ColumnMatcher {
  const ColumnMatcher();

  Map<String, String> autoMap(
    List<String> headers,
    List<ImportField> fields,
  ) {
    final normalizedHeaders = {
      for (final h in headers) _norm(h): h,
    };
    final result = <String, String>{};

    for (final field in fields) {
      final candidates = <String>{
        _norm(field.label),
        _norm(field.key),
        ...field.synonyms.map(_norm),
      };
      for (final c in candidates) {
        if (c.isEmpty) continue;
        final hit = normalizedHeaders[c];
        if (hit != null) {
          result[field.key] = hit;
          break;
        }
      }
    }
    return result;
  }

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
