import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blur;
  final double? opacity; // Optional local override
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding,
    this.margin,
    this.blur = 0,
    this.opacity,
    this.borderColor,
    this.boxShadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final activeOpacity = opacity ?? settings.glassOpacity;
    final isSolid = activeOpacity == 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final border =
        borderColor ??
        (isSolid
            ? (isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.05))
            : (isDark
                  ? Colors.white.withOpacity(0.15)
                  : Colors.black.withOpacity(0.08)));

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: isSolid
            ? (isDark ? const Color(0xFF1E293B) : Colors.white)
            : (isDark ? Colors.white : Theme.of(context).colorScheme.surface)
                  .withOpacity(activeOpacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border, width: 1),
        boxShadow:
            boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                blurRadius: 12,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: content,
        ),
      );
    }

    return content;
  }
}

class GlassSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const GlassSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  State<GlassSkeleton> createState() => _GlassSkeletonState();
}

class _GlassSkeletonState extends State<GlassSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(
      begin: 0.08,
      end: 0.22,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withOpacity(
              _opacityAnimation.value,
            ),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
            ),
          ),
        );
      },
    );
  }
}

class ShowRowSkeleton extends StatelessWidget {
  const ShowRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        borderRadius: 16,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: const [
            GlassSkeleton(width: 80, height: 115, borderRadius: 12),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlassSkeleton(width: 160, height: 16),
                  SizedBox(height: 8),
                  GlassSkeleton(width: 80, height: 12),
                  SizedBox(height: 12),
                  GlassSkeleton(width: 120, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
