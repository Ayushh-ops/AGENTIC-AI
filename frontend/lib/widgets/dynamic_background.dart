import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Lightweight dot-grid background with cursor dot spotlight replicating `.grid` and `.spot`
/// from reference prototype.
///
/// Layer 1 (static): faint dot grid, 22px spacing, 1px dots in `lineColor`, opacity 0.7.
/// Layer 2 (spotlight): same 22px grid in `accentColor` (1.2px radius), base opacity 0.5,
/// visible ONLY within a 260px radius circle around the mouse pointer, fading to 0 at 70% of radius.
class DynamicBackground extends StatefulWidget {
  final Widget child;
  final bool isLoading;
  final Color? accentColor;
  final bool? spotlightEnabled;

  const DynamicBackground({
    super.key,
    required this.child,
    this.isLoading = false,
    this.accentColor,
    this.spotlightEnabled,
  });

  @override
  State<DynamicBackground> createState() => _DynamicBackgroundState();
}

class _DynamicBackgroundState extends State<DynamicBackground> {
  late final ValueNotifier<Offset?> _pointerNotifier;

  @override
  void initState() {
    super.initState();
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    // In test mode, don't start pointer tracking to avoid unnecessary repaints
    _pointerNotifier = ValueNotifier<Offset?>(null);

    if (!isTest) {
      // Set initial position: center-x, 25% height after first layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final size = MediaQuery.maybeSizeOf(context);
        if (size != null && size.width > 0 && size.height > 0) {
          _pointerNotifier.value = Offset(size.width / 2, size.height * 0.25);
        }
      });
    }
  }

  @override
  void dispose() {
    _pointerNotifier.dispose();
    super.dispose();
  }

  void _onPointerHover(PointerHoverEvent event) {
    _pointerNotifier.value = event.localPosition;
  }

  void _onPointerExit(PointerExitEvent event) {
    // Optionally keep last position or clear
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark ? AppTheme.darkLines : AppTheme.lightLines;
    final accent = widget.accentColor ?? (isDark ? AppTheme.darkAt : AppTheme.lightAt);
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    final bool enableSpotlight =
        widget.spotlightEnabled ?? SettingsService.instance.isSpotlightActive;

    return MouseRegion(
      onHover: isTest ? null : _onPointerHover,
      onExit: isTest ? null : _onPointerExit,
      child: Stack(
        children: [
          // Base scaffold background color
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),

          // Layer 1: Static dot grid (re-paints only on theme change)
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _DotGridPainter(lineColor: lineColor),
              ),
            ),
          ),

          // Layer 2: Cursor spotlight dot grid (re-paints only when pointer moves)
          if (!isTest && enableSpotlight)
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<Offset?>(
                  valueListenable: _pointerNotifier,
                  builder: (context, pointer, _) {
                    if (pointer == null) return const SizedBox.shrink();
                    return CustomPaint(
                      painter: _SpotlightDotPainter(
                        pointer: pointer,
                        accentColor: accent,
                      ),
                    );
                  },
                ),
              ),
            ),

          // Foreground Content
          Positioned.fill(child: widget.child),
        ],
      ),
    );
  }
}

/// Static dot grid painter (Layer 1)
class _DotGridPainter extends CustomPainter {
  final Color lineColor;

  _DotGridPainter({required this.lineColor});

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

/// Dynamic spotlight dot painter (Layer 2)
/// Renders 1.2px radius dots in accentColor, only within 260px of the pointer,
/// fading to 0 at 70% of radius (182px).
class _SpotlightDotPainter extends CustomPainter {
  final Offset pointer;
  final Color accentColor;

  static const double spacing = 22.0;
  static const double spotlightRadius = 260.0;
  static const double fadeRadius = spotlightRadius * 0.7; // ~182px
  static const double dotRadius = 1.2;

  _SpotlightDotPainter({
    required this.pointer,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Bounding box of the spotlight to minimize work
    final minX = (pointer.dx - spotlightRadius).clamp(0.0, size.width);
    final maxX = (pointer.dx + spotlightRadius).clamp(0.0, size.width);
    final minY = (pointer.dy - spotlightRadius).clamp(0.0, size.height);
    final maxY = (pointer.dy + spotlightRadius).clamp(0.0, size.height);

    // Snap to grid boundaries
    final startX = (minX / spacing).floor() * spacing + (spacing / 2);
    final startY = (minY / spacing).floor() * spacing + (spacing / 2);

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (double x = startX; x <= maxX; x += spacing) {
      final dx = x - pointer.dx;
      final dx2 = dx * dx;

      for (double y = startY; y <= maxY; y += spacing) {
        final dy = y - pointer.dy;
        final distSq = dx2 + (dy * dy);

        // Skip if outside 260px circle
        if (distSq > spotlightRadius * spotlightRadius) continue;

        // Accurate sqrt only for candidate dots
        final distance = (Offset(x, y) - pointer).distance;
        if (distance > spotlightRadius) continue;

        // Radial fade: full strength (0.5 opacity) at center, ~0 at 70% radius
        // Formula: base_opacity * (1.0 - (distance / fadeRadius).clamp(0.0, 1.0))
        final fadeFactor = (1.0 - (distance / fadeRadius)).clamp(0.0, 1.0);
        if (fadeFactor <= 0.0) continue;

        final alpha = 0.5 * fadeFactor;
        dotPaint.color = accentColor.withValues(alpha: alpha);
        canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightDotPainter oldDelegate) {
    return oldDelegate.pointer != pointer || oldDelegate.accentColor != accentColor;
  }
}
