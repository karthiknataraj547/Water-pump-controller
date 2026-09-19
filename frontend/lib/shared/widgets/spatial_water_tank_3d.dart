import 'dart:math' as math;
import 'package:flutter/material.dart';

class SpatialWaterTank3D extends StatefulWidget {
  final double levelPercentage; // 0.0 to 100.0
  final double height;
  final double? width;
  final bool isFilling;
  final double totalCapacityLiters;
  final bool showGestureTip;

  const SpatialWaterTank3D({
    Key? key,
    required this.levelPercentage,
    this.height = 240,
    this.width,
    this.isFilling = false,
    this.totalCapacityLiters = 5000.0,
    this.showGestureTip = true,
  }) : super(key: key);

  @override
  State<SpatialWaterTank3D> createState() => _SpatialWaterTank3DState();
}

class _SpatialWaterTank3DState extends State<SpatialWaterTank3D>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _bubbleController;
  late AnimationController _flowController;

  // Interactive 3D Spatial Tilt Angles
  double _tiltX = -0.05;
  double _tiltY = 0.03;
  double _targetTiltX = -0.05;
  double _targetTiltY = 0.03;

  final List<_Bubble> _bubbles = [];
  final List<_SplashDroplet> _splashDroplets = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    // Generate volumetric rising micro-bubbles
    for (int i = 0; i < 26; i++) {
      _bubbles.add(_Bubble(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 3.5 + 1.8,
        speed: _random.nextDouble() * 0.45 + 0.35,
        opacity: _random.nextDouble() * 0.5 + 0.3,
      ));
    }

    // Generate dynamic splash particles for water inflow impact
    for (int i = 0; i < 14; i++) {
      _splashDroplets.add(_SplashDroplet(
        angle: (_random.nextDouble() * math.pi) + math.pi, // upward semi-circle
        speed: _random.nextDouble() * 18 + 10,
        size: _random.nextDouble() * 2.8 + 1.2,
        phaseOffset: _random.nextDouble(),
      ));
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _bubbleController.dispose();
    _flowController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _targetTiltY += details.delta.dx * 0.003;
      _targetTiltX -= details.delta.dy * 0.003;
      _targetTiltX = _targetTiltX.clamp(-0.22, 0.22);
      _targetTiltY = _targetTiltY.clamp(-0.22, 0.22);
      _tiltX = _targetTiltX;
      _tiltY = _targetTiltY;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _targetTiltX = -0.05;
      _targetTiltY = 0.03;
    });
  }

  @override
  Widget build(BuildContext context) {
    final clampedLevel = widget.levelPercentage.clamp(0.0, 100.0);
    final currentLiters = (widget.totalCapacityLiters * (clampedLevel / 100.0)).round();

    // Fluid palette dynamically adapting to reservoir thresholds
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final renderWidth = widget.width ?? (constraints.maxWidth.isFinite ? constraints.maxWidth : 240.0);
        final renderHeight = widget.height;
        final isCompact = renderHeight < 250;

        return GestureDetector(
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: _tiltX, end: _targetTiltX),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              builder: (context, currentX, child) {
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0018)
                    ..rotateX(currentX)
                    ..rotateY(_tiltY),
                  child: Container(
                    width: renderWidth,
                    height: renderHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: fluidGlowColor.withOpacity(widget.isFilling ? 0.32 : 0.18),
                          blurRadius: widget.isFilling ? 32 : 22,
                          spreadRadius: widget.isFilling ? 3 : 1,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.55),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 1. 3D Spatial Cylinder, Inflow Pipe & Multi-Layer Wave Painter
                        AnimatedBuilder(
                          animation: Listenable.merge([_waveController, _bubbleController, _flowController]),
                          builder: (context, _) {
                            return CustomPaint(
                              size: Size(renderWidth, renderHeight),
                              painter: _Spatial3DTankPainter(
                                fillPct: clampedLevel / 100.0,
                                wavePhase: _waveController.value * 2 * math.pi,
                                bubbleProgress: _bubbleController.value,
                                flowProgress: _flowController.value,
                                primaryColor: primaryFluidColor,
                                secondaryColor: secondaryFluidColor,
                                glowColor: fluidGlowColor,
                                bubbles: _bubbles,
                                splashDroplets: _splashDroplets,
                                isFilling: widget.isFilling,
                              ),
                            );
                          },
                        ),

                        // 2. Holographic Cyber Telemetry Center Readout Badge
                        Positioned(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 12 : 16,
                              vertical: isCompact ? 6 : 9,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF090D1A).withOpacity(0.82),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: fluidGlowColor.withOpacity(widget.isFilling ? 0.75 : 0.45),
                                width: widget.isFilling ? 1.8 : 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: fluidGlowColor.withOpacity(widget.isFilling ? 0.35 : 0.15),
                                  blurRadius: 14,
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
                                        Icons.water_drop_rounded,
                                        color: primaryFluidColor,
                                        size: isCompact ? 13 : 15,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'PUMP INFLOW ACTIVE',
                                        style: TextStyle(
                                          color: primaryFluidColor,
                                          fontSize: isCompact ? 8.5 : 9.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: isCompact ? 1 : 2),
                                ],
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      clampedLevel.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isCompact ? 24 : 28,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.8,
                                        height: 1.0,
                                      ),
                                    ),
                                    Text(
                                      '%',
                                      style: TextStyle(
                                        color: primaryFluidColor,
                                        fontSize: isCompact ? 14 : 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: isCompact ? 1 : 2),
                                Text(
                                  '$currentLiters / ${widget.totalCapacityLiters.toInt()} L',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: isCompact ? 9.5 : 10.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // 3. Interactive Gesture Parallax Hint (if enabled)
                        if (widget.showGestureTip && !isCompact)
                          Positioned(
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.45),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.touch_app_rounded, color: Colors.white.withOpacity(0.45), size: 10),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Drag to rotate 3D tank',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.45),
                                      fontSize: 8.5,
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
      },
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

