import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SpatialPumpVisualizer3D extends StatefulWidget {
  final bool isRunning;
  final double flowRateLpm;
  final double powerWatts;
  final String mode;
  final VoidCallback onToggle;
  final ValueChanged<String>? onModeChanged;

  const SpatialPumpVisualizer3D({
    Key? key,
    required this.isRunning,
    this.flowRateLpm = 0.0,
    this.powerWatts = 0.0,
    this.mode = 'AUTO',
    required this.onToggle,
    this.onModeChanged,
  }) : super(key: key);

  @override
  State<SpatialPumpVisualizer3D> createState() => _SpatialPumpVisualizer3DState();
}

class _SpatialPumpVisualizer3DState extends State<SpatialPumpVisualizer3D>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (widget.isRunning) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SpatialPumpVisualizer3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning != oldWidget.isRunning) {
      if (widget.isRunning) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isRunning ? const Color(0xFF00E5FF) : const Color(0xFF64748B);
    final glowColor = widget.isRunning ? const Color(0xFF00E5FF) : Colors.transparent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1426).withOpacity(0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: (widget.isRunning ? const Color(0xFF00E5FF) : const Color(0xFF1E293B)).withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (widget.isRunning ? const Color(0xFF00E5FF) : Colors.black).withOpacity(widget.isRunning ? 0.15 : 0.4),
            blurRadius: 28,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header & Live Mode Tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isRunning ? const Color(0xFF00E5FF) : const Color(0xFF94A3B8),
                      boxShadow: widget.isRunning
                          ? [
                              const BoxShadow(
                                color: Color(0xFF00E5FF),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'MOTOR CONTROL',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (widget.isRunning ? const Color(0xFF00E5FF) : Colors.grey).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (widget.isRunning ? const Color(0xFF00E5FF) : Colors.grey).withOpacity(0.35),
                  ),
                ),
                child: Text(
                  widget.isRunning ? 'ACTIVE • RUNNING' : 'STANDBY',
                  style: TextStyle(
                    color: widget.isRunning ? const Color(0xFF00E5FF) : Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 2. 3-Way Mode Segmented Selector Inside Motor Control Card
          _buildModeSelector(),

          const SizedBox(height: 18),

          // 3. 3D Spatial Turbine & Pipeflow Visualizer Stage
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 3D Isometric Turbine Assembly
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.002)
                  ..rotateX(-0.1)
                  ..rotateY(0.08),
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0xFF1E293B),
                        Color(0xFF0F172A),
                        Color(0xFF020617),
                      ],
                    ),
                    border: Border.all(
                      color: activeColor.withOpacity(0.5),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Tachometer tick marks
                      CustomPaint(
                        size: const Size(130, 130),
                        painter: _TachometerDialPainter(
                          isActive: widget.isRunning,
                          accentColor: activeColor,
                        ),
                      ),
                      // Rotating Multi-Blade Impeller
                      AnimatedBuilder(
                        animation: _rotationController,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _rotationController.value * 2 * math.pi,
                            child: child,
                          );
                        },
                        child: CustomPaint(
                          size: const Size(90, 90),
                          painter: _ImpellerBladesPainter(
                            color: activeColor,
                            isRunning: widget.isRunning,
                          ),
                        ),
                      ),
                      // Central Bearing Hub
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0F172A),
                          border: Border.all(
                            color: activeColor,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: glowColor.withOpacity(0.6),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // Dynamic Flow Metrics Panel
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTelemetryRow(
                      icon: Icons.speed_rounded,
                      label: 'FLOW RATE',
                      value: '${widget.flowRateLpm.toStringAsFixed(1)} L/m',
                      color: const Color(0xFF00E5FF),
                    ),
                    const SizedBox(height: 10),
                    _buildTelemetryRow(
                      icon: Icons.bolt_rounded,
                      label: 'POWER DRAW',
                      value: '${widget.powerWatts.toStringAsFixed(0)} W',
                      color: const Color(0xFFFFD600),
                    ),
                    const SizedBox(height: 10),
                    _buildTelemetryRow(
                      icon: Icons.sync_alt_rounded,
                      label: 'TURBINE SPEED',
                      value: widget.isRunning ? '2,850 RPM' : '0 RPM',
                      color: const Color(0xFF00E676),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 4. Tactile 3D Power Control Button (STOP / START PUMP)
          GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) {
              setState(() => _isPressed = false);
              widget.onToggle();
            },
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.96 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isRunning
                        ? [const Color(0xFFFF1744), const Color(0xFFD50000)]
                        : [const Color(0xFF00E5FF), const Color(0xFF0072FF)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: (widget.isRunning ? const Color(0xFFFF1744) : const Color(0xFF00E5FF)).withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.isRunning ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isRunning ? 'STOP WATER PUMP' : 'START WATER PUMP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    final modes = [
      {'key': 'AUTO', 'label': 'Automatic', 'icon': Icons.auto_mode_rounded},
      {'key': 'MANUAL', 'label': 'Manual', 'icon': Icons.touch_app_rounded},
      {'key': 'SCHEDULE', 'label': 'Schedules', 'icon': Icons.schedule_rounded},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF050B17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2)),
      ),
      child: Row(
        children: modes.map((m) {
          final isSelected = widget.mode.toUpperCase() == m['key'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (widget.onModeChanged != null) {
                  widget.onModeChanged!(m['key'] as String);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF0284C7)],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      m['icon'] as IconData,
                      size: 14,
                      color: isSelected ? Colors.black : Colors.white.withOpacity(0.6),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      m['label'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                        color: isSelected ? Colors.black : Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTelemetryRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF070D1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TachometerDialPainter extends CustomPainter {
  final bool isActive;
  final Color accentColor;

  _TachometerDialPainter({required this.isActive, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final tickPaint = Paint()
      ..color = (isActive ? accentColor : Colors.white24).withOpacity(0.4)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 24; i++) {
      final angle = (i * 15) * math.pi / 180;
      final isMajor = i % 6 == 0;
      final innerRadius = isMajor ? radius - 8 : radius - 4;
      final p1 = Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      final p2 = Offset(center.dx + innerRadius * math.cos(angle), center.dy + innerRadius * math.sin(angle));
      canvas.drawLine(p1, p2, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TachometerDialPainter oldDelegate) {
    return oldDelegate.isActive != isActive || oldDelegate.accentColor != accentColor;
  }
}

class _ImpellerBladesPainter extends CustomPainter {
  final Color color;
  final bool isRunning;

  _ImpellerBladesPainter({required this.color, required this.isRunning});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bladePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = color.withOpacity(isRunning ? 0.35 : 0.0)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    for (int i = 0; i < 4; i++) {
      final angle = (i * 90) * math.pi / 180;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(12, -22, 6, -38)
        ..quadraticBezierTo(0, -42, -6, -38)
        ..quadraticBezierTo(-12, -22, 0, 0)
        ..close();

      if (isRunning) {
        canvas.drawPath(path, glowPaint);
      }
      canvas.drawPath(path, bladePaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ImpellerBladesPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isRunning != isRunning;
  }
}
