import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Lightweight dot-grid background replicating `.grid` from reference prototype.
/// Renders a crisp 22px grid of 1px circular dots in `--line` at 0.7 opacity with zero overhead.
class DynamicBackground extends StatelessWidget {
  final Widget child;
  final bool isLoading;

  const DynamicBackground({
    super.key,
    required this.child,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark ? AppTheme.darkLines : AppTheme.lightLines;

    return Stack(
      children: [
        // Base scaffold background color
        Positioned.fill(
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
        ),
        // RepaintBoundary isolated dot-grid
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _DotGridPainter(
                lineColor: lineColor,
              ),
            ),
          ),
        ),
        // Foreground Content
        Positioned.fill(child: child),
      ],
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color lineColor;

  _DotGridPainter({
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final dotPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const double spacing = 22.0;
    const double radius = 1.0;

    for (double x = spacing / 2; x < size.width; x += spacing) {
      for (double y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}
