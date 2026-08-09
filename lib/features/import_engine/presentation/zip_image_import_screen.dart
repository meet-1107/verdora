import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/import_models.dart';
import '../logic/zip_image_importer.dart';

/// Upload a ZIP of images; each is matched to a product by file name
/// (SKU or product name) and attached.
class ZipImageImportScreen extends ConsumerStatefulWidget {
  const ZipImageImportScreen({super.key});

  @override
  ConsumerState<ZipImageImportScreen> createState() =>
      _ZipImageImportScreenState();
}

class _ZipImageImportScreenState extends ConsumerState<ZipImageImportScreen> {
  bool _busy = false;
  List<ImportRowResult>? _results;

  Future<void> _pickAndRun() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final companyId = ref.read(currentUserProvider).valueOrNull?.companyId ??
          AppConstants.defaultCompanyId;
      final results = await ref
          .read(zipImageImporterProvider)
          .run(companyId: companyId, zipBytes: bytes);
      setState(() => _results = results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    int count(ImportRowStatus s) =>
        results?.where((r) => r.status == s).length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Bulk Image Import')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
              'Upload a .zip of images. Each file is matched to a product by '
              'its file name — either a variant SKU or the product name '
              '(e.g. "20mm_elbow.jpg" → SKU "20mm_elbow" or product '
              '"20mm Elbow"). Matched images are attached to the product.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _pickAndRun,
            icon: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.folder_zip_outlined),
            label: Text(_busy ? 'Importing…' : 'Choose ZIP file'),
          ),
          if (results != null) ...[
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 8, children: [
              _chip(
                  context, 'Attached', count(ImportRowStatus.ok), Colors.green),
              _chip(context, 'Unmatched', count(ImportRowStatus.skipped),
                  Colors.orange),
              _chip(
                  context, 'Errors', count(ImportRowStatus.error), Colors.red),
            ]),
            const Divider(height: 28),
            for (final r in results.take(200))
              ListTile(
                dense: true,
                leading: Icon(
                  r.status == ImportRowStatus.ok
                      ? Icons.check_circle_outline
                      : r.status == ImportRowStatus.skipped
                          ? Icons.info_outline
                          : Icons.error_outline,
                  color: r.status == ImportRowStatus.ok
                      ? Colors.green
                      : r.status == ImportRowStatus.skipped
                          ? Colors.orange
                          : Theme.of(context).colorScheme.error,
                ),
                title: Text(r.message ?? ''),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, int value, Color color) {
    return Chip(
      backgroundColor: color.withValues(alpha: 0.12),
      label: Text('$label: $value',
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
