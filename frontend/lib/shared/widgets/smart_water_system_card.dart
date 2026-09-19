import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/hardware/hardware_state_service.dart';
import 'spatial_water_tank_3d.dart';

class SmartWaterSystemCard extends StatefulWidget {
  final double waterLevelPct;
  final double waterVolumeLiters;
  final double totalCapacityLiters;
  final bool isPumpRunning;
  final String mode; // 'AUTO' or 'MANUAL'
  final NodeStatus mainNodeStatus;
  final NodeStatus subNodeStatus;
  final SystemHealth systemHealth;
  final CommandTransitState commandState;
  final VoidCallback onTogglePump;
  final ValueChanged<String> onModeChanged;
  final VoidCallback? onEmergencyStop;
  final double? powerKw;
  final int? runTimeSeconds;
  final int? cycleCount;

  const SmartWaterSystemCard({
    Key? key,
    required this.waterLevelPct,
    this.waterVolumeLiters = 0.0,
    this.totalCapacityLiters = 5000.0,
    required this.isPumpRunning,
    this.mode = 'AUTO',
    this.mainNodeStatus = NodeStatus.offline,
    this.subNodeStatus = NodeStatus.offline,
    this.systemHealth = SystemHealth.offline,
    this.commandState = CommandTransitState.idle,
    required this.onTogglePump,
    required this.onModeChanged,
    this.onEmergencyStop,
    this.powerKw,
    this.runTimeSeconds,
    this.cycleCount,
  }) : super(key: key);

  @override
  State<SmartWaterSystemCard> createState() => _SmartWaterSystemCardState();
}

