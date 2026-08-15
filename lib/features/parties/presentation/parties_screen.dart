import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_lazy_list.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../client/application/cart_provider.dart';
import '../../client/presentation/client_categories_screen.dart';
import '../../discounts/presentation/discount_structure_view.dart';
import '../../import_engine/logic/party_import_config.dart';
import '../../import_engine/logic/party_import_executor.dart';
import '../../import_engine/presentation/import_screen.dart';
import '../data/party_repository.dart';
import '../domain/party.dart';
import 'party_providers.dart';

class PartiesScreen extends ConsumerStatefulWidget {
  const PartiesScreen({super.key});

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parties = ref.watch(partiesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Parties'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ImportScreen(
                title: 'Import Parties',
                target: 'parties',
                fields: PartyImportConfig.fields,
                executorProvider: partyImportExecutorProvider,
              ),
            )),
            icon: const Icon(Icons.upload_file),
            label: const Text('Import'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add Party'),
      ),
      body: parties.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(partiesProvider)),
        data: (items) {
          if (items.isEmpty) {
            return EmptyView(
              message: 'No parties yet.\nAdd your first customer.',
              icon: Icons.groups_outlined,
              action: FilledButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add Party'),
              ),
            );
          }
          var sorted = [...items]
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          final q = _query.trim().toLowerCase();
          if (q.isNotEmpty) {
            sorted = sorted
                .where((p) =>
                    p.name.toLowerCase().contains(q) ||
                    p.partyCode.toLowerCase().contains(q) ||
                    (p.phone ?? '').toLowerCase().contains(q))
                .toList();
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: AppSearchBar(
                  controller: _search,
                  hint: 'Search dealer, ID or phone…',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: sorted.isEmpty
                    ? EmptyView(
                        message: 'No dealers match “${_query.trim()}”.',
                        icon: Icons.search_off,
                      )
                    : AppLazyListView<Party>(
                        items: sorted,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemBuilder: (context, p, i) => _PartyCard(
                          party: p,
                          onOpen: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => _PartyDetailScreen(
                                      partyId: p.id, initial: p))),
                          onAction: (a) => _onAction(context, ref, a, p),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String action, Party p) async {
    final repo = ref.read(partyRepositoryProvider);
    switch (action) {
      case 'create_order':
        // Admin builds an order on behalf of this dealer using the client
        // catalog. A fresh cart is used, scoped to the selected party.
        ref.read(actingPartyProvider.notifier).state = p;
        ref.read(cartProvider.notifier).clear();
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ClientCategoriesScreen()));
      case 'edit':
        _openForm(context, existing: p);
      case 'login':
        await provisionDealerLogin(context, ref, p);
      case 'deactivate':
        await repo.setStatus(p.id, 'inactive');
      case 'activate':
        await repo.setStatus(p.id, 'active');
      case 'delete':
        await _confirmDelete(context, ref, p);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Party p) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete party?'),
        content: Text(
            'Are you sure you want to delete "${p.name}" (${p.partyCode})?\n\n'
            'This permanently removes the party AND revokes their client login — '
            'they will lose all access to the app. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete & revoke access'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(partyRepositoryProvider).deleteWithAccess(p.id);
      messenger.showSnackBar(SnackBar(
          content: Text('Deleted "${p.name}" and revoked access.')));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Could not delete party: $e')));
    }
  }

  void _openForm(BuildContext context, {Party? existing}) {
    showDialog(
      context: context,
      builder: (_) => _PartyForm(existing: existing),
    );
  }
}

