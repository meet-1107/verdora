import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/file_parser.dart';
import '../data/import_template_repository.dart';
import '../domain/import_models.dart';
import '../logic/column_matcher.dart';

/// Generic, target-agnostic CSV/Excel import flow: upload → map columns →
/// options → import. Configure it with [fields] and an [executorProvider]; it
/// works for products, parties, or any future target.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({
    super.key,
    required this.title,
    required this.target,
    required this.fields,
    required this.executorProvider,
  });

  final String title;
  final String target; // 'products' | 'parties' ...
  final List<ImportField> fields;
  final ProviderListenable<ImportExecutor> executorProvider;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  int _step = 0;
  ParsedTable? _table;
  String _fileName = '';
  Map<String, String> _mapping = {};
  ImportMode _mode = ImportMode.addAndUpdate;
  List<ImportRowResult>? _results;
  bool _busy = false;

  List<ImportField> get _requiredFields =>
      widget.fields.where((f) => f.required).toList();

  bool get _requiredMapped =>
      _requiredFields.every((f) => _mapping.containsKey(f.key));

  Future<void> _pickFile() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx', 'xls'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      final table = const FileParser().parse(bytes: bytes, fileName: file.name);
      if (table.isEmpty) {
        _snack('No rows found in the file.');
        return;
      }
      final mapping =
          const ColumnMatcher().autoMap(table.headers, widget.fields);
      setState(() {
        _table = table;
        _fileName = file.name;
        _mapping = mapping;
        _results = null;
        _step = 1;
      });
    } catch (e) {
      _snack('Could not read file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runImport() async {
    final table = _table;
    if (table == null) return;
    setState(() => _busy = true);
    try {
      final companyId = ref.read(currentUserProvider).valueOrNull?.companyId ??
          AppConstants.defaultCompanyId;
      final results = await ref.read(widget.executorProvider).run(
            companyId: companyId,
            table: table,
            mapping: _mapping,
            mode: _mode,
          );
      setState(() {
        _results = results;
        _step = 3;
      });
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Stepper(
          currentStep: _step,
          controlsBuilder: (context, details) => const SizedBox.shrink(),
          onStepTapped: (s) {
            if (s < _step) setState(() => _step = s);
          },
          steps: [
            Step(
              title: const Text('Upload file'),
              isActive: _step >= 0,
              content: _UploadStep(
                  fileName: _fileName, busy: _busy, onPick: _pickFile),
            ),
            Step(
              title: const Text('Map columns'),
              isActive: _step >= 1,
              content: _table == null
                  ? const SizedBox()
                  : _MappingStep(
                      table: _table!,
                      fields: widget.fields,
                      target: widget.target,
                      mapping: _mapping,
                      requiredMapped: _requiredMapped,
                      onChanged: (m) => setState(() => _mapping = m),
                      onNext: () => setState(() => _step = 2),
                    ),
            ),
            Step(
              title: const Text('Options & import'),
              isActive: _step >= 2,
              content: _table == null
                  ? const SizedBox()
                  : _OptionsStep(
                      table: _table!,
                      mapping: _mapping,
                      requiredFields: _requiredFields,
                      mode: _mode,
                      busy: _busy,
                      onModeChanged: (m) => setState(() => _mode = m),
                      onImport: _runImport,
                    ),
            ),
            Step(
              title: const Text('Results'),
              isActive: _step >= 3,
              content: _ResultsStep(results: _results ?? const []),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadStep extends StatelessWidget {
  const _UploadStep(
      {required this.fileName, required this.busy, required this.onPick});
  final String fileName;
  final bool busy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
            'Upload a CSV or Excel (.xlsx/.xls) file. Headers can be in any '
            'order and use any names — the next step maps them.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : onPick,
          icon: const Icon(Icons.upload_file),
          label: Text(fileName.isEmpty ? 'Choose file' : 'Choose another file'),
        ),
        if (fileName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Selected: $fileName',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _MappingStep extends ConsumerWidget {
  const _MappingStep({
    required this.table,
    required this.fields,
    required this.target,
    required this.mapping,
    required this.requiredMapped,
    required this.onChanged,
    required this.onNext,
  });

  final ParsedTable table;
  final List<ImportField> fields;
  final String target;
  final Map<String, String> mapping;
  final bool requiredMapped;
  final ValueChanged<Map<String, String>> onChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates =
        ref.watch(importTemplatesProvider(target)).valueOrNull ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${table.rows.length} rows · '
                  '${table.headers.length} columns detected'),
            ),
            if (templates.isNotEmpty)
              PopupMenuButton<ImportTemplate>(
                icon: const Icon(Icons.bookmark_border),
                tooltip: 'Apply saved mapping',
                onSelected: (t) {
                  final applied = {
                    for (final e in t.mapping.entries)
                      if (table.headers.contains(e.value)) e.key: e.value,
                  };
                  onChanged(applied);
                },
                itemBuilder: (_) => [
                  for (final t in templates)
                    PopupMenuItem(value: t, child: Text(t.name)),
                ],
              ),
            IconButton(
              tooltip: 'Save this mapping',
              icon: const Icon(Icons.save_outlined),
              onPressed: () => _saveTemplate(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Flexible(child: Text(field.label)),
                      if (field.required)
                        Text(' *',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String?>(
                    initialValue: mapping[field.key],
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('— Ignore —')),
                      for (final h in table.headers)
                        DropdownMenuItem<String?>(value: h, child: Text(h)),
                    ],
                    onChanged: (h) {
                      final next = {...mapping};
                      if (h == null) {
                        next.remove(field.key);
                      } else {
                        next[field.key] = h;
                      }
                      onChanged(next);
                    },
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: requiredMapped ? onNext : null,
            child: const Text('Next'),
          ),
        ),
        if (!requiredMapped)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Map all required (*) fields to continue.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ),
      ],
    );
  }

  Future<void> _saveTemplate(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save mapping template'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Template name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final companyId = ref.read(currentUserProvider).valueOrNull?.companyId ??
        AppConstants.defaultCompanyId;
    await ref.read(importTemplateRepositoryProvider).save(ImportTemplate(
          id: '',
          companyId: companyId,
          name: name,
          target: target,
          mapping: mapping,
        ));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved "$name".')));
    }
  }
}