class _SplashDroplet {
  final double angle;
  final double speed;
  final double size;
  final double phaseOffset;

  _SplashDroplet({
    required this.angle,
    required this.speed,
    required this.size,
    required this.phaseOffset,
  });
}

class _Spatial3DTankPainter extends CustomPainter {
  final double fillPct;
  final double wavePhase;
  final double bubbleProgress;
  final double flowProgress;
  final Color primaryColor;
  final Color secondaryColor;
  final Color glowColor;
  final List<_Bubble> bubbles;
  final List<_SplashDroplet> splashDroplets;
  final bool isFilling;

  _Spatial3DTankPainter({
    required this.fillPct,
    required this.wavePhase,
    required this.bubbleProgress,
    required this.flowProgress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.glowColor,
    required this.bubbles,
    required this.splashDroplets,
    required this.isFilling,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(28));

    canvas.save();
    canvas.clipRRect(rrect);

    // 1. Cylindrical Glass Vessel Interior Gradient
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
    final inletX = size.width * 0.5;

    // 2. Active Water Flow Stream (Top Inlet Pipe Cascade)
    if (isFilling) {
      _paintWaterFlowStream(canvas, size, inletX, baseWaterY);
    }

    // 3. Fluid Body Waves (Back and Front Wave)
    if (fillPct > 0.005) {
      final waveTurbulence = isFilling ? 1.4 : 1.0;

      // Back Water Wave
      final backWavePath = Path();
      backWavePath.moveTo(0, size.height);
      backWavePath.lineTo(0, baseWaterY);

      for (double x = 0; x <= size.width; x += 4) {
        final normX = x / size.width;
        final waveY = baseWaterY +
            (math.sin(normX * 2 * math.pi + wavePhase * 0.8) * 6.0 * waveTurbulence) +
            (math.cos(normX * 4 * math.pi - wavePhase * 0.6) * 2.5 * waveTurbulence);
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
            secondaryColor.withOpacity(0.22),
          ],
        ).createShader(rect);
      canvas.drawPath(backWavePath, backWavePaint);

      // Front Water Wave
      final frontWavePath = Path();
      frontWavePath.moveTo(0, size.height);
      frontWavePath.lineTo(0, baseWaterY);

      for (double x = 0; x <= size.width; x += 4) {
        final normX = x / size.width;
        final waveY = baseWaterY +
            (math.sin(normX * 2 * math.pi - wavePhase) * 8.0 * waveTurbulence) +
            (math.sin(normX * 3.5 * math.pi + wavePhase * 1.3) * 3.5 * waveTurbulence);
        frontWavePath.lineTo(x, waveY);
      }
      frontWavePath.lineTo(size.width, size.height);
      frontWavePath.close();

      final frontWavePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            primaryColor.withOpacity(0.90),
            secondaryColor.withOpacity(0.92),
            const Color(0xFF001538),
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(rect);
      canvas.drawPath(frontWavePath, frontWavePaint);

      // 4. 3D Elliptical Meniscus Surface at Fluid Height
      final meniscusRect = Rect.fromCenter(
        center: Offset(size.width / 2, baseWaterY),
        width: size.width * 0.94,
        height: 12,
      );
      final meniscusPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.85),
            primaryColor.withOpacity(0.8),
            primaryColor.withOpacity(0.0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(meniscusRect);
      canvas.drawOval(meniscusRect, meniscusPaint);

      // 5. Water Inflow Surface Splash Ripples & Kinetic Particles
      if (isFilling) {
        _paintSplashImpact(canvas, size, inletX, baseWaterY);
      }

      // 6. Volumetric Rising Bubbles
      final bubbleSpeedMultiplier = isFilling ? 1.8 : 1.0;
      for (final bubble in bubbles) {
        final currentY = (bubble.y - (bubbleProgress * bubble.speed * bubbleSpeedMultiplier)) % 1.0;
        final actualY = baseWaterY + (currentY * waterHeight);
        final actualX = bubble.x * size.width + math.sin(bubbleProgress * 2 * math.pi + bubble.y * 8) * 5;

        if (actualY > baseWaterY && actualY < size.height) {
          final bubblePaint = Paint()
            ..color = Colors.white.withOpacity(bubble.opacity * 0.75)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(actualX, actualY), bubble.size, bubblePaint);

          final bubbleRim = Paint()
            ..color = glowColor.withOpacity(bubble.opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8;
          canvas.drawCircle(Offset(actualX, actualY), bubble.size, bubbleRim);
        }
      }
    }

