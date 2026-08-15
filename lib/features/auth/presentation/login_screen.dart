import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_image.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/auth_repository.dart';

enum _LoginMode { admin, client }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  // ---- form state (unchanged logic) ----
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  _LoginMode _mode = _LoginMode.admin;
  bool _loading = false;
  bool _obscure = true;
  bool _remember = true;
  String? _error;

  // ---- presentation-only animation ----
  late final AnimationController _entrance;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _logoFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _cardFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
    ));
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _entrance.dispose();
    _shake.dispose();
    super.dispose();
  }

  // ---- auth logic (UNCHANGED) ----
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      if (_mode == _LoginMode.admin) {
        await repo.signInAdmin(
          email: _identifier.text,
          password: _password.text,
        );
      } else {
        await repo.signInClient(
          partyId: _identifier.text,
          password: _password.text,
        );
      }
      // Router redirects on the resulting auth-state change.
    } on Exception catch (e) {
      setState(() => _error = _friendlyError(e));
      _shake.forward(from: 0); // presentation-only feedback
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Exception e) {
    final msg = e.toString();
    if (msg.contains('user-not-found') || msg.contains('wrong-password')) {
      return 'Invalid credentials. Please try again.';
    }
    if (msg.contains('invalid-credential')) {
      return 'Invalid credentials. Please try again.';
    }
    if (msg.contains('network')) {
      return 'Unable to connect. Check your internet connection.';
    }
    if (msg.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    }
    return 'Sign in failed. Please try again.';
  }

  void _openForgotPassword() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forgot password?'),
        content: const Text(
          'Accounts are managed by your company administrator. Please contact '
          'them to reset your password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isAdmin = _mode == _LoginMode.admin;
    final branding = ref.watch(brandingProvider).valueOrNull;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.xxxl,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ---- brand ----
                      FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: _BrandLogo(logoUrl: branding?.logoUrl),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      FadeTransition(
                        opacity: _cardFade,
                        child: Column(
                          children: [
                            // Company name (from settings) shown below the logo.
                            if ((branding?.name ?? '').isNotEmpty) ...[
                              Text(
                                branding!.name,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                            Text(
                              'Business Ordering & Inventory',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.huge),
                      // ---- login card ----
                      SlideTransition(
                        position: _cardSlide,
                        child: FadeTransition(
                          opacity: _cardFade,
                          child: _buildCard(theme, scheme, isAdmin),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      // ---- support + footer ----
                      Text(
                        'Need help? Contact your company administrator.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Developed by Verdora  ·  Contact: 6351007253',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(ThemeData theme, ColorScheme scheme, bool isAdmin) {
    // Horizontal shake on error (presentation only).
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final dx = math.sin(_shake.value * math.pi * 4) * 10 * (1 - _shake.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Welcome back', style: theme.textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Sign in to continue',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                // ---- role toggle ----
                SegmentedButton<_LoginMode>(
                  segments: const [
                    ButtonSegment(
                      value: _LoginMode.admin,
                      icon: Icon(Icons.admin_panel_settings_outlined),
                      label: Text('Admin'),
                    ),
                    ButtonSegment(
                      value: _LoginMode.client,
                      icon: Icon(Icons.storefront_outlined),
                      label: Text('Client'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() {
                    _mode = s.first;
                    _error = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.xl),
                // ---- identifier ----
                TextFormField(
                  controller: _identifier,
                  keyboardType: isAdmin
                      ? TextInputType.emailAddress
                      : TextInputType.text,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    labelText: isAdmin ? 'Email' : 'Party ID',
                    hintText: isAdmin ? 'you@company.com' : 'e.g. SR1001',
                    helperText: isAdmin
                        ? null
                        : 'Enter the Party ID provided by your company.',
                    prefixIcon: Icon(isAdmin
                        ? Icons.email_outlined
                        : Icons.business_outlined),
                  ),
                  validator: (v) => isAdmin
                      ? Validators.email(v)
                      : Validators.required(v, field: 'Party ID'),
                ),
                const SizedBox(height: AppSpacing.lg),
                // ---- password ----
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  enableInteractiveSelection: false, // no copy/paste
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: Validators.password,
                  onFieldSubmitted: (_) => _submit(),
                ),
                // ---- forgot password ----
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _openForgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                ),
                // ---- error ----
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _error == null
                      ? const SizedBox.shrink()
                      : Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: scheme.error.withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(AppRadius.textField),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  size: 20, color: scheme.error),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                      color: scheme.error, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // ---- remember me ----
                Row(
                  children: [
                    Checkbox(
                      value: _remember,
                      onChanged: (v) =>
                          setState(() => _remember = v ?? false),
                    ),
                    const Text('Remember me'),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // ---- submit ----
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: AppSpacing.md),
                            Text('Signing in…'),
                          ],
                        )
                      : const Text('LOGIN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded brand logo tile — shows the company logo if one is set, else the
/// default app icon.
class _BrandLogo extends StatelessWidget {
  const _BrandLogo({this.logoUrl});
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = appImageProvider(logoUrl);
    final hasLogo = provider != null;
    return Container(
      width: 104,
      height: 104,
      padding: hasLogo ? const EdgeInsets.all(10) : EdgeInsets.zero,
      decoration: BoxDecoration(
        // White plate behind the logo so it reads on any theme; brand tint for
        // the default icon.
        color: hasLogo ? Colors.white : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: hasLogo
          ? Image(image: provider, fit: BoxFit.contain)
          : Icon(Icons.inventory_2_rounded, size: 40, color: scheme.primary),
    );
  }
}

/// Subtle brand-tinted background shapes (~4% opacity). No photos/gradients.
class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -130,
            left: -90,
            child: _blob(primary.withValues(alpha: 0.05), 300),
          ),
          Positioned(
            bottom: -160,
            right: -110,
            child: _blob(primary.withValues(alpha: 0.04), 360),
          ),
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
