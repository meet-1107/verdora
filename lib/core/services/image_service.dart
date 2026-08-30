import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../providers/firebase_providers.dart';

final imageServiceProvider = Provider<ImageService>((ref) {
  return ImageService(ref.watch(firebaseStorageProvider));
});

/// Picks, compresses and uploads images to Firebase Storage (available on the
/// Blaze plan). The display side ([appImageProvider]) still understands legacy
/// inline `data:` images, so anything uploaded before Storage was enabled keeps
/// rendering.
class ImageService {
  ImageService(this._storage);

  final FirebaseStorage _storage;
  final _picker = ImagePicker();
  final _uuid = const Uuid();

  Future<Uint8List?> pick({ImageSource source = ImageSource.gallery}) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return null;
    return _compress(await picked.readAsBytes());
  }

  /// Compresses to a reasonable catalog size (keeps uploads small & fast). The
  /// native codec is mobile-only, so web uploads the original bytes.
  Future<Uint8List> _compress(Uint8List bytes) async {
    if (kIsWeb) return bytes;
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        quality: 80,
        minWidth: 1400,
        minHeight: 1400,
      );
    } catch (_) {
      return bytes; // codec unavailable — upload the original
    }
  }

  /// Uploads under e.g. `products/{companyId}/{uuid}.jpg` and returns the public
  /// download URL.
  Future<String> upload({
    required Uint8List bytes,
    required String folder,
    required String companyId,
  }) async {
    final ref = _storage.ref('$folder/$companyId/${_uuid.v4()}.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> deleteByUrl(String url) async {
    if (url.startsWith('data:')) return; // legacy inline image — nothing to delete
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // Already gone / not a Storage URL — ignore.
    }
  }
}
