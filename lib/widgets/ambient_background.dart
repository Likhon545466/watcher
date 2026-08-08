import 'package:flutter/material.dart';

class AmbientBackground extends StatelessWidget {
  final Widget child;

  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

    return Stack(
      children: <Widget>[
        Positioned.fill(child: Container(color: scaffoldBg)),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? <Color>[
                        primary.withOpacity(0.12),
                        Colors.transparent,
                        primary.withOpacity(0.05),
                      ]
                    : <Color>[
                        primary.withOpacity(0.08),
                        Colors.transparent,
                        primary.withOpacity(0.04),
                      ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
