import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lightweight, theme-aware animated background using CustomPainter.
/// Draws slow-moving soft radial gradient blobs with minimal CPU/GPU overhead.
/// Features a subtle hue/pulse shift when [isLoading] is true, and automatically
/// pauses when the app is placed in the background.
class DynamicBackground extends StatefulWidget {
  final Widget child;
  final bool isLoading;

  const DynamicBackground({
    super.key,
    required this.child,
    this.isLoading = false,
  });

  @override
  State<DynamicBackground> createState() => _DynamicBackgroundState();
}

class _DynamicBackgroundState extends State<DynamicBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;

  bool get _isTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 25-second slow and graceful loop for minimal CPU cycles
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    );
    if (!_isTest) {
      _controller.repeat();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isTest) return;
    if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Solid background base
        Positioned.fill(
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
        ),
        // RepaintBoundary isolated gradient animation
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _MeshBlobPainter(
                    progress: _controller.value,
                    isDark: isDark,
                    isLoading: widget.isLoading,
                  ),
                );
              },
            ),
          ),
        ),
        // Foreground Content
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _MeshBlobPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  final bool isLoading;

  _MeshBlobPainter({
    required this.progress,
    required this.isDark,
    required this.isLoading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final t = progress * 2 * math.pi;

    // Pulse multiplier during active research loading
    final pulse = isLoading ? 1.0 + 0.15 * math.sin(t * 3) : 1.0;

    // Blob 1: Teal / Cyan (Top Left drifting to Center)
    final blob1Center = Offset(
      size.width * (0.22 + 0.12 * math.cos(t)),
      size.height * (0.25 + 0.10 * math.sin(t * 0.9)),
    );
    final blob1Radius = size.shortestSide * 0.45 * pulse;
    final blob1Color = isDark
        ? const Color(0xFF0F766E).withValues(alpha: isLoading ? 0.22 : 0.14)
        : const Color(0xFF99F6E4).withValues(alpha: isLoading ? 0.35 : 0.22);

    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [blob1Color, blob1Color.withValues(alpha: 0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: blob1Center, radius: blob1Radius));
    canvas.drawCircle(blob1Center, blob1Radius, paint1);

    // Blob 2: Deep Indigo / Soft Lavender (Top Right drifting downwards)
    final blob2Center = Offset(
      size.width * (0.80 - 0.14 * math.sin(t * 0.8)),
      size.height * (0.35 + 0.12 * math.cos(t * 0.8)),
    );
    final blob2Radius = size.shortestSide * 0.50 * pulse;
    final blob2Color = isDark
        ? const Color(0xFF312E81).withValues(alpha: isLoading ? 0.25 : 0.16)
        : const Color(0xFFE0E7FF).withValues(alpha: isLoading ? 0.45 : 0.28);

    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [blob2Color, blob2Color.withValues(alpha: 0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: blob2Center, radius: blob2Radius));
    canvas.drawCircle(blob2Center, blob2Radius, paint2);

    // Blob 3: Warm Amber / Sunset (Bottom Center drifting horizontally)
    final blob3Center = Offset(
      size.width * (0.50 + 0.15 * math.cos(t * 1.1)),
      size.height * (0.80 - 0.10 * math.sin(t * 1.1)),
    );
    final blob3Radius = size.shortestSide * 0.42 * pulse;
    final blob3Color = isDark
        ? const Color(0xFFB45309).withValues(alpha: isLoading ? 0.16 : 0.08)
        : const Color(0xFFFEF3C7).withValues(alpha: isLoading ? 0.35 : 0.20);

    final paint3 = Paint()
      ..shader = RadialGradient(
        colors: [blob3Color, blob3Color.withValues(alpha: 0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: blob3Center, radius: blob3Radius));
    canvas.drawCircle(blob3Center, blob3Radius, paint3);
  }

  @override
  bool shouldRepaint(covariant _MeshBlobPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isLoading != isLoading;
  }
}
