import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Animated shimmer wrapper. Wrap grey [AppSkeletonBox]es in it to build
/// content-shaped loading placeholders instead of blank screens/spinners.
class AppShimmer extends StatefulWidget {
  const AppShimmer({super.key, required this.child});
  final Widget child;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.35),
      base,
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final t = _controller.value;
            return LinearGradient(
              begin: Alignment(-1 - t * 2, 0),
              end: Alignment(1 - t * 2, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A single grey placeholder block.
class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Shimmering placeholder grid for the categories screen ([count] tiles).
class AppCategorySkeleton extends StatelessWidget {
  const AppCategorySkeleton({
    super.key,
    this.count = 8,
    this.crossAxisCount = 2,
  });

  final int count;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: GridView.count(
        padding: const EdgeInsets.all(AppSpacing.lg),
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.lg,
        childAspectRatio: 0.95,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < count; i++)
            const AppSkeletonBox(height: double.infinity, radius: 20),
        ],
      ),
    );
  }
}

/// Shimmering placeholder list ([count] rows) for list-based screens.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({super.key, this.count = 6, this.rowHeight = 88});

  final int count;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: count,
        physics: const NeverScrollableScrollPhysics(),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, __) =>
            AppSkeletonBox(height: rowHeight, radius: 18),
      ),
    );
  }
}

/// Ready-made skeleton for the client/admin dashboard (metric cards + list).
class AppSkeletonDashboard extends StatelessWidget {
  const AppSkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSkeletonBox(width: 180, height: 20),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  const Expanded(
                    child: AppSkeletonBox(height: 110, radius: 20),
                  ),
                  if (i < 2) const SizedBox(width: AppSpacing.md),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            const AppSkeletonBox(width: 140, height: 18),
            const SizedBox(height: AppSpacing.lg),
            for (var i = 0; i < 4; i++) ...[
              const AppSkeletonBox(height: 64, radius: 20),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
