/// A parsed spreadsheet: ordered [headers] and [rows] (each row is a map from
/// header -> cell string). Produced by the file parser for CSV/XLSX/XLS.
class ParsedTable {
  const ParsedTable({required this.headers, required this.rows});
  final List<String> headers;
  final List<Map<String, String>> rows;

  bool get isEmpty => rows.isEmpty;
}

/// An application field that a spreadsheet column can be mapped onto.
class ImportField {
  const ImportField({
    required this.key,
    required this.label,
    this.required = false,
    this.synonyms = const [],
    this.hint,
  });

  final String key;
  final String label;
  final bool required;

  /// Alternate header names auto-detection should recognise (lower-cased).
  final List<String> synonyms;
  final String? hint;
}

/// The result of validating/importing a single row.
enum ImportRowStatus { ok, warning, error, skipped }

class ImportRowResult {
  ImportRowResult({
    required this.rowNumber,
    required this.status,
    this.message,
  });

  final int rowNumber; // 1-based, matches spreadsheet line (excluding header)
  final ImportRowStatus status;
  final String? message;
}

/// How to treat rows that already exist (matched by SKU for products).
enum ImportMode { addOnly, addAndUpdate, updateOnly }

/// Strategy that writes a mapped table into Firestore for a given target
/// (products, parties…). Implementations report a per-row result and must never
/// abort the whole import because of a single bad row.
abstract interface class ImportExecutor {
  Future<List<ImportRowResult>> run({
    required String companyId,
    required ParsedTable table,
    required Map<String, String> mapping,
    required ImportMode mode,
  });
}

/// A reusable column-mapping template (`import_templates/{id}`), e.g.
/// "PVC Factory Format". Stores appFieldKey -> spreadsheet header.
class ImportTemplate {
  const ImportTemplate({
    required this.id,
    required this.companyId,
    required this.name,
    required this.target,
    required this.mapping,
  });

  final String id;
  final String companyId;
  final String name;
  final String target; // e.g. 'products' | 'parties'
  final Map<String, String> mapping;

  factory ImportTemplate.fromMap(String id, Map<String, dynamic> map) {
    return ImportTemplate(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      name: map['name'] as String? ?? '',
      target: map['target'] as String? ?? 'products',
      mapping: (map['mapping'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          const {},
    );
  }

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'name': name,
        'target': target,
        'mapping': mapping,
      };
}