/// Prompts for a password and creates OR resets the dealer's login via the
/// Cloud Function. Prefills the stored password (if any). Shared by the list
/// menu and the detail screen.
Future<void> provisionDealerLogin(
    BuildContext context, WidgetRef ref, Party p) async {
  final controller = TextEditingController(text: p.loginPassword ?? '');
  final messenger = ScaffoldMessenger.of(context);
  final password = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Provision / reset login'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set the login password for "${p.name}" (ID: ${p.partyCode}). '
              'Creates the login if it doesn\'t exist yet, otherwise resets it.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Password (min 6 characters)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Provision'),
        ),
      ],
    ),
  );
  if (password == null || password.isEmpty) return;
  if (password.length < 6) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Password must be at least 6 characters.')));
    return;
  }
  messenger.showSnackBar(const SnackBar(content: Text('Provisioning login…')));
  try {
    await ref
        .read(partyRepositoryProvider)
        .provisionLogin(party: p, password: password);
    messenger.showSnackBar(SnackBar(
        content: Text('Login ready — "${p.name}" can sign in with '
            'ID ${p.partyCode}.')));
  } on PartyLoginPendingException {
    messenger.showSnackBar(const SnackBar(
      content: Text('Cloud Functions not deployed yet. Run: '
          'firebase deploy --only functions'),
      duration: Duration(seconds: 6),
    ));
  } catch (e) {
    messenger
        .showSnackBar(SnackBar(content: Text('Could not provision login: $e')));
  }
}

// ---------------------------------------------------------------------------
// Modern dealer card
// ---------------------------------------------------------------------------

class _PartyCard extends StatelessWidget {
  const _PartyCard({
    required this.party,
    required this.onOpen,
    required this.onAction,
  });
  final Party party;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final p = party;
    final theme = Theme.of(context);
    final active = p.status == 'active';
    final seed = p.name.isNotEmpty ? p.name : p.partyCode;
    final avatar = seed.trim().isNotEmpty ? seed.trim()[0].toUpperCase() : '?';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(avatar,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full name — wraps, never truncated.
                    Text(p.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        'ID: ${p.partyCode}'
                        '${p.phone != null && p.phone!.isNotEmpty ? '  ·  ${p.phone}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _pill(active ? 'Active' : 'Inactive',
                            active
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF9AA6BC)),
                        if (p.defaultDiscount > 0)
                          _pill('${Formatters.qty(p.defaultDiscount)}% off',
                              const Color(0xFF0F4CBA)),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: onAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'create_order',
                      child: Text('Create order')),
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                      value: 'login',
                      child: Text('Provision / reset login')),
                  PopupMenuItem(
                      value: active ? 'deactivate' : 'activate',
                      child: Text(active ? 'Deactivate' : 'Activate')),
                  const PopupMenuItem(
                      value: 'delete',
                      child:
                          Text('Delete', style: TextStyle(color: Colors.red))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      );
}

// ---------------------------------------------------------------------------
// Dealer detail — every field the admin entered, in cards, nothing truncated,
// including the login ID + password (copyable).
// ---------------------------------------------------------------------------

class _PartyDetailScreen extends ConsumerStatefulWidget {
  const _PartyDetailScreen({required this.partyId, required this.initial});
  final String partyId;
  final Party initial;

  @override
  ConsumerState<_PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends ConsumerState<_PartyDetailScreen> {
  bool _showPassword = false;

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
  }

