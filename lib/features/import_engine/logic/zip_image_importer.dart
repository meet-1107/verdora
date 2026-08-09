import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/collections.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/services/image_service.dart';
import '../domain/import_models.dart';

final zipImageImporterProvider = Provider<ZipImageImporter>((ref) {
  return ZipImageImporter(
    ref.watch(firestoreProvider),
    ref.watch(imageServiceProvider),
  );
});

/// Extracts images from a ZIP and attaches each to a product by matching the
/// file name (without extension) against a variant SKU or a product name.
/// e.g. `20mm_elbow.jpg` -> product "20mm Elbow" or variant SKU "20mm_elbow".
class ZipImageImporter {
  ZipImageImporter(this._db, this._images);

  final FirebaseFirestore _db;
  final ImageService _images;

  static const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

  Future<List<ImportRowResult>> run({
    required String companyId,
    required Uint8List zipBytes,
  }) async {
    final results = <ImportRowResult>[];

    // Build lookup: normalised key -> productId (from SKUs and product names).
    final skuToProduct = <String, String>{};
    final nameToProduct = <String, String>{};

    final prodSnap = await _db
        .collection(Collections.products)
        .where('companyId', isEqualTo: companyId)
        .get();
    for (final d in prodSnap.docs) {
      nameToProduct[_norm(d.data()['name'])] = d.id;
    }
    final varSnap = await _db
        .collection(Collections.variants)
        .where('companyId', isEqualTo: companyId)
        .get();
    for (final d in varSnap.docs) {
      final sku = d.data()['sku'];
      final productId = d.data()['productId'];
      if (sku is String && sku.isNotEmpty && productId is String) {
        skuToProduct[_norm(sku)] = productId;
      }
    }

    final archive = ZipDecoder().decodeBytes(zipBytes);
    var index = 0;
    for (final file in archive) {
      if (!file.isFile) continue;
      final baseName = file.name.split('/').last;
      final dot = baseName.lastIndexOf('.');
      if (dot < 0) continue;
      final ext = baseName.substring(dot + 1).toLowerCase();
      if (!_imageExts.contains(ext)) continue;

      index++;
      final key = _norm(baseName.substring(0, dot));
      final productId = skuToProduct[key] ?? nameToProduct[key];

      if (productId == null) {
        results.add(ImportRowResult(
            rowNumber: index,
            status: ImportRowStatus.skipped,
            message: 'No product/SKU matches "$baseName"'));
        continue;
      }

      try {
        final bytes = Uint8List.fromList(file.content as List<int>);
        final url = await _images.upload(
          bytes: bytes,
          folder: 'products',
          companyId: companyId,
        );
        await _db.collection(Collections.products).doc(productId).update({
          'imageUrls': FieldValue.arrayUnion([url]),
        });
        results.add(ImportRowResult(
            rowNumber: index,
            status: ImportRowStatus.ok,
            message: 'Attached "$baseName"'));
      } catch (e) {
        results.add(ImportRowResult(
            rowNumber: index, status: ImportRowStatus.error, message: '$e'));
      }
    }

    if (results.isEmpty) {
      results.add(ImportRowResult(
          rowNumber: 0,
          status: ImportRowStatus.error,
          message: 'No image files found in the ZIP'));
    }
    return results;
  }

  String _norm(dynamic s) =>
      (s?.toString() ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
