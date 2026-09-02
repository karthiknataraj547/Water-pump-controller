import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SpatialWaterTank3D extends StatefulWidget {
  final double levelPercentage; // 0.0 to 100.0
  final double height;
  final double width;
  final bool isFilling;
  final double totalCapacityLiters;

  const SpatialWaterTank3D({
    Key? key,
    required this.levelPercentage,
    this.height = 320,
    this.width = 240,
    this.isFilling = false,
    this.totalCapacityLiters = 5000.0,
  }) : super(key: key);

  @override
  State<SpatialWaterTank3D> createState() => _SpatialWaterTank3DState();
}

class _SpatialWaterTank3DState extends State<SpatialWaterTank3D>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _bubbleController;

  // Interactive 3D Spatial Tilt Angles
  double _tiltX = -0.06;
  double _tiltY = 0.04;
  double _targetTiltX = -0.06;
  double _targetTiltY = 0.04;

  final List<_Bubble> _bubbles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Generate volumetric rising micro-bubbles
    for (int i = 0; i < 22; i++) {
      _bubbles.add(_Bubble(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 4 + 2,
        speed: _random.nextDouble() * 0.4 + 0.3,
        opacity: _random.nextDouble() * 0.5 + 0.3,
      ));
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _bubbleController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _targetTiltY += details.delta.dx * 0.003;
      _targetTiltX -= details.delta.dy * 0.003;
      _targetTiltX = _targetTiltX.clamp(-0.25, 0.25);
      _targetTiltY = _targetTiltY.clamp(-0.25, 0.25);
      _tiltX = _targetTiltX;
      _tiltY = _targetTiltY;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _targetTiltX = -0.06;
      _targetTiltY = 0.04;
    });
  }

  @override
  Widget build(BuildContext context) {
    final clampedLevel = widget.levelPercentage.clamp(0.0, 100.0);
    final currentLiters = (widget.totalCapacityLiters * (clampedLevel / 100.0)).round();

    // Responsive fluid color palette based on tank level
    Color primaryFluidColor = const Color(0xFF00E5FF);
    Color secondaryFluidColor = const Color(0xFF0066FF);
    Color fluidGlowColor = const Color(0xFF00D2FF);

    if (clampedLevel <= 20) {
      primaryFluidColor = const Color(0xFFFF5252);
      secondaryFluidColor = const Color(0xFFD50000);
      fluidGlowColor = const Color(0xFFFF1744);
    } else if (clampedLevel <= 40) {
      primaryFluidColor = const Color(0xFFFFD600);
      secondaryFluidColor = const Color(0xFFFF6D00);
      fluidGlowColor = const Color(0xFFFFAB00);
    } else if (clampedLevel >= 90) {
      primaryFluidColor = const Color(0xFF00E676);
      secondaryFluidColor = const Color(0xFF00B0FF);
      fluidGlowColor = const Color(0xFF00E676);
    }

    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: _tiltX, end: _targetTiltX),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (context, currentX, child) {
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0018) // 3D perspective depth factor
                ..rotateX(currentX)
                ..rotateY(_tiltY),
              child: Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(38),
                  boxShadow: [
                    // Dynamic 3D ambient fluid back-glow
                    BoxShadow(
                      color: fluidGlowColor.withOpacity(0.22),
                      blurRadius: 36,
                      spreadRadius: 4,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 1. 3D Spatial Cylinder & Multi-Layer Wave Painter
                    AnimatedBuilder(
                      animation: Listenable.merge([_waveController, _bubbleController]),
                      builder: (context, _) {
                        return CustomPaint(
                          size: Size(widget.width, widget.height),
                          painter: _Spatial3DTankPainter(
                            fillPct: clampedLevel / 100.0,
                            wavePhase: _waveController.value * 2 * math.pi,
                            bubbleProgress: _bubbleController.value,
                            primaryColor: primaryFluidColor,
                            secondaryColor: secondaryFluidColor,
                            glowColor: fluidGlowColor,
                            bubbles: _bubbles,
                            isFilling: widget.isFilling,
                          ),
                        );
                      },
                    ),

                    // 2. Holographic Cyber Center Readout Badge
                    Positioned(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF090D1A).withOpacity(0.78),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: fluidGlowColor.withOpacity(0.55),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: fluidGlowColor.withOpacity(0.25),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.isFilling) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.arrow_circle_up_rounded,
                                    color: primaryFluidColor,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'PUMPING WATER',
                                    style: TextStyle(
                                      color: primaryFluidColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                            ],
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  clampedLevel.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1,
                                    height: 1.0,
                                  ),
                                ),
                                Text(
                                  '%',
                                  style: TextStyle(
                                    color: primaryFluidColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$currentLiters / ${widget.totalCapacityLiters.toInt()} L',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 3. Interactive Gesture Parallax Tip
                    Positioned(
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app_rounded, color: Colors.white.withOpacity(0.4), size: 12),
                            const SizedBox(width: 4),
                            Text(
                              'Drag to tilt 3D spatial view',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Bubble {
  double x;
  double y;
  double size;
  double speed;
  double opacity;

  _Bubble({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });
}

class _Spatial3DTankPainter extends CustomPainter {
  final double fillPct;
  final double wavePhase;
  final double bubbleProgress;
  final Color primaryColor;
  final Color secondaryColor;
  final Color glowColor;
  final List<_Bubble> bubbles;
  final bool isFilling;

  _Spatial3DTankPainter({
    required this.fillPct,
    required this.wavePhase,
    required this.bubbleProgress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.glowColor,
    required this.bubbles,
    required this.isFilling,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(36));

    // Clip to rounded tank boundary
    canvas.save();
    canvas.clipRRect(rrect);

    // 1. Dark Cylindrical Glass Vessel Background with 3D Depth Gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF070B16),
          Color(0xFF141D33),
          Color(0xFF0B1020),
          Color(0xFF04060C),
        ],
        stops: [0.0, 0.35, 0.75, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    final waterHeight = size.height * fillPct;
    final baseWaterY = size.height - waterHeight;

    if (fillPct > 0.005) {
      // 2. Back Water Wave (Dual Harmonic Wave with Parallax)
      final backWavePath = Path();
      backWavePath.moveTo(0, size.height);
      backWavePath.lineTo(0, baseWaterY);

      for (double x = 0; x <= size.width; x += 4) {
        final normX = x / size.width;
        final waveY = baseWaterY +
            math.sin(normX * 2 * math.pi + wavePhase * 0.8) * 7.0 +
            math.cos(normX * 4 * math.pi - wavePhase * 0.6) * 3.0;
        backWavePath.lineTo(x, waveY);
      }
      backWavePath.lineTo(size.width, size.height);
      backWavePath.close();

      final backWavePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            secondaryColor.withOpacity(0.55),
            secondaryColor.withOpacity(0.25),
          ],
        ).createShader(rect);
      canvas.drawPath(backWavePath, backWavePaint);

      // 3. Front Water Wave (Primary Volumetric Fluid Fill)
      final frontWavePath = Path();
      frontWavePath.moveTo(0, size.height);
      frontWavePath.lineTo(0, baseWaterY);

      for (double x = 0; x <= size.width; x += 4) {
        final normX = x / size.width;
        final waveY = baseWaterY +
            math.sin(normX * 2 * math.pi - wavePhase) * 9.0 +
            math.sin(normX * 3.5 * math.pi + wavePhase * 1.3) * 4.0;
        frontWavePath.lineTo(x, waveY);
      }
      frontWavePath.lineTo(size.width, size.height);
      frontWavePath.close();

      final frontWavePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            primaryColor.withOpacity(0.88),
            secondaryColor.withOpacity(0.92),
            const Color(0xFF001F54),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(rect);
      canvas.drawPath(frontWavePath, frontWavePaint);

      // 4. 3D Elliptical Meniscus Surface at Fluid Height
      final meniscusRect = Rect.fromCenter(
        center: Offset(size.width / 2, baseWaterY),
        width: size.width * 0.94,
        height: 14,
      );
      final meniscusPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.75),
            primaryColor.withOpacity(0.8),
            primaryColor.withOpacity(0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(meniscusRect);
      canvas.drawOval(meniscusRect, meniscusPaint);

      // 5. Volumetric Rising Bubbles
      for (final bubble in bubbles) {
        final currentY = (bubble.y - (bubbleProgress * bubble.speed)) % 1.0;
        final actualY = baseWaterY + (currentY * waterHeight);
        final actualX = bubble.x * size.width + math.sin(bubbleProgress * 2 * math.pi + bubble.y * 10) * 6;

        if (actualY > baseWaterY && actualY < size.height) {
          final bubblePaint = Paint()
            ..color = Colors.white.withOpacity(bubble.opacity * 0.7)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(actualX, actualY), bubble.size, bubblePaint);

          final bubbleRim = Paint()
            ..color = glowColor.withOpacity(bubble.opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;
          canvas.drawCircle(Offset(actualX, actualY), bubble.size, bubbleRim);
        }
      }
    }

    // 6. Laser-Etched 3D Graduation Rings & Tick Marks
    final tickPaint = Paint()
      ..color = const Color(0xFF4A6595).withOpacity(0.5)
      ..strokeWidth = 1.5;

    final tickTextPainter = TextPainter(textDirection: TextDirection.ltr);

    final levels = [0.25, 0.50, 0.75, 1.0];
    for (final lvl in levels) {
      final y = size.height * (1.0 - lvl);
      // Graduation line across cylinder
      canvas.drawLine(Offset(12, y), Offset(28, y), tickPaint);
      canvas.drawLine(Offset(size.width - 28, y), Offset(size.width - 12, y), tickPaint);

      // Label
      tickTextPainter.text = TextSpan(
        text: '${(lvl * 100).toInt()}%',
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      );
      tickTextPainter.layout();
      tickTextPainter.paint(canvas, Offset(32, y - 5));
    }

    // 7. 3D Cylindrical Curved Glass Highlights & Reflections
    final glassReflectionPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withOpacity(0.28),
          Colors.white.withOpacity(0.04),
          Colors.transparent,
          Colors.white.withOpacity(0.12),
        ],
        stops: const [0.05, 0.22, 0.85, 0.98],
      ).createShader(rect);
    canvas.drawRect(rect, glassReflectionPaint);

    // 8. Outer Spatial Glass Border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.4),
          glowColor.withOpacity(0.7),
          const Color(0xFF1E293B),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, borderPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Spatial3DTankPainter oldDelegate) {
    return true;
  }
}
