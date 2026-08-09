import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/import_models.dart';
import 'product_import_config.dart';

final productImportExecutorProvider = Provider<ImportExecutor>((ref) {
  return ProductImportExecutor(ref.watch(firestoreProvider));
});

/// Imports a mapped product spreadsheet into Firestore. One spreadsheet row =
/// one variant of a product. Categories/subcategories/products are resolved by
/// name and created on demand. Variants are matched by SKU.
///
/// Errors are per-row: a bad row is skipped and reported, never aborting the
/// whole import.
class ProductImportExecutor implements ImportExecutor {
  ProductImportExecutor(this._db);

  final FirebaseFirestore _db;

  @override
  Future<List<ImportRowResult>> run({
    required String companyId,
    required ParsedTable table,
    required Map<String, String> mapping,
    required ImportMode mode,
  }) async {
    final results = <ImportRowResult>[];

    // Preload existing data so lookups are in-memory.
    final categories = await _loadNameIndex(Collections.categories, companyId);
    final products = <String, String>{}; // '$catId|$name' -> productId
    final variantsBySku = <String, DocumentReference>{};

    final prodSnap = await _db
        .collection(Collections.products)
        .where('companyId', isEqualTo: companyId)
        .get();
    for (final d in prodSnap.docs) {
      final data = d.data();
      products['${data['categoryId']}|${_lc(data['name'])}'] = d.id;
    }
    final varSnap = await _db
        .collection(Collections.variants)
        .where('companyId', isEqualTo: companyId)
        .get();
    for (final d in varSnap.docs) {
      final sku = d.data()['sku'];
      if (sku is String && sku.isNotEmpty) variantsBySku[sku] = d.reference;
    }

    for (var i = 0; i < table.rows.length; i++) {
      final row = table.rows[i];
      final rowNo = i + 1;
      String? cell(String field) =>
          mapping[field] == null ? null : row[mapping[field]]?.trim();

      final name = cell(ProductImportConfig.productName) ?? '';
      if (name.isEmpty) {
        results.add(ImportRowResult(
            rowNumber: rowNo,
            status: ImportRowStatus.error,
            message: 'Missing product name'));
        continue;
      }

      // Rate validation.
      final rateStr = cell(ProductImportConfig.rate);
      double rate = 0;
      if (rateStr != null && rateStr.isNotEmpty) {
        final parsed = double.tryParse(rateStr.replaceAll(',', ''));
        if (parsed == null) {
          results.add(ImportRowResult(
              rowNumber: rowNo,
              status: ImportRowStatus.error,
              message: 'Invalid rate "$rateStr"'));
          continue;
        }
        rate = parsed;
      }

      try {
        // Resolve / create category.
        final catName = cell(ProductImportConfig.category);
        String categoryId = '';
        if (catName != null && catName.isNotEmpty) {
          categoryId = categories[_lc(catName)] ??
              await _createCategory(companyId, catName, categories);
        } else {
          categoryId = categories['uncategorised'] ??
              await _createCategory(companyId, 'Uncategorised', categories);
        }

        // Resolve / create product.
        final pKey = '$categoryId|${_lc(name)}';
        final productId =
            products[pKey] ?? await _createProduct(companyId, categoryId, name);
        products[pKey] = productId;

        // Build the variant.
        final variantValue = cell(ProductImportConfig.variant);
        final attributes = <String, String>{};
        if (variantValue != null && variantValue.isNotEmpty) {
          attributes['Size'] = variantValue;
        }
        final sku = cell(ProductImportConfig.sku);
        final opening =
            int.tryParse(cell(ProductImportConfig.openingStock) ?? '') ?? 0;
        final data = {
          'companyId': companyId,
          'productId': productId,
          'attributes': attributes,
          'rate': rate,
          'pack': int.tryParse(cell(ProductImportConfig.pack) ?? '') ?? 1,
          'boxPack': int.tryParse(cell(ProductImportConfig.boxPack) ?? '') ?? 1,
          'sku': (sku != null && sku.isNotEmpty) ? sku : null,
          'barcode': cell(ProductImportConfig.barcode),
          'minStock':
              int.tryParse(cell(ProductImportConfig.minStock) ?? '') ?? 0,
          'status': 'active',
        };

        final existing =
            (sku != null && sku.isNotEmpty) ? variantsBySku[sku] : null;

        if (existing != null) {
          if (mode == ImportMode.addOnly) {
            results.add(ImportRowResult(
                rowNumber: rowNo,
                status: ImportRowStatus.skipped,
                message: 'SKU $sku already exists'));
            continue;
          }
          await existing.update(data); // keeps currentStock as-is
          results.add(ImportRowResult(
              rowNumber: rowNo,
              status: ImportRowStatus.ok,
              message: 'Updated'));
        } else {
          if (mode == ImportMode.updateOnly) {
            results.add(ImportRowResult(
                rowNumber: rowNo,
                status: ImportRowStatus.skipped,
                message: 'No existing SKU to update'));
            continue;
          }
          final ref = await _db
              .collection(Collections.variants)
              .add({...data, 'currentStock': opening});
          if (sku != null && sku.isNotEmpty) variantsBySku[sku] = ref;
          if (opening > 0) {
            await _db.collection(Collections.inventoryTransactions).add({
              'companyId': companyId,
              'variantId': ref.id,
              'type': 'opening',
              'quantity': opening,
              'refType': 'import',
              'note': 'Opening stock (import)',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
          results.add(ImportRowResult(
              rowNumber: rowNo,
              status: ImportRowStatus.ok,
              message: 'Created'));
        }
      } catch (e) {
        results.add(ImportRowResult(
            rowNumber: rowNo, status: ImportRowStatus.error, message: '$e'));
      }
    }
    return results;
  }

  Future<Map<String, String>> _loadNameIndex(
      String collection, String companyId) async {
    final snap = await _db
        .collection(collection)
        .where('companyId', isEqualTo: companyId)
        .get();
    return {for (final d in snap.docs) _lc(d.data()['name']): d.id};
  }

  Future<String> _createCategory(
      String companyId, String name, Map<String, String> cache) async {
    final ref = await _db.collection(Collections.categories).add({
      'companyId': companyId,
      'name': name,
      'description': '',
      'sortOrder': 0,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    cache[_lc(name)] = ref.id;
    return ref.id;
  }

  Future<String> _createProduct(
      String companyId, String categoryId, String name) async {
    final ref = await _db.collection(Collections.products).add({
      'companyId': companyId,
      'categoryId': categoryId,
      'name': name,
      'description': '',
      'imageUrls': <String>[],
      'attributes': <Map<String, dynamic>>[],
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  String _lc(dynamic v) => (v?.toString() ?? '').toLowerCase().trim();
}
