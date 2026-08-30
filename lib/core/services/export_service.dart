import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

final exportServiceProvider =
    Provider<ExportService>((ref) => const ExportService());

/// Exports a simple table ([headers] + string [rows]) to CSV, Excel or PDF and
/// hands the file to the user (save dialog / download / share sheet).
class ExportService {
  const ExportService();

  Future<void> exportCsv({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final csv = const ListToCsvConverter().convert([headers, ...rows]);
    await _save('$fileName.csv', Uint8List.fromList(csv.codeUnits));
  }

  Future<void> exportExcel({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final book = xls.Excel.createExcel();
    final sheet = book[book.getDefaultSheet()!];
    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());
    for (final r in rows) {
      sheet.appendRow(r.map((c) => xls.TextCellValue(c)).toList());
    }
    final bytes = book.encode();
    if (bytes != null) {
      await _save('$fileName.xlsx', Uint8List.fromList(bytes));
    }
  }

  Future<void> exportPdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Text(title,
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green50),
          ),
        ],
      ),
    );
    await Printing.sharePdf(bytes: await doc.save(), filename: '$title.pdf');
  }

  Future<void> _save(String fileName, Uint8List bytes) async {
    // file_picker: on web this triggers a download; on desktop/mobile it opens
    // a save dialog and writes the bytes.
    await FilePicker.platform.saveFile(
      fileName: fileName,
      bytes: bytes,
    );
  }
}
