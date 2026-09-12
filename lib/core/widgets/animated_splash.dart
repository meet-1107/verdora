import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../../features/settings/presentation/settings_providers.dart';
import 'app_image.dart';

/// Shows an animated branded splash on top of [child] for a short time on cold
/// start, then fades away — so the launch/loading wait isn't a blank screen.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _show = true;
  bool _fade = false;

  @override
  void initState() {
    super.initState();
    // Keep the splash up briefly, then fade it out.
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _fade = true);
    });
    Future.delayed(const Duration(milliseconds: 2900), () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_show)
          AnimatedOpacity(
            opacity: _fade ? 0 : 1,
            duration: const Duration(milliseconds: 500),
            child: const _AnimatedSplash(),
          ),
      ],
    );
  }
}

class _AnimatedSplash extends ConsumerStatefulWidget {
  const _AnimatedSplash();

  @override
  ConsumerState<_AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends ConsumerState<_AnimatedSplash>
    with TickerProviderStateMixin {
  late final AnimationController _intro; // one-shot entrance
  late final AnimationController _pulse; // looping logo pulse

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(brandingProvider).valueOrNull;
    final logo = appImageProvider(branding?.logoUrl);
    final name = (branding?.name.isNotEmpty ?? false)
        ? branding!.name
        : AppConstants.appName;

    const c1 = Color(0xFF1565C0);
    const c2 = Color(0xFF0D47A1);

    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c1, c2],
          ),
        ),
        child: Stack(
          children: [
            // Soft decorative circles.
            Positioned(
              top: -60,
              right: -40,
              child: _blob(160, Colors.white.withValues(alpha: 0.08)),
            ),
            Positioned(
              bottom: -50,
              left: -30,
              child: _blob(130, Colors.white.withValues(alpha: 0.06)),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsing logo badge.
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.6, end: 1).animate(
                        CurvedAnimation(
                            parent: _intro, curve: Curves.easeOutBack)),
                    child: FadeTransition(
                      opacity: fade,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, child) {
                          final s = 1 + (_pulse.value * 0.06);
                          return Transform.scale(scale: s, child: child);
                        },
                        child: Container(
                          width: 116,
                          height: 116,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.20),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                            image: logo == null
                                ? null
                                : DecorationImage(
                                    image: logo, fit: BoxFit.contain),
                          ),
                          alignment: Alignment.center,
                          child: logo == null
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'V',
                                  style: const TextStyle(
                                      fontSize: 52,
                                      fontWeight: FontWeight.w800,
                                      color: c2),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SlideTransition(
                    position: slide,
                    child: FadeTransition(
                      opacity: fade,
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: fade,
                    child: Text(
                      'Inventory & Orders',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85),
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Loading indicator near the bottom.
            Positioned(
              left: 0,
              right: 0,
              bottom: 56,
              child: Center(
                child: FadeTransition(
                  opacity: fade,
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.9)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
