import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';

/// Premium application entry screen.
///
/// This widget is **purely presentational** — the real initialization and
/// routing decisions happen in `main.dart` (Firebase init) and the GoRouter
/// redirect (auth/profile/role). The router keeps this screen visible while
/// those providers resolve, then navigates away. No business logic lives here.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<double> _loaderFade;

  Timer? _messageTimer;
  int _messageIndex = 0;

  // Reassuring, professional status copy. Cycled for perceived progress; the
  // real navigation happens whenever the router's providers are ready.
  static const _messages = <String>[
    'Initializing…',
    'Connecting securely…',
    'Checking your account…',
    'Loading your workspace…',
    'Syncing settings…',
    'Almost ready…',
  ];

  static const _version = 'v0.1.0';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // Logo: fade in + gentle scale 0.92 -> 1.0.
    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    // Name + tagline fade in after the logo.
    _textFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
    );
    // Loading section appears last.
    _loaderFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
    );

    _controller.forward();

    _messageTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Subtle nature-inspired background shapes (~4% opacity).
          const Positioned.fill(child: _SplashBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  // ---- Logo + identity ----
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: const _Logo(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _textFade,
                    child: Column(
                      children: [
                        Text(
                          AppConstants.appName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            'Business Ordering & Inventory',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // ---- Loading section ----
                  FadeTransition(
                    opacity: _loaderFade,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(scheme.primary),
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Smoothly cross-fade between status messages.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: child,
                          ),
                          child: Text(
                            _messages[_messageIndex],
                            key: ValueKey<int>(_messageIndex),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 4),
                  // ---- Footer ----
                  FadeTransition(
                    opacity: _loaderFade,
                    child: Column(
                      children: [
                        Text(
                          _version,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '© 2026 ${AppConstants.appName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded logo tile: soft shadow, tinted background, brand-green glyph.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.inventory_2_rounded,
        size: 46,
        color: scheme.primary,
      ),
    );
  }
}

/// Very subtle, brand-tinted abstract shapes. No photos, no strong gradients.
class _SplashBackground extends StatelessWidget {
  const _SplashBackground();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -100,
            child: _blob(primary.withValues(alpha: 0.05), 300),
          ),
          Positioned(
            bottom: -140,
            left: -110,
            child: _blob(primary.withValues(alpha: 0.04), 340),
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
