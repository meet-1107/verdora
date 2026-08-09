import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../domain/import_models.dart';

/// Parses CSV / XLSX / XLS bytes into a [ParsedTable] with a **flexible**
/// header row. The first non-empty row is treated as headers; every subsequent
/// row is keyed by those headers. Missing trailing cells become empty strings.
class FileParser {
  const FileParser();

  ParsedTable parse({required Uint8List bytes, required String fileName}) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.csv')) return _parseCsv(bytes);
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return _parseExcel(bytes);
    }
    // Fallback: try CSV (many exports are CSV with an odd extension).
    return _parseCsv(bytes);
  }

  ParsedTable _parseCsv(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    // Strip a leading BOM (U+FEFF) if present, and normalise line endings.
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(text);
    return _fromRows(rows);
  }

  ParsedTable _parseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      return const ParsedTable(headers: [], rows: []);
    }
    final sheet = excel.tables.values.first;
    final rows =
        sheet.rows.map((r) => r.map((cell) => cell?.value).toList()).toList();
    return _fromRows(rows);
  }

  ParsedTable _fromRows(List<List<dynamic>> raw) {
    // Drop fully-empty leading rows, then take the first as headers.
    final nonEmpty =
        raw.where((r) => r.any((c) => _cell(c).isNotEmpty)).toList();
    if (nonEmpty.isEmpty) return const ParsedTable(headers: [], rows: []);

    final headers = nonEmpty.first.map(_cell).toList();
    // De-duplicate blank headers so mapping keys stay usable.
    for (var i = 0; i < headers.length; i++) {
      if (headers[i].isEmpty) headers[i] = 'Column ${i + 1}';
    }

    final rows = <Map<String, String>>[];
    for (final r in nonEmpty.skip(1)) {
      final map = <String, String>{};
      for (var i = 0; i < headers.length; i++) {
        map[headers[i]] = i < r.length ? _cell(r[i]) : '';
      }
      rows.add(map);
    }
    return ParsedTable(headers: headers, rows: rows);
  }

  String _cell(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    // excel v4 wraps cells in CellValue subtypes (TextCellValue, IntCellValue…)
    // which expose the underlying literal via `.value`. Fall back to toString.
    try {
      final inner = (value as dynamic).value;
      if (inner != null) return inner.toString().trim();
    } catch (_) {}
    return value.toString().trim();
  }
}