  Future<void> _delete(Party p) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete party?'),
        content: Text(
            'Delete "${p.name}" (${p.partyCode})? This permanently removes the '
            'party AND revokes their login. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete & revoke access'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(partyRepositoryProvider).deleteWithAccess(p.id);
      messenger.showSnackBar(SnackBar(content: Text('Deleted "${p.name}".')));
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parties = ref.watch(partiesProvider).valueOrNull ?? const <Party>[];
    final p = parties.firstWhere((e) => e.id == widget.partyId,
        orElse: () => widget.initial);
    final active = p.status == 'active';
    final email = AuthRepository.partyIdToEmail(p.partyCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showDialog(
                context: context, builder: (_) => _PartyForm(existing: p)),
          ),
          PopupMenuButton<String>(
            onSelected: (a) {
              final repo = ref.read(partyRepositoryProvider);
              if (a == 'login') provisionDealerLogin(context, ref, p);
              if (a == 'activate') repo.setStatus(p.id, 'active');
              if (a == 'deactivate') repo.setStatus(p.id, 'inactive');
              if (a == 'delete') _delete(p);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'login', child: Text('Provision / reset login')),
              PopupMenuItem(
                  value: active ? 'deactivate' : 'activate',
                  child: Text(active ? 'Deactivate' : 'Activate')),
              const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                    (p.name.isNotEmpty ? p.name : p.partyCode)
                        .trim()
                        .substring(0, 1)
                        .toUpperCase(),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: (active
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF9AA6BC))
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(active ? 'Active' : 'Inactive',
                          style: TextStyle(
                              color: active
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF6B7690),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Login credentials
          _section('Login credentials', [
            _copyRow('Login ID', p.partyCode),
            _passwordRow(p.loginPassword),
            _copyRow('Login email', email),
          ]),

          // Contact
          _section('Contact', [
            _row('Owner', p.ownerName),
            _row('Phone', p.phone, copyValue: p.phone),
            _row('WhatsApp', p.whatsapp, copyValue: p.whatsapp),
            _row('Email', p.email, copyValue: p.email),
          ]),

          // Business
          _section('Business', [
            _row('GST number', p.gstNumber, copyValue: p.gstNumber),
            _row('Credit limit',
                p.creditLimit > 0 ? Formatters.money(p.creditLimit) : null),
            _row('Cash discount',
                p.defaultDiscount > 0 ? '${p.defaultDiscount}%' : null),
            _row('Payment terms', p.paymentTerms),
            _row('Transport', p.transport),
          ]),

          // Discount structure (category / subcategory / product rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text('Discount structure',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                DiscountStructureView(
                  partyId: p.id,
                  globalPercent: p.defaultDiscount,
                  showGlobal: false,
                ),
              ],
            ),
          ),

          // Address
          _section('Address', [
            _row('Address', p.address),
            _row('City', p.city),
            _row('State', p.state),
            _row('Pincode', p.pincode),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    final visible = rows
        .whereType<_DetailRow>()
        .where((r) => r.label.isNotEmpty)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: visible),
            ),
          ),
        ],
      ),
    );
  }

  // Returns a _DetailRow only when there's a value (so empty fields disappear).
  Widget _row(String label, String? value, {String? copyValue}) {
    if (value == null || value.trim().isEmpty) return const _DetailRow.empty();
    return _DetailRow(
      label: label,
      value: value,
      onCopy: copyValue == null ? null : () => _copy(label, copyValue),
    );
  }

  Widget _copyRow(String label, String value) => _DetailRow(
        label: label,
        value: value,
        strong: true,
        onCopy: () => _copy(label, value),
      );

  Widget _passwordRow(String? password) {
    if (password == null || password.isEmpty) {
      return const _DetailRow(
        label: 'Password',
        value: 'Not stored (set before this feature). Recreate the dealer to '
            'set a viewable password.',
        muted: true,
      );
    }
    return _DetailRow(
      label: 'Password',
      value: _showPassword ? password : '•' * password.length,
      strong: true,
      onCopy: () => _copy('Password', password),
      trailing: IconButton(
        tooltip: _showPassword ? 'Hide' : 'Show',
        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility,
            size: 20),
        onPressed: () => setState(() => _showPassword = !_showPassword),
      ),
    );
  }
}

/// One label/value row inside a detail card (value is selectable & never
/// truncated). The `.empty()` variant renders nothing and is filtered out.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.onCopy,
    this.trailing,
    this.strong = false,
    this.muted = false,
  });
  const _DetailRow.empty()
      : label = '',
        value = '',
        onCopy = null,
        trailing = null,
        strong = false,
        muted = false;

  final String label;
  final String value;
  final VoidCallback? onCopy;
  final Widget? trailing;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                color: muted ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
          if (trailing != null) trailing!,
          if (onCopy != null)
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}

class _PartyForm extends ConsumerStatefulWidget {
  const _PartyForm({this.existing});
  final Party? existing;

  @override
  ConsumerState<_PartyForm> createState() => _PartyFormState();
}

