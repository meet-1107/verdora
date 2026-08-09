import 'package:b2b_saas/features/import_engine/logic/column_matcher.dart';
import 'package:b2b_saas/features/import_engine/logic/product_import_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ColumnMatcher', () {
    test('maps synonym headers to app fields', () {
      final headers = ['Item Name', 'Diameter', 'Dealer Price', 'Box Qty'];
      final map =
          const ColumnMatcher().autoMap(headers, ProductImportConfig.fields);
      expect(map[ProductImportConfig.productName], 'Item Name');
      expect(map[ProductImportConfig.variant], 'Diameter');
      expect(map[ProductImportConfig.rate], 'Dealer Price');
      expect(map[ProductImportConfig.boxPack], 'Box Qty');
    });

    test('is case/space/punctuation insensitive', () {
      final headers = ['product  name', 'R A T E'];
      final map =
          const ColumnMatcher().autoMap(headers, ProductImportConfig.fields);
      expect(map[ProductImportConfig.productName], 'product  name');
      expect(map[ProductImportConfig.rate], 'R A T E');
    });

    test('leaves unknown headers unmapped', () {
      final map = const ColumnMatcher()
          .autoMap(['Totally Unknown'], ProductImportConfig.fields);
      expect(map.containsKey(ProductImportConfig.productName), isFalse);
    });
  });
}