class _OptionsStep extends StatelessWidget {
  const _OptionsStep({
    required this.table,
    required this.mapping,
    required this.requiredFields,
    required this.mode,
    required this.busy,
    required this.onModeChanged,
    required this.onImport,
  });

  final ParsedTable table;
  final Map<String, String> mapping;
  final List<ImportField> requiredFields;
  final ImportMode mode;
  final bool busy;
  final ValueChanged<ImportMode> onModeChanged;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    // Count rows missing any required field.
    var missing = 0;
    for (final r in table.rows) {
      final ok = requiredFields.every((f) {
        final h = mapping[f.key];
        return h != null && (r[h] ?? '').trim().isNotEmpty;
      });
      if (!ok) missing++;
    }
    final ready = table.rows.length - missing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Duplicate handling',
            style: Theme.of(context).textTheme.titleSmall),
        RadioGroup<ImportMode>(
          groupValue: mode,
          onChanged: (v) => onModeChanged(v!),
          child: const Column(
            children: [
              RadioListTile<ImportMode>(
                value: ImportMode.addAndUpdate,
                title: Text('Add new and update existing'),
                dense: true,
              ),
              RadioListTile<ImportMode>(
                value: ImportMode.addOnly,
                title: Text('Add new only (skip existing)'),
                dense: true,
              ),
              RadioListTile<ImportMode>(
                value: ImportMode.updateOnly,
                title: Text('Update existing only'),
                dense: true,
              ),
            ],
          ),
        ),
        const Divider(height: 24),
        Wrap(spacing: 12, runSpacing: 8, children: [
          _stat(context, 'Rows', table.rows.length, Colors.blue),
          _stat(context, 'Ready', ready < 0 ? 0 : ready, Colors.green),
          _stat(context, 'Missing required', missing, Colors.orange),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : onImport,
          icon: busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow),
          label: Text(busy ? 'Importing…' : 'Import ${table.rows.length} rows'),
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value',
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        const SizedBox(width: 6),
        Text(label),
      ]),
    );
  }
}

class _ResultsStep extends StatelessWidget {
  const _ResultsStep({required this.results});
  final List<ImportRowResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const Text('No results yet.');
    int count(ImportRowStatus s) => results.where((r) => r.status == s).length;
    final problems = results
        .where((r) =>
            r.status == ImportRowStatus.error ||
            r.status == ImportRowStatus.skipped)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 12, runSpacing: 8, children: [
          _chip(context, 'Imported', count(ImportRowStatus.ok), Colors.green),
          _chip(context, 'Skipped', count(ImportRowStatus.skipped),
              Colors.orange),
          _chip(context, 'Errors', count(ImportRowStatus.error), Colors.red),
        ]),
        const SizedBox(height: 12),
        if (problems.isEmpty)
          const Text('All rows imported successfully. 🎉')
        else ...[
          Text('Rows needing attention',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final r in problems.take(100))
            ListTile(
              dense: true,
              leading: Icon(
                r.status == ImportRowStatus.error
                    ? Icons.error_outline
                    : Icons.info_outline,
                color: r.status == ImportRowStatus.error
                    ? Theme.of(context).colorScheme.error
                    : Colors.orange,
              ),
              title: Text('Row ${r.rowNumber}: ${r.message ?? ''}'),
            ),
          if (problems.length > 100)
            Text('…and ${problems.length - 100} more',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
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
