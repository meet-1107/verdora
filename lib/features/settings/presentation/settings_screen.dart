import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/image_service.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/state_views.dart';
import '../../activity/data/activity_repository.dart';
import '../../activity/presentation/activity_logs_screen.dart';
import '../../auth/data/auth_repository.dart';
import '../backup/presentation/backup_screen.dart';
import '../data/settings_repository.dart';
import '../domain/company_settings.dart';
import 'settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(companySettingsProvider);
    return Scaffold(
      appBar: AppBar(
          leading: const AdminMenuButton(), title: const Text('Settings')),
      body: settings.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(companySettingsProvider)),
        data: (s) => _SettingsForm(initial: s),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.initial});
  final CompanySettings initial;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final Map<String, TextEditingController> _c;
  bool _saving = false;
  bool _uploadingLogo = false;
  late String _logoUrl;

  @override
  void initState() {
    super.initState();
    _logoUrl = widget.initial.logoUrl;
    final s = widget.initial;
    _c = {
      'name': TextEditingController(text: s.name),
      'address': TextEditingController(text: s.address),
      'phone': TextEditingController(text: s.phone),
      'email': TextEditingController(text: s.email),
      'gstNumber': TextEditingController(text: s.gstNumber),
      'invoicePrefix': TextEditingController(text: s.invoicePrefix),
      'currency': TextEditingController(text: s.currency),
      'supportNumber': TextEditingController(text: s.supportNumber),
      'terms': TextEditingController(text: s.terms),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final s = CompanySettings(
        companyId: widget.initial.companyId,
        name: _c['name']!.text.trim(),
        address: _c['address']!.text.trim(),
        phone: _c['phone']!.text.trim(),
        email: _c['email']!.text.trim(),
        gstNumber: _c['gstNumber']!.text.trim(),
        invoicePrefix: _c['invoicePrefix']!.text.trim().isEmpty
            ? 'INV'
            : _c['invoicePrefix']!.text.trim(),
        currency: _c['currency']!.text.trim().isEmpty
            ? '₹'
            : _c['currency']!.text.trim(),
        supportNumber: _c['supportNumber']!.text.trim(),
        terms: _c['terms']!.text.trim(),
        logoUrl: _logoUrl,
      );
      await ref.read(settingsRepositoryProvider).save(s);
      await ref.read(activityLoggerProvider).record('settings.updated');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickLogo() async {
    setState(() => _uploadingLogo = true);
    try {
      final bytes = await ref.read(imageServiceProvider).pick();
      if (bytes == null) return;
      final url = await ref.read(imageServiceProvider).upload(
            bytes: bytes,
            folder: 'logos',
            companyId: widget.initial.companyId,
          );
      // Persist immediately so it shows on login / client home right away.
      await ref
          .read(settingsRepositoryProvider)
          .save(widget.initial.copyWith(logoUrl: url));
      if (mounted) {
        setState(() => _logoUrl = url);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Logo updated.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Logo upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    await ref
        .read(settingsRepositoryProvider)
        .save(widget.initial.copyWith(logoUrl: ''));
    if (mounted) setState(() => _logoUrl = '');
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Company profile',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _logoSection(context),
              const SizedBox(height: 12),
              _field('name', 'Company name'),
              _field('address', 'Address', maxLines: 2),
              Row(children: [
                Expanded(child: _field('phone', 'Phone')),
                const SizedBox(width: 12),
                Expanded(child: _field('email', 'Email')),
              ]),
              _field('gstNumber', 'GST number'),
              Row(children: [
                Expanded(child: _field('invoicePrefix', 'Invoice prefix')),
                const SizedBox(width: 12),
                Expanded(child: _field('currency', 'Currency symbol')),
              ]),
              _field('supportNumber', 'Support number'),
              _field('terms', 'Invoice terms', maxLines: 3),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Text('Save settings'),
              ),
              const Divider(height: 40),
              Text('Appearance',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {themeMode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).set(s.first),
              ),
              const Divider(height: 40),
              Text('Data', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Monthly backup (CSV)'),
                subtitle: const Text(
                    'Export a month\'s orders, party totals and stock'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const BackupScreen())),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: const Text('Activity logs'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ActivityLogsScreen())),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logoSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = appImageProvider(_logoUrl);
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            image: provider == null
                ? null
                : DecorationImage(image: provider, fit: BoxFit.cover),
          ),
          alignment: Alignment.center,
          child: provider == null
              ? Icon(Icons.image_outlined, color: scheme.onSurfaceVariant)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Company logo',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text('Shown on the login and client home screens.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _uploadingLogo ? null : _pickLogo,
                    icon: _uploadingLogo
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_outlined, size: 18),
                    label: Text(_logoUrl.isEmpty ? 'Upload' : 'Change'),
                  ),
                  if (_logoUrl.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    TextButton(
                        onPressed: _uploadingLogo ? null : _removeLogo,
                        child: const Text('Remove')),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(String key, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _c[key],
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
