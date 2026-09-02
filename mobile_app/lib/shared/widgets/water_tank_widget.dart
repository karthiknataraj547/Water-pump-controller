import 'dart:math';
import 'package:flutter/material.dart';

class WaterTankWidget extends StatefulWidget {
  final double levelPercentage; // 0.0 to 100.0
  final double height;
  final double width;
  final bool isFilling;

  const WaterTankWidget({
    Key? key,
    required this.levelPercentage,
    this.height = 280,
    this.width = 200,
    this.isFilling = false,
  }) : super(key: key);

  @override
  State<WaterTankWidget> createState() => _WaterTankWidgetState();
}

class _WaterTankWidgetState extends State<WaterTankWidget> with SingleTickerProviderStateMixin {
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clampedLevel = widget.levelPercentage.clamp(0.0, 100.0) / 100.0;

    Color waveColor = const Color(0xFF00D2FF);
    Color waveGradientBottom = const Color(0xFF0072FF);

    if (widget.levelPercentage <= 15) {
      waveColor = const Color(0xFFF59E0B);
      waveGradientBottom = const Color(0xFFD97706);
    } else if (widget.levelPercentage >= 95) {
      waveColor = const Color(0xFF10B981);
      waveGradientBottom = const Color(0xFF059669);
    }

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E).withOpacity(0.8),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0xFF2B3A60), width: 2),
        boxShadow: [
          BoxShadow(
            color: waveColor.withOpacity(0.15),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Wave animation canvas
            AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return CustomPaint(
                  size: Size(widget.width, widget.height),
                  painter: _WavePainter(
                    waveAnimation: _waveController.value,
                    fillPercentage: clampedLevel,
                    topColor: waveColor,
                    bottomColor: waveGradientBottom,
                  ),
                );
              },
            ),

            // Level percentage and indicator readout
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isFilling) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        'FILLING',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  '${widget.levelPercentage.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getLevelDescriptor(widget.levelPercentage),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getLevelDescriptor(double pct) {
    if (pct < 10) return 'Empty';
    if (pct <= 30) return 'Low Level';
    if (pct <= 70) return 'Half Full';
    if (pct <= 90) return 'Optimal Level';
    return 'Full Capacity';
  }
}

class _WavePainter extends CustomPainter {
  final double waveAnimation;
  final double fillPercentage;
  final Color topColor;
  final Color bottomColor;

  _WavePainter({
    required this.waveAnimation,
    required this.fillPercentage,
    required this.topColor,
    required this.bottomColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fillPercentage <= 0.001) return;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: [topColor.withOpacity(0.85), bottomColor.withOpacity(0.95)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final waterHeight = size.height * fillPercentage;
    final baseHeight = size.height - waterHeight;

    const waveFrequency = 1.5;
    const waveAmplitude = 8.0;

    path.moveTo(0, size.height);
    path.lineTo(0, baseHeight);

    for (double x = 0; x <= size.width; x++) {
      final y = baseHeight +
          sin((x / size.width * 2 * pi * waveFrequency) + (waveAnimation * 2 * pi)) * waveAmplitude;
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.waveAnimation != waveAnimation ||
        oldDelegate.fillPercentage != fillPercentage ||
        oldDelegate.topColor != topColor;
  }
}