class _PartyFormState extends ConsumerState<_PartyForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _c = {
      'partyCode': TextEditingController(text: p?.partyCode ?? ''),
      'name': TextEditingController(text: p?.name ?? ''),
      'ownerName': TextEditingController(text: p?.ownerName ?? ''),
      'phone': TextEditingController(text: p?.phone ?? ''),
      'whatsapp': TextEditingController(text: p?.whatsapp ?? ''),
      'email': TextEditingController(text: p?.email ?? ''),
      'gstNumber': TextEditingController(text: p?.gstNumber ?? ''),
      'address': TextEditingController(text: p?.address ?? ''),
      'city': TextEditingController(text: p?.city ?? ''),
      'state': TextEditingController(text: p?.state ?? ''),
      'pincode': TextEditingController(text: p?.pincode ?? ''),
      'transport': TextEditingController(text: p?.transport ?? ''),
      'paymentTerms': TextEditingController(text: p?.paymentTerms ?? ''),
      'creditLimit':
          TextEditingController(text: (p?.creditLimit ?? 0).toString()),
      'defaultDiscount':
          TextEditingController(text: (p?.defaultDiscount ?? 0).toString()),
      'password': TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String k) => _c[k]!.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(partyRepositoryProvider);
      final companyId = ref.read(currentUserProvider).valueOrNull?.companyId ??
          AppConstants.defaultCompanyId;
      final party = Party(
        id: widget.existing?.id ?? '',
        companyId: companyId,
        partyCode: _t('partyCode'),
        name: _t('name'),
        ownerName: _t('ownerName'),
        phone: _t('phone'),
        whatsapp: _t('whatsapp'),
        email: _t('email'),
        gstNumber: _t('gstNumber'),
        address: _t('address'),
        city: _t('city'),
        state: _t('state'),
        pincode: _t('pincode'),
        transport: _t('transport'),
        paymentTerms: _t('paymentTerms'),
        creditLimit: double.tryParse(_t('creditLimit')) ?? 0,
        defaultDiscount: double.tryParse(_t('defaultDiscount')) ?? 0,
        status: widget.existing?.status ?? 'active',
      );
      if (_isEdit) {
        await repo.update(party);
      } else {
        await repo.createWithLogin(party: party, password: _t('password'));
      }
      if (mounted) Navigator.pop(context);
    } on PartyLoginPendingException {
      // Party was saved; only the client login couldn't be created (Cloud
      // Functions not deployed). Close and warn rather than blocking.
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Party saved. Client login is pending — deploy Cloud Functions '
              '(Blaze) to enable dealer sign-in.'),
          duration: Duration(seconds: 5),
        ));
      }
    } catch (e) {
      setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Party' : 'Add Party'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 96).clamp(260.0, 520.0).toDouble(),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field('partyCode', 'Party ID (login)',
                    validator: (v) => Validators.required(v, field: 'Party ID'),
                    enabled: !_isEdit),
                _field('name', 'Party name',
                    validator: (v) => Validators.required(v, field: 'Name')),
                _field('ownerName', 'Owner name (optional)'),
                Row(children: [
                  Expanded(child: _field('phone', 'Phone')),
                  const SizedBox(width: 12),
                  Expanded(child: _field('whatsapp', 'WhatsApp')),
                ]),
                _field('email', 'Email (optional)'),
                _field('gstNumber', 'GST number (optional)'),
                _field('address', 'Address'),
                Row(children: [
                  Expanded(child: _field('city', 'City')),
                  const SizedBox(width: 12),
                  Expanded(child: _field('state', 'State')),
                ]),
                Row(children: [
                  Expanded(child: _field('pincode', 'Pincode')),
                  const SizedBox(width: 12),
                  Expanded(child: _field('transport', 'Transport')),
                ]),
                _field('paymentTerms', 'Payment terms (optional)'),
                Row(children: [
                  Expanded(child: _field('creditLimit', 'Credit limit')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field('defaultDiscount', 'Cash discount %')),
                ]),
                if (!_isEdit)
                  _field('password', 'Login password',
                      obscure: true, validator: Validators.password),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(String key, String label,
      {String? Function(String?)? validator,
      bool obscure = false,
      bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _c[key],
        obscureText: obscure,
        enabled: enabled,
        decoration: InputDecoration(labelText: label, isDense: true),
        validator: validator,
      ),
    );
  }
}