    // 7. Top Water Inlet Pipe Hardware Fixture
    _paintInletPipeHardware(canvas, size, inletX);

    // 8. Laser-Etched 3D Graduation Rings & Tick Marks
    final tickPaint = Paint()
      ..color = const Color(0xFF4A6595).withOpacity(0.45)
      ..strokeWidth = 1.2;

    final tickTextPainter = TextPainter(textDirection: TextDirection.ltr);
    final levels = [0.25, 0.50, 0.75, 1.0];
    for (final lvl in levels) {
      final y = size.height * (1.0 - lvl);
      canvas.drawLine(Offset(10, y), Offset(22, y), tickPaint);
      canvas.drawLine(Offset(size.width - 22, y), Offset(size.width - 10, y), tickPaint);

      tickTextPainter.text = TextSpan(
        text: '${(lvl * 100).toInt()}%',
        style: TextStyle(
          color: Colors.white.withOpacity(0.38),
          fontSize: 7.5,
          fontWeight: FontWeight.bold,
        ),
      );
      tickTextPainter.layout();
      tickTextPainter.paint(canvas, Offset(26, y - 4.5));
    }

    // 9. 3D Cylindrical Curved Glass Highlights & Reflections
    final glassReflectionPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withOpacity(0.24),
          Colors.white.withOpacity(0.03),
          Colors.transparent,
          Colors.white.withOpacity(0.10),
        ],
        stops: const [0.04, 0.20, 0.85, 0.98],
      ).createShader(rect);
    canvas.drawRect(rect, glassReflectionPaint);

    // 10. Outer Spatial Vessel Rim
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.35),
          glowColor.withOpacity(isFilling ? 0.75 : 0.45),
          const Color(0xFF1E293B),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, borderPaint);

    canvas.restore();
  }

  void _paintInletPipeHardware(Canvas canvas, Size size, double inletX) {
    const pipeWidth = 22.0;
    const pipeHeight = 16.0;
    final pipeRect = Rect.fromLTWH(inletX - (pipeWidth / 2), 0, pipeWidth, pipeHeight);

    // Chrome pipe gradient
    final pipePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF64748B),
          Color(0xFFE2E8F0),
          Color(0xFF94A3B8),
          Color(0xFF334155),
        ],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(pipeRect);

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        pipeRect,
        bottomLeft: const Radius.circular(5),
        bottomRight: const Radius.circular(5),
      ),
      pipePaint,
    );

    // Flange nozzle rim
    final nozzleRect = Rect.fromLTWH(inletX - 13, pipeHeight - 3, 26, 4);
    final nozzlePaint = Paint()..color = const Color(0xFFCBD5E1);
    canvas.drawRRect(RRect.fromRectAndRadius(nozzleRect, const Radius.circular(2)), nozzlePaint);

    if (isFilling) {
      // Glowing active water orifice
      final glowOrifice = Paint()
        ..color = primaryColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawOval(Rect.fromLTWH(inletX - 8, pipeHeight - 2, 16, 4), glowOrifice);
    }
  }

  void _paintWaterFlowStream(Canvas canvas, Size size, double inletX, double baseWaterY) {
    const startY = 16.0;
    final endY = math.max(startY, baseWaterY);
    if (endY <= startY) return;

    final streamPath = Path();
    const streamHalfWidth = 6.5;

    // Stream outer contour with fluid velocity oscillation
    streamPath.moveTo(inletX - streamHalfWidth, startY);

    for (double y = startY; y <= endY; y += 4) {
      final normY = (y - startY) / (endY - startY);
      final wave = math.sin((normY * 4 * math.pi) - (flowProgress * 2 * math.pi)) * 1.8;
      // Stream expands slightly as it falls
      final currentWidth = streamHalfWidth + (normY * 3.0);
      streamPath.lineTo(inletX - currentWidth + wave, y);
    }

    for (double y = endY; y >= startY; y -= 4) {
      final normY = (y - startY) / (endY - startY);
      final wave = math.sin((normY * 4 * math.pi) - (flowProgress * 2 * math.pi)) * 1.8;
      final currentWidth = streamHalfWidth + (normY * 3.0);
      streamPath.lineTo(inletX + currentWidth + wave, y);
    }

    streamPath.close();

    // Vibrant cascading fluid gradient with bright translucent core
    final streamShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        primaryColor.withOpacity(0.95),
        primaryColor.withOpacity(0.85),
        secondaryColor.withOpacity(0.95),
      ],
    ).createShader(Rect.fromLTRB(inletX - 12, startY, inletX + 12, endY));

    final streamPaint = Paint()
      ..shader = streamShader
      ..style = PaintingStyle.fill;
    canvas.drawPath(streamPath, streamPaint);

    // Inner bright water core
    final corePaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(inletX, startY), Offset(inletX, endY), corePaint);

    // Dynamic flowing droplets falling down the stream
    for (int i = 0; i < 5; i++) {
      final dropY = startY + (((flowProgress + (i * 0.2)) % 1.0) * (endY - startY));
      final dropPaint = Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(inletX, dropY), 2.2, dropPaint);
    }
  }

  void _paintSplashImpact(Canvas canvas, Size size, double inletX, double baseWaterY) {
    // 1. Concentric ripple rings expanding on the water surface
    for (int i = 0; i < 3; i++) {
      final rippleProgress = ((flowProgress + (i * 0.33)) % 1.0);
      final rippleWidth = 14.0 + (rippleProgress * 44.0);
      final rippleHeight = 4.0 + (rippleProgress * 8.0);
      final rippleOpacity = (1.0 - rippleProgress).clamp(0.0, 1.0) * 0.65;

      final ripplePaint = Paint()
        ..color = primaryColor.withOpacity(rippleOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(inletX, baseWaterY),
          width: rippleWidth,
          height: rippleHeight,
        ),
        ripplePaint,
      );
    }

    // 2. Kinetic Splash Droplets flying upwards from impact point
    for (final droplet in splashDroplets) {
      final p = (flowProgress + droplet.phaseOffset) % 1.0;
      final dx = math.cos(droplet.angle) * droplet.speed * p;
      // Parabolic ballistic arc: dy = speed*sin(a)*p + gravity*p^2
      final dy = (math.sin(droplet.angle) * droplet.speed * p) + (14.0 * p * p);
      final opacity = (1.0 - p).clamp(0.0, 1.0) * 0.8;

      final splashPaint = Paint()
        ..color = Colors.white.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(inletX + dx, baseWaterY + dy), droplet.size, splashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _Spatial3DTankPainter oldDelegate) {
    return true;
  }
}