class _SmartWaterSystemCardState extends State<SmartWaterSystemCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  bool _show3DTank = true;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;

    final isAuto = widget.mode.toUpperCase() == 'AUTO';
    final isOnline = widget.mainNodeStatus != NodeStatus.offline;
    final isSubOnline = widget.subNodeStatus != NodeStatus.offline;

    final clampedPct = widget.waterLevelPct.clamp(0.0, 100.0);
    final volume = widget.waterVolumeLiters > 0
        ? widget.waterVolumeLiters
        : (clampedPct / 100.0 * widget.totalCapacityLiters);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP TELEMETRY STATUS BAR
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isOnline ? AppTheme.accent : AppTheme.danger).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (isOnline ? AppTheme.accent : AppTheme.danger).withOpacity(0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isOnline ? AppTheme.accent : AppTheme.danger,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isOnline ? 'GATEWAY LIVE' : 'GATEWAY OFFLINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isOnline ? AppTheme.accent : AppTheme.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isSubOnline ? AppTheme.primary : AppTheme.slate).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (isSubOnline ? AppTheme.primary : AppTheme.slate).withOpacity(0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSubOnline ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                            size: 11,
                            color: isSubOnline ? AppTheme.primary : AppTheme.slate,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSubOnline ? 'TANK SENSOR LIVE' : 'TANK SENSOR OFFLINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: isSubOnline ? AppTheme.primary : AppTheme.slate,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _show3DTank = !_show3DTank),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _show3DTank
                              ? AppTheme.primary.withOpacity(0.16)
                              : (isDark ? const Color(0xFF0B111E) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _show3DTank ? AppTheme.primary.withOpacity(0.5) : Colors.transparent,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _show3DTank ? Icons.view_in_ar_rounded : Icons.grid_view_rounded,
                              size: 11,
                              color: _show3DTank
                                  ? AppTheme.primary
                                  : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _show3DTank ? '3D TANK' : '2D GRID',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: _show3DTank
                                    ? AppTheme.primary
                                    : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        final newMode = isAuto ? 'MANUAL' : 'AUTO';
                        widget.onModeChanged(newMode);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isAuto
                              ? AppTheme.primary.withOpacity(0.14)
                              : AppTheme.accent.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isAuto
                                ? AppTheme.primary.withOpacity(0.4)
                                : AppTheme.accent.withOpacity(0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAuto ? Icons.autorenew_rounded : Icons.touch_app_rounded,
                              size: 11,
                              color: isAuto ? AppTheme.primary : AppTheme.accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isAuto ? 'MODE: AUTO' : 'MODE: MANUAL',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: isAuto ? AppTheme.primary : AppTheme.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Divider(color: cardBorder, height: 1),

          // 2. PRECISION VOLUMETRIC RESERVOIR GAUGE
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: SizedBox(
              height: 220,
              child: Row(
                children: [
                  // Calibrated Reservoir Cross-Section Tank (3D Spatial or 2D Analytic)
                  Expanded(
                    flex: 5,
                    child: _show3DTank
                        ? SpatialWaterTank3D(
                            levelPercentage: clampedPct,
                            height: 220,
                            isFilling: widget.isPumpRunning,
                            totalCapacityLiters: widget.totalCapacityLiters,
                            showGestureTip: true,
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF090E17) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
                                width: 1.0,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              children: [
                                // Background Grid & Metric Graduations
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _ReservoirTicksPainter(
                                      isDark: isDark,
                                      maxCapacity: widget.totalCapacityLiters,
                                    ),
                                  ),
                                ),

                                // Animated Fluid Body
                                AnimatedBuilder(
                                  animation: _waveController,
                                  builder: (context, _) {
                                    return CustomPaint(
                                      size: Size.infinite,
                                      painter: _FluidReservoirPainter(
                                        fillPct: clampedPct / 100.0,
                                        waveProgress: _waveController.value,
                                        isPumpRunning: widget.isPumpRunning,
                                        isDark: isDark,
                                      ),
                                    );
                                  },
                                ),

                                // Threshold Markers Overlay (Auto-Stop 95%, Auto-Start 25%)
                                Positioned(
                                  top: 220 * 0.05,
                                  left: 0,
                                  right: 0,
                                  child: _buildThresholdMarker('95% AUTO-STOP', AppTheme.accent, isDark),
                                ),
                                Positioned(
                                  top: 220 * 0.75,
                                  left: 0,
                                  right: 0,
                                  child: _buildThresholdMarker('25% AUTO-START', AppTheme.warning, isDark),
                                ),

                                // Center Volume Telemetry Display
                                Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: (isDark ? const Color(0xFF0B1220) : Colors.white).withOpacity(0.82),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: (isDark ? Colors.white : Colors.black).withOpacity(0.12),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${clampedPct.toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.8,
                                                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                            Text(
                                              '${volume.toStringAsFixed(0)} / ${widget.totalCapacityLiters.toStringAsFixed(0)} L',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  const SizedBox(width: 16),

                  // Reservoir Side Telemetry Legend
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSideMetric(
                          'CAPACITY',
                          '${widget.totalCapacityLiters.toStringAsFixed(0)} L',
                          'Total Tank Volume',
                          Icons.inventory_2_outlined,
                          AppTheme.primary,
                          isDark,
                          textTheme,
                        ),
                        _buildSideMetric(
                          'PUMP FLOW',
                          widget.isPumpRunning ? '18.5 L/min' : '0.0 L/min',
                          widget.isPumpRunning ? 'Actuator Pumping' : 'Actuator Idle',
                          Icons.speed_rounded,
                          widget.isPumpRunning ? AppTheme.accent : AppTheme.slate,
                          isDark,
                          textTheme,
                        ),
                        _buildSideMetric(
                          'HEAD PRESSURE',
                          widget.isPumpRunning ? '2.4 bar' : '0.0 bar',
                          'Operating Line Pressure',
                          Icons.compress_rounded,
                          AppTheme.primaryLight,
                          isDark,
                          textTheme,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Divider(color: cardBorder, height: 1),

          // 3. INDUSTRIAL ACTUATOR CONTROL DECK
          Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mode Selector Segmented Deck
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0B111E) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cardBorder, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onModeChanged('AUTO');
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isAuto
                                        ? (isDark ? AppTheme.darkCard : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: isAuto
                                        ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 1))]
                                        : null,
                                  ),
                                  child: Text(
                                    'AUTO (Sensor Rules)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isAuto ? FontWeight.w700 : FontWeight.w500,
                                      color: isAuto
                                          ? (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)
                                          : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onModeChanged('MANUAL');
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: !isAuto
                                        ? (isDark ? AppTheme.darkCard : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: !isAuto
                                        ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 1))]
                                        : null,
                                  ),
                                  child: Text(
                                    'MANUAL (Override)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: !isAuto ? FontWeight.w700 : FontWeight.w500,
                                      color: !isAuto
                                          ? (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)
                                          : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Heavy-Duty Actuator Trigger Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.isPumpRunning ? AppTheme.danger : AppTheme.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: widget.isPumpRunning ? 4 : 0,
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      if (isAuto && !widget.isPumpRunning) {
                        widget.onModeChanged('MANUAL');
                      }
                      widget.onTogglePump();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.isPumpRunning ? Icons.stop_circle_rounded : Icons.play_circle_filled_rounded,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isPumpRunning ? 'STOP PUMP ACTUATOR' : 'START PUMP ACTUATOR',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.4),
                            ),
                            Text(
                              widget.isPumpRunning
                                  ? 'Active pumping: 18.5 L/min'
                                  : (isAuto ? 'Manual override · Tap to start' : 'Standby · Instant command dispatch'),
                              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThresholdMarker(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: color.withOpacity(0.5))),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: Container(height: 1, color: color.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildSideMetric(
    String label,
    String value,
    String subtitle,
    IconData icon,
    Color accent,
    bool isDark,
    TextTheme textTheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090E17) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _ReservoirTicksPainter extends CustomPainter {
  final bool isDark;
  final double maxCapacity;

  _ReservoirTicksPainter({required this.isDark, required this.maxCapacity});

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.08)
      ..strokeWidth = 1.0;

    // Draw 4 horizontal grid lines
    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReservoirTicksPainter oldDelegate) => false;
}

class _FluidReservoirPainter extends CustomPainter {
  final double fillPct;
  final double waveProgress;
  final bool isPumpRunning;
  final bool isDark;

  _FluidReservoirPainter({
    required this.fillPct,
    required this.waveProgress,
    required this.isPumpRunning,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fillPct <= 0.001) return;

    final fluidTopY = size.height * (1.0 - fillPct);
    final waveAmplitude = isPumpRunning ? 4.0 : 2.0;

    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, fluidTopY);

    for (double x = 0; x <= size.width; x += 4) {
      final waveOffset = math.sin((x / size.width * 2 * math.pi) + (waveProgress * 2 * math.pi));
      final y = fluidTopY + (waveOffset * waveAmplitude);
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    final fluidGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [const Color(0xFF0284C7).withOpacity(0.75), const Color(0xFF0369A1).withOpacity(0.9)]
          : [const Color(0xFF38BDF8).withOpacity(0.85), const Color(0xFF0284C7).withOpacity(0.95)],
    );

    final paint = Paint()
      ..shader = fluidGradient.createShader(Rect.fromLTWH(0, fluidTopY, size.width, size.height - fluidTopY))
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // Meniscus Highlight Line
    final meniscusPaint = Paint()
      ..color = Colors.white.withOpacity(isDark ? 0.35 : 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final meniscusPath = Path();
    meniscusPath.moveTo(0, fluidTopY);
    for (double x = 0; x <= size.width; x += 4) {
      final waveOffset = math.sin((x / size.width * 2 * math.pi) + (waveProgress * 2 * math.pi));
      final y = fluidTopY + (waveOffset * waveAmplitude);
      meniscusPath.lineTo(x, y);
    }
    canvas.drawPath(meniscusPath, meniscusPaint);
  }

  @override
  bool shouldRepaint(covariant _FluidReservoirPainter oldDelegate) {
    return oldDelegate.fillPct != fillPct ||
        oldDelegate.waveProgress != waveProgress ||
        oldDelegate.isPumpRunning != isPumpRunning ||
        oldDelegate.isDark != isDark;
  }
}
