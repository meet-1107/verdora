import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../../features/settings/presentation/settings_providers.dart';
import 'app_image.dart';

/// Shows a simple branded splash on top of [child] for a short time on cold
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
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _fade = true);
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
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
            duration: const Duration(milliseconds: 450),
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branding = ref.watch(brandingProvider).valueOrNull;
    final logo = appImageProvider(branding?.logoUrl);
    final name = (branding?.name.isNotEmpty ?? false)
        ? branding!.name
        : AppConstants.appName;
    const accent = Color(0xFF1565C0);

    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    final scale = Tween<double>(begin: 0.85, end: 1).animate(
        CurvedAnimation(parent: _intro, curve: Curves.easeOutBack));

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Center(
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Animated ring around the logo.
                        const SizedBox(
                          width: 140,
                          height: 140,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(accent),
                          ),
                        ),
                        // Round logo badge with a border.
                        Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: accent, width: 2.5),
                            image: logo == null
                                ? null
                                : DecorationImage(
                                    image: logo, fit: BoxFit.cover),
                          ),
                          alignment: Alignment.center,
                          child: logo == null
                              ? Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : 'V',
                                  style: const TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.w800,
                                      color: accent),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
