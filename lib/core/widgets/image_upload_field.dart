import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../services/image_service.dart';
import 'app_image.dart';

/// A reusable multi-image manager: shows thumbnails, adds via gallery/camera,
/// removes (and deletes from Storage). Emits the current URL list via
/// [onChanged].
class ImageUploadField extends ConsumerStatefulWidget {
  const ImageUploadField({
    super.key,
    required this.initial,
    required this.companyId,
    required this.folder,
    required this.onChanged,
    this.title = 'Images',
  });

  final List<String> initial;
  final String companyId;
  final String folder; // e.g. 'products'
  final ValueChanged<List<String>> onChanged;
  final String title;

  @override
  ConsumerState<ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends ConsumerState<ImageUploadField> {
  late List<String> _urls = [...widget.initial];
  bool _busy = false;

  Future<void> _add(ImageSource source) async {
    setState(() => _busy = true);
    try {
      final service = ref.read(imageServiceProvider);
      final bytes = await service.pick(source: source);
      if (bytes == null) return;
      final url = await service.upload(
        bytes: bytes,
        folder: widget.folder,
        companyId: widget.companyId,
      );
      setState(() => _urls = [..._urls, url]);
      widget.onChanged(_urls);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_uploadErrorMessage(e)),
          duration: const Duration(seconds: 6),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Turns a raw Storage exception into an actionable message. Almost always
  /// this means Cloud Storage isn't enabled for the Firebase project yet.
  String _uploadErrorMessage(Object e) {
    final s = e.toString().toLowerCase();
    final storageIssue = s.contains('firebase_storage') ||
        s.contains('object-not-found') ||
        s.contains('bucket') ||
        s.contains('not found') ||
        s.contains('404') ||
        s.contains('unauthorized') ||
        s.contains('unknown') ||
        s.contains('retry-limit') ||
        s.contains('permission');
    if (storageIssue) {
      return 'Image upload is unavailable because Cloud Storage is not enabled '
          'for this project. You can still save without an image — enable '
          'Storage in the Firebase console to turn on uploads.';
    }
    return 'Upload failed: $e';
  }

  Future<void> _remove(String url) async {
    setState(() => _urls = _urls.where((u) => u != url).toList());
    widget.onChanged(_urls);
    await ref.read(imageServiceProvider).deleteByUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final url in _urls) _thumb(url),
            _addButton(),
          ],
        ),
      ],
    );
  }

  Widget _thumb(String url) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(
            image: appImageProvider(url)!,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(
                width: 88, height: 88, child: Icon(Icons.broken_image)),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            icon: const CircleAvatar(
              radius: 12,
              child: Icon(Icons.close, size: 14),
            ),
            onPressed: () => _remove(url),
          ),
        ),
      ],
    );
  }

  Widget _addButton() {
    return InkWell(
      onTap: _busy ? null : () => _showSourceSheet(),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: _busy
            ? const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : const Icon(Icons.add_a_photo_outlined),
      ),
    );
  }

  void _showSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _add(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _add(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }
}
