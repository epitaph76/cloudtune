import 'dart:math' as math;

import 'package:flutter/material.dart';

class NowPlayingWaveBackground extends StatefulWidget {
  const NowPlayingWaveBackground({
    super.key,
    required this.isActive,
    required this.child,
  });

  final bool isActive;
  final Widget child;

  @override
  State<NowPlayingWaveBackground> createState() =>
      _NowPlayingWaveBackgroundState();
}

class _NowPlayingWaveBackgroundState extends State<NowPlayingWaveBackground>
    with SingleTickerProviderStateMixin {
  static const Duration _wavePeriod = Duration(milliseconds: 1400);
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _wavePeriod);
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant NowPlayingWaveBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              opacity: widget.isActive ? 1 : 0,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _NowPlayingWavePainter(
                      t: _controller.value,
                      primary: colorScheme.primary,
                      secondary: colorScheme.tertiary,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _NowPlayingWavePainter extends CustomPainter {
  const _NowPlayingWavePainter({
    required this.t,
    required this.primary,
    required this.secondary,
  });

  final double t;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final phase = t * 2 * math.pi;
    final lines = 7;
    final topPadding = size.height * 0.03;
    final verticalSpan = size.height * 0.78;
    final stepY = verticalSpan / (lines - 1);

    for (int i = 0; i < lines; i++) {
      final baseY = topPadding + (i * stepY);
      final amp = 7.0 + (i % 2) * 2.5;
      final frequency = 2.0 + (i % 3) * 0.35;
      final localPhase = phase + (i * 0.85);
      final path = Path()..moveTo(0, baseY);

      for (double x = 0; x <= size.width; x += 8) {
        final nx = size.width == 0 ? 0.0 : x / size.width;
        final y =
            baseY + math.sin((nx * 2 * math.pi * frequency) + localPhase) * amp;
        path.lineTo(x, y);
      }

      final color = Color.lerp(
        primary,
        secondary,
        i / (lines - 1),
      )!.withValues(alpha: 0.24);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.9
        ..color = color;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NowPlayingWavePainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary;
  }
}
