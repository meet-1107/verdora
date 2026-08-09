import 'dart:convert';
import 'dart:typed_data';

import 'package:b2b_saas/features/import_engine/data/file_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _csv(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('FileParser (CSV)', () {
    test('reads headers and rows', () {
      final t = const FileParser().parse(
          bytes: _csv('Name,Price\nElbow,10\nTee,20\n'), fileName: 'x.csv');
      expect(t.headers, ['Name', 'Price']);
      expect(t.rows.length, 2);
      expect(t.rows.first['Name'], 'Elbow');
      expect(t.rows[1]['Price'], '20');
    });

    test('handles CRLF line endings and trims cells', () {
      final t = const FileParser()
          .parse(bytes: _csv('A,B\r\n x , y \r\n'), fileName: 'x.csv');
      expect(t.rows.first['A'], 'x');
      expect(t.rows.first['B'], 'y');
    });

    test('pads short rows with empty strings', () {
      final t = const FileParser()
          .parse(bytes: _csv('A,B,C\n1,2\n'), fileName: 'x.csv');
      expect(t.rows.first['C'], '');
    });

    test('empty file yields no rows', () {
      final t = const FileParser().parse(bytes: _csv(''), fileName: 'x.csv');
      expect(t.isEmpty, isTrue);
    });
  });
}
