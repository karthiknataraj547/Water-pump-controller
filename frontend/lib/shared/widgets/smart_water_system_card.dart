import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/hardware/hardware_state_service.dart';
import 'animated_pressable.dart';

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
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _ambientController;
  late AnimationController _waveController;
  late AnimationController _impellerController;
  late AnimationController _pipeFlowController;
  late AnimationController _cascadeController;
  late AnimationController _splashController;
  late AnimationController _pulseController;

  // 3D 360° Rotatable Solid Tank (Continuous 360° Horizontal Orbit)
  double _tankRotY = 0.0;
  final double _tankRotX = -0.05; // Isometric perspective angle
  bool _isDraggingTank = false;

  @override
  void initState() {
    super.initState();

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _impellerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _pipeFlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    _cascadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _splashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 580),
    );

    if (widget.isPumpRunning) {
      _startPumpingAnimations();
    }
  }

  void _startPumpingAnimations() {
    _impellerController.repeat();
    _pipeFlowController.repeat();
    _cascadeController.repeat();
    _splashController.repeat();
  }

  void _stopPumpingAnimations() {
    _impellerController.stop();
    _pipeFlowController.stop();
    _cascadeController.stop();
    _splashController.stop();
  }

  @override
  void didUpdateWidget(covariant SmartWaterSystemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPumpRunning != oldWidget.isPumpRunning) {
      if (widget.isPumpRunning) {
        _startPumpingAnimations();
      } else {
        _stopPumpingAnimations();
      }
    }
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _waveController.dispose();
    _pulseController.dispose();
    _impellerController.dispose();
    _pipeFlowController.dispose();
    _cascadeController.dispose();
    _splashController.dispose();
    super.dispose();
  }

  void _onTankHorizontalPanUpdate(DragUpdateDetails details) {
    setState(() {
      _isDraggingTank = true;
      // Smooth continuous 360° horizontal rotation
      _tankRotY = (_tankRotY + details.delta.dx * 0.012);
    });
  }

  void _onTankHorizontalPanEnd(DragEndDetails details) {
    setState(() {
      _isDraggingTank = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.mainNodeStatus != NodeStatus.offline;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ==================================================================
          // 1. HEADER: STATUS & TITLE
          // ==================================================================
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? AppTheme.accent : AppTheme.danger,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Pump Control',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ==================================================================
          // 2. 3D INTEGRATED VIEWPORT: SOLID CYLINDER + FIXED MOTOR & PIPE + CASCADE
          // ==================================================================
          Container(
            height: 335,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D0D1A) : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppTheme.darkCardBorder : const Color(0xFF334155),
                width: 0.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Stack(
                children: [
                  // A. Static Ground Perspective Stage Layer
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _StaticGroundStagePainter(isRunning: widget.isPumpRunning),
                    ),
                  ),

                  // B. SOLID 3D ROTATABLE CYLINDRICAL TANK (Only the Tank Rotates 360° on Horizontal Pan)
                  Positioned(
                    left: 10,
                    top: 12,
                    child: GestureDetector(
                      onHorizontalDragUpdate: _onTankHorizontalPanUpdate,
                      onHorizontalDragEnd: _onTankHorizontalPanEnd,
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _waveController,
                          _ambientController,
                          _splashController,
                        ]),
                        builder: (context, child) {
                          final floatY = _isDraggingTank
                              ? 0.0
                              : math.sin(_ambientController.value * 2 * math.pi) * 0.012;
                          final matrix = Matrix4.identity()
                            ..setEntry(3, 2, 0.0015)
                            ..rotateX(_tankRotX + floatY);

                          return Transform(
                            alignment: FractionalOffset.center,
                            transform: matrix,
                            child: SizedBox(
                              width: 200,
                              height: 260,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CustomPaint(
                                    size: const Size(200, 260),
                                    painter: _Solid3DVolumetricTankPainter(
                                      waterLevelPct: widget.waterLevelPct.clamp(0.0, 100.0),
                                      isPumpRunning: widget.isPumpRunning,
                                      wavePhase: _waveController.value * 2 * math.pi,
                                      splashPhase: _splashController.value,
                                      rotY: _tankRotY,
                                    ),
                                  ),
                                  // Floating Level HUD in Center of Tank
                                  Positioned(
                                    top: 26,
                                    child: _buildTankHudBadge(),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // C. CONSTANT / FIXED PIPE & MOTOR & WATERFALL CASCADE LAYER
                  // (Fixed layer: stationary motor, arched pipe to tank top, waterfall cascade pouring in)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _pipeFlowController,
                          _impellerController,
                          _cascadeController,
                          _splashController,
                        ]),
                        builder: (context, child) {
                          return CustomPaint(
                            painter: _FixedPipeMotorAndCascadePainter(
                              isPumpRunning: widget.isPumpRunning,
                              pipeFlowPhase: _pipeFlowController.value,
                              impellerAngle: _impellerController.value * 2 * math.pi,
                              cascadePhase: _cascadeController.value,
                              splashPhase: _splashController.value,
                              waterLevelPct: widget.waterLevelPct.clamp(0.0, 100.0),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // ==================================================================
          // 3. OPERATIONAL MODE SWITCHER [ AUTOMATIC | MANUAL ] WITH ANIMATIONS
          // ==================================================================
          _buildModeSelector(isOnline),

          const SizedBox(height: 16),

          // ==================================================================
          // 4. SINGLE MORPHING ACTION BUTTON (START <-> STOP) WITH TACTILE BOUNCE
          // ==================================================================
          _buildMergedActionButton(isOnline),

          const SizedBox(height: 10),

          // ==================================================================
          // 5. HIGH-PRIORITY EMERGENCY STOP (WORKS IN AUTO & MANUAL)
          // ==================================================================
          _buildEmergencyStopButton(),

          const SizedBox(height: 14),

          // ==================================================================
          // 6. HYDRO SYSTEM REAL-TIME STATS: POWER, RUNTIME, CYCLES
          // ==================================================================
          _buildHydroSystemStatsBar(),

          const SizedBox(height: 4),

          Center(
            child: Text(
              '3D Engine · Authoritative Hardware Telemetry',
              style: textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTankHudBadge() {
    final clampedPct = widget.waterLevelPct.clamp(0.0, 100.0);
    final volume = (clampedPct / 100.0) * widget.totalCapacityLiters;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A).withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.waterBlueDark.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${clampedPct.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: AppTheme.waterBlueDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          Text(
            '${volume.toStringAsFixed(0)} / ${widget.totalCapacityLiters.toStringAsFixed(0)} L',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(bool isOnline) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: AnimatedPressable(
              onTap: () {
                if (!isOnline) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      duration: Duration(seconds: 2),
                      backgroundColor: Color(0xFFE11D48),
                      content: Text(
                        '⚠️ Hardware Offline • Mode selection locked until ESP32 reconnects.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                  return;
                }
                widget.onModeChanged('AUTO');
              },
              pressedScale: 0.97,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                decoration: BoxDecoration(
                  color: widget.mode == 'AUTO'
                      ? colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: widget.mode == 'AUTO'
                          ? Colors.white
                          : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                    ),
                    const SizedBox(width: 6),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        color: widget.mode == 'AUTO'
                            ? Colors.white
                            : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                        fontSize: 12,
                        fontWeight: widget.mode == 'AUTO' ? FontWeight.w700 : FontWeight.w500,
                      ),
                      child: const Text('AUTOMATIC'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: AnimatedPressable(
              onTap: () {
                if (!isOnline) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      duration: Duration(seconds: 2),
                      backgroundColor: Color(0xFFE11D48),
                      content: Text(
                        '⚠️ Hardware Offline • Mode selection locked until ESP32 reconnects.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                  return;
                }
                widget.onModeChanged('MANUAL');
              },
              pressedScale: 0.97,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                decoration: BoxDecoration(
                  color: widget.mode == 'MANUAL'
                      ? colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 14,
                      color: widget.mode == 'MANUAL'
                          ? Colors.white
                          : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                    ),
                    const SizedBox(width: 6),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        color: widget.mode == 'MANUAL'
                            ? Colors.white
                            : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                        fontSize: 12,
                        fontWeight: widget.mode == 'MANUAL' ? FontWeight.w700 : FontWeight.w500,
                      ),
                      child: const Text('MANUAL'),
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

  Widget _buildMergedActionButton(bool isOnline) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAuto = widget.mode == 'AUTO';

    if (!isOnline) {
      return AnimatedPressable(
        onTap: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFFE11D48),
              content: Text(
                '🔒 Hardware Offline • Connect ESP32 to operate pump motor.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          );
        },
        pressedScale: 0.98,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B).withOpacity(0.5) : const Color(0xFFE2E8F0).withOpacity(0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'HARDWARE OFFLINE • CONTROL LOCKED',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isAuto) {
      // In AUTO mode, manual button is disabled/interlocked with clear status
      return AnimatedPressable(
        onTap: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 2),
              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF334155),
              content: const Text(
                '⚡ Pump is governed by Autonomous Rules. Switch to MANUAL mode for direct control.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          );
        },
        pressedScale: 0.98,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: widget.isPumpRunning
                ? (isDark ? const Color(0xFF064E3B).withOpacity(0.4) : const Color(0xFFD1FAE5))
                : (isDark ? const Color(0xFF1E293B).withOpacity(0.6) : const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isPumpRunning
                  ? AppTheme.accentEmerald.withOpacity(0.4)
                  : (isDark ? Colors.white10 : Colors.black12),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isPumpRunning ? Icons.sync_rounded : Icons.lock_outline_rounded,
                color: widget.isPumpRunning
                    ? AppTheme.accentEmerald
                    : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                size: 18,
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isPumpRunning ? 'AUTO-RUNNING (PUMP ACTIVE)' : 'AUTO-MANAGED (STANDBY)',
                    style: TextStyle(
                      color: widget.isPumpRunning
                          ? AppTheme.accentEmerald
                          : (isDark ? Colors.white : const Color(0xFF1E293B)),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    widget.isPumpRunning
                        ? 'Refilling tank to 95% cutoff'
                        : 'Governed by automation rules · Switch to Manual to override',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // In MANUAL mode, full manual control
    return AnimatedPressable(
      onTap: () {
        if (hardwareStateService.isEmergencyStopActive) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.danger,
              duration: Duration(seconds: 2),
              content: Text('⚠️ Motor Locked: Emergency Stop is engaged. Tap the red button below to reset.'),
            ),
          );
          return;
        }
        widget.onTogglePump();
      },
      pressedScale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        height: 52,
        decoration: BoxDecoration(
          color: widget.isPumpRunning ? AppTheme.danger : colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (widget.isPumpRunning ? AppTheme.danger : colorScheme.primary).withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(anim), child: child),
          ),
          child: widget.commandState == CommandTransitState.sending
              ? Row(
                  key: const ValueKey('PENDING_BUTTON'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.isPumpRunning ? 'STOPPING MOTOR...' : 'STARTING MOTOR...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                )
              : (widget.isPumpRunning
                  ? Row(
                      key: const ValueKey('STOP_BUTTON'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.stop_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'STOP MOTOR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      key: const ValueKey('START_BUTTON'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'START MOTOR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    )),
        ),
      ),
    );
  }

  Widget _buildEmergencyStopButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEstopActive = hardwareStateService.isEmergencyStopActive;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEstopActive) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.danger.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.danger, width: 1.2),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_rounded, color: AppTheme.danger, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'EMERGENCY STOP ENGAGED • Motor relay locked out. Tap button below to reset.',
                    style: TextStyle(
                      color: AppTheme.danger,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        AnimatedPressable(
          onTap: () {
            if (isEstopActive) {
              hardwareStateService.clearEmergencyStop();
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: AppTheme.accent,
                  duration: Duration(seconds: 3),
                  content: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '✓ EMERGENCY STOP CLEARED: Pump interlock released. Normal controls restored.',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            } else {
              if (widget.onEmergencyStop != null) {
                widget.onEmergencyStop!();
              } else {
                hardwareStateService.sendEmergencyStop();
              }
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: AppTheme.danger,
                  duration: Duration(seconds: 3),
                  content: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '🚨 EMERGENCY STOP: Pump motor halted immediately on hardware.',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          },
          pressedScale: 0.96,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isEstopActive
                  ? AppTheme.danger
                  : (isDark ? const Color(0xFF3B1219) : const Color(0xFFFFEBEF)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isEstopActive ? Colors.white : AppTheme.danger.withOpacity(0.5),
                width: isEstopActive ? 1.8 : 1.0,
              ),
              boxShadow: isEstopActive
                  ? [
                      BoxShadow(
                        color: AppTheme.danger.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isEstopActive
                        ? Colors.white.withOpacity(0.25)
                        : AppTheme.danger.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isEstopActive ? Icons.lock_reset_rounded : Icons.power_settings_new_rounded,
                    color: isEstopActive ? Colors.white : AppTheme.danger,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isEstopActive
                      ? 'EMERGENCY STOP ENGAGED (TAP TO RESET)'
                      : 'EMERGENCY STOP (AUTO / MANUAL)',
                  style: TextStyle(
                    color: isEstopActive ? Colors.white : AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHydroSystemStatsBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    final power = widget.powerKw ?? hardwareStateService.powerConsumptionKw;
    final runtime = widget.runTimeSeconds ?? hardwareStateService.runningDurationSeconds;
    final cycles = widget.cycleCount ?? hardwareStateService.pumpCycleCount;

    final minutes = (runtime / 60).floor();
    final seconds = runtime % 60;
    final runtimeStr = widget.isPumpRunning ? '${minutes}m ${seconds}s' : 'Standby';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141424) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 1. Power Consumption
          _buildStatCell(
            icon: Icons.bolt_rounded,
            iconColor: widget.isPumpRunning ? AppTheme.warning : (isDark ? Colors.white38 : Colors.black38),
            value: widget.isPumpRunning ? '${power.toStringAsFixed(2)} kW' : '0.00 kW',
            label: 'Power Draw',
            isDark: isDark,
            textTheme: textTheme,
          ),
          Container(
            width: 1,
            height: 28,
            color: isDark ? Colors.white10 : Colors.black12,
          ),
          // 2. Run Time
          _buildStatCell(
            icon: Icons.timer_outlined,
            iconColor: widget.isPumpRunning ? AppTheme.accentEmerald : (isDark ? Colors.white38 : Colors.black38),
            value: runtimeStr,
            label: 'Cycle Run Time',
            isDark: isDark,
            textTheme: textTheme,
          ),
          Container(
            width: 1,
            height: 28,
            color: isDark ? Colors.white10 : Colors.black12,
          ),
          // 3. Pump Cycles
          _buildStatCell(
            icon: Icons.repeat_rounded,
            iconColor: AppTheme.waterBlueDark,
            value: '$cycles',
            label: 'Daily Cycles',
            isDark: isDark,
            textTheme: textTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCell({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required bool isDark,
    required TextTheme textTheme,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// A. STATIC GROUND STAGE PAINTER
// ============================================================================
class _StaticGroundStagePainter extends CustomPainter {
  final bool isRunning;
  _StaticGroundStagePainter({required this.isRunning});

  @override
  void paint(Canvas canvas, Size size) {
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.15, 0.15),
        radius: 0.95,
        colors: [
          const Color(0xFF0F1B36).withOpacity(0.5),
          const Color(0xFF030712).withOpacity(0.98),
        ],
      ).createShader(bgRect);

    canvas.drawRect(bgRect, bgPaint);

    // Perspective Grid Lines at Stage Base
    final gridPaint = Paint()
      ..color = (isRunning ? const Color(0xFF00E5FF) : const Color(0xFF1E2F54)).withOpacity(0.14)
      ..strokeWidth = 1.0;

    final bottomY = size.height * 0.84;
    for (int i = 0; i <= 7; i++) {
      final x1 = size.width * 0.05 + (i * size.width * 0.90 / 7);
      final y1 = bottomY - 30;
      final x2 = size.width * 0.01 + (i * size.width * 0.98 / 7);
      final y2 = size.height - 4;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), gridPaint);
    }
    for (int j = 0; j <= 3; j++) {
      final y = bottomY - 25 + (j * 15);
      canvas.drawLine(Offset(size.width * 0.04, y), Offset(size.width * 0.96, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StaticGroundStagePainter oldDelegate) =>
      oldDelegate.isRunning != isRunning;
}

// ============================================================================
// B. SOLID 3D VOLUMETRIC CYLINDRICAL TANK PAINTER (True 3D Rotating Vessel)
// ============================================================================
class _Solid3DVolumetricTankPainter extends CustomPainter {
  final double waterLevelPct;
  final bool isPumpRunning;
  final double wavePhase;
  final double splashPhase;
  final double rotY;

  _Solid3DVolumetricTankPainter({
    required this.waterLevelPct,
    required this.isPumpRunning,
    required this.wavePhase,
    required this.splashPhase,
    required this.rotY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final r = size.width * 0.44; // Tank radius
    final h = size.height * 0.84;
    final top = 22.0;
    final bottom = top + h;
    final capH = 22.0; // Elliptical 3D perspective cap height

    // ------------------------------------------------------------------------
    // 1. SOLID BASE PEDESTAL & 3D CONTACT GROUND SHADOW
    // ------------------------------------------------------------------------
    final groundShadow = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, bottom + 12), width: r * 2.2, height: capH * 1.3),
      groundShadow,
    );

    // Solid Base Plinth
    final baseRect = Rect.fromCenter(center: Offset(cx, bottom + 5), width: r * 2.1, height: capH * 0.9);
    final baseGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF1E293B),
        const Color(0xFF0B1120),
      ],
    ).createShader(baseRect);
    canvas.drawOval(baseRect, Paint()..shader = baseGrad);

    // ------------------------------------------------------------------------
    // 2. BACK WALL OF CYLINDER & BACK STRUCTURAL RIBS (Facing away z < 0)
    // ------------------------------------------------------------------------
    final backCylinderPath = Path()
      ..moveTo(cx - r, top)
      ..lineTo(cx - r, bottom)
      ..arcToPoint(Offset(cx + r, bottom), radius: Radius.elliptical(r, capH), clockwise: false)
      ..lineTo(cx + r, top)
      ..arcToPoint(Offset(cx - r, top), radius: Radius.elliptical(r, capH), clockwise: true)
      ..close();

    final backHullGrad = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        const Color(0xFF070E1E),
        const Color(0xFF0F1B36),
        const Color(0xFF0A1326),
      ],
    ).createShader(Rect.fromLTRB(cx - r, top, cx + r, bottom));

    canvas.drawPath(backCylinderPath, Paint()..shader = backHullGrad);

    // Orbiting Back Structural Longitudinal Ribs
    final numRibs = 8;
    for (int k = 0; k < numRibs; k++) {
      final theta = (k * 2 * math.pi / numRibs);
      final alpha = theta + rotY;
      final z = math.cos(alpha); // z < 0 is back hemisphere
      final x = cx + r * math.sin(alpha);

      if (z < 0) {
        final backRibPaint = Paint()
          ..color = const Color(0xFF1E2F54).withOpacity(0.35 * (-z))
          ..strokeWidth = 1.6;
        canvas.drawLine(Offset(x, top), Offset(x, bottom), backRibPaint);
      }
    }

    // ------------------------------------------------------------------------
    // 3. SOLID VOLUMETRIC FLUID MASS (True 3D Liquid Volume)
    // ------------------------------------------------------------------------
    final clampedLevel = (waterLevelPct / 100.0).clamp(0.0, 1.0);
    final fluidH = h * clampedLevel;
    final fluidTop = bottom - fluidH;

    if (clampedLevel > 0.01) {
      canvas.save();

      // Fluid Hull Path
      final fluidPath = Path()
        ..moveTo(cx - r, fluidTop)
        ..lineTo(cx - r, bottom)
        ..arcToPoint(Offset(cx + r, bottom), radius: Radius.elliptical(r, capH), clockwise: false)
        ..lineTo(cx + r, fluidTop)
        ..arcToPoint(Offset(cx - r, fluidTop), radius: Radius.elliptical(r, capH), clockwise: true)
        ..close();

      // 3D Cylindrical Volumetric Fluid Gradient
      final fluidLightOffset = math.sin(rotY) * 0.25;
      final fluidStop1 = (0.28 + fluidLightOffset).clamp(0.05, 0.55);
      final fluidStop2 = (0.65 + fluidLightOffset).clamp(0.40, 0.85);

      final fluidGrad = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF03045E).withOpacity(0.95),
          const Color(0xFF0077B6).withOpacity(0.90),
          const Color(0xFF00B4D8).withOpacity(0.85),
          const Color(0xFF023E8A).withOpacity(0.95),
        ],
        stops: [0.0, fluidStop1, fluidStop2, 1.0],
      );

      final fluidRect = Rect.fromLTRB(cx - r, fluidTop, cx + r, bottom);
      canvas.drawPath(
        fluidPath,
        Paint()..shader = fluidGrad.createShader(fluidRect),
      );

      // 3D Orbiting Aeration Micro-Bubbles (Rotating in 3D space with rotY)
      final bubblePaint = Paint()
        ..color = Colors.white.withOpacity(0.7)
        ..style = PaintingStyle.fill;

      for (int b = 0; b < 14; b++) {
        final bTheta = (b * 0.45 * math.pi);
        final bAlpha = bTheta + rotY;
        final bZ = math.cos(bAlpha);
        final bRad = r * 0.75;
        final bx = cx + bRad * math.sin(bAlpha);
        final bProgress = ((wavePhase / (2 * math.pi) + (b * 0.075)) % 1.0);
        final by = bottom - (fluidH * bProgress);

        final bubbleAlpha = (0.3 + 0.5 * ((bZ + 1) / 2)).clamp(0.1, 0.9);
        final bubbleSize = (1.5 + (b % 3)) * (0.8 + 0.3 * ((bZ + 1) / 2));

        canvas.drawCircle(
          Offset(bx, by),
          bubbleSize,
          bubblePaint..color = Colors.white.withOpacity(bubbleAlpha),
        );
      }

      // 3D Elliptical Surface Meniscus Cap at fluidTop
      final meniscusRect = Rect.fromCenter(center: Offset(cx, fluidTop), width: r * 2, height: capH);
      final meniscusGrad = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF90E0EF).withOpacity(0.9),
          const Color(0xFF00B4D8).withOpacity(0.65),
          const Color(0xFF0077B6).withOpacity(0.4),
        ],
      ).createShader(meniscusRect);

      canvas.drawOval(meniscusRect, Paint()..shader = meniscusGrad);

      // Oscillating Wave Crest
      final wavePath = Path();
      wavePath.moveTo(cx - r, fluidTop);
      final waveAmp = isPumpRunning ? 4.5 : 1.8;

      for (double x = cx - r; x <= cx + r; x += 3) {
        final relX = (x - (cx - r)) / (r * 2);
        final waveY = fluidTop + math.sin((relX * 2 * math.pi) + wavePhase) * waveAmp;
        wavePath.lineTo(x, waveY);
      }
      canvas.drawPath(
        wavePath,
        Paint()
          ..color = const Color(0xFFCAF0F8).withOpacity(0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      // Waterfall Surface Impact Splash Ripples
      if (isPumpRunning) {
        final impactX = 135.0;
        final rippleRadius = 7.0 + (splashPhase * 22.0);
        final rippleAlpha = (1.0 - splashPhase).clamp(0.0, 1.0);

        final ripplePaint = Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(rippleAlpha * 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(impactX, fluidTop),
            width: rippleRadius * 2,
            height: rippleRadius * 0.65,
          ),
          ripplePaint,
        );
      }

      canvas.restore();
    }

    // ------------------------------------------------------------------------
    // 4. SOLID FRONT SHELL: 3D CYLINDRICAL LIGHTING & SPECULAR FRESNEL GLARE
    // ------------------------------------------------------------------------
    // Dynamic specular reflection follows rotY
    final lightVector = math.sin(rotY) * 0.35;
    final specStop1 = (0.28 + lightVector).clamp(0.05, 0.60);
    final specStop2 = (0.42 + lightVector).clamp(0.20, 0.75);
    final specStop3 = (0.78 + lightVector).clamp(0.55, 0.95);

    final frontGlassGrad = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        const Color(0xFF0F1A34).withOpacity(0.88),
        const Color(0xFF2E487C).withOpacity(0.40),
        const Color(0xFF64B5F6).withOpacity(0.25), // Specular light glare
        const Color(0xFF1A2C50).withOpacity(0.45),
        const Color(0xFF0B1428).withOpacity(0.92),
      ],
      stops: [0.0, specStop1, specStop2, specStop3, 1.0],
    );

    final frontCylinderPath = Path()
      ..moveTo(cx - r, top)
      ..lineTo(cx - r, bottom)
      ..arcToPoint(Offset(cx + r, bottom), radius: Radius.elliptical(r, capH), clockwise: false)
      ..lineTo(cx + r, top)
      ..arcToPoint(Offset(cx - r, top), radius: Radius.elliptical(r, capH), clockwise: true)
      ..close();

    canvas.drawPath(
      frontCylinderPath,
      Paint()..shader = frontGlassGrad.createShader(Rect.fromLTRB(cx - r, top, cx + r, bottom)),
    );

    // ------------------------------------------------------------------------
    // 5. 3D ORBITING FRONT STRUCTURAL RIBS (z > 0)
    // ------------------------------------------------------------------------
    for (int k = 0; k < numRibs; k++) {
      final theta = (k * 2 * math.pi / numRibs);
      final alpha = theta + rotY;
      final z = math.cos(alpha);
      final x = cx + r * math.sin(alpha);

      if (z > 0.05) {
        // Front metallic extruded beam with left highlight & right shadow
        final ribWidth = (2.2 * z).clamp(1.0, 3.0);

        // Highlight edge
        canvas.drawLine(
          Offset(x - ribWidth / 2, top),
          Offset(x - ribWidth / 2, bottom),
          Paint()
            ..color = Colors.white.withOpacity(0.6 * z)
            ..strokeWidth = 1.0,
        );

        // Core & shadow edge
        canvas.drawLine(
          Offset(x + ribWidth / 2, top),
          Offset(x + ribWidth / 2, bottom),
          Paint()
            ..color = const Color(0xFF00E5FF).withOpacity(0.5 * z)
            ..strokeWidth = 1.4,
        );
      }
    }

    // ------------------------------------------------------------------------
    // 6. 3D HEAVY-DUTY CIRCUMFERENTIAL STEEL REINFORCEMENT BELTS / RINGS
    // ------------------------------------------------------------------------
    for (int ring = 1; ring <= 3; ring++) {
      final ringY = top + (h / 4) * ring;
      final ringRect = Rect.fromCenter(center: Offset(cx, ringY), width: r * 2.04, height: capH * 0.85);

      // Ring upper metallic highlight
      canvas.drawOval(
        ringRect,
        Paint()
          ..color = const Color(0xFF475569).withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2,
      );

      // Ring front core line
      canvas.drawOval(
        ringRect,
        Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(isPumpRunning ? 0.75 : 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // ------------------------------------------------------------------------
    // 7. 3D TOP DOME & CENTRAL MANHOLE ACCESS FLANGE
    // ------------------------------------------------------------------------
    // Top Rim Bevel
    final topCapRect = Rect.fromCenter(center: Offset(cx, top), width: r * 2, height: capH);
    final topDomeGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF2E487C),
        const Color(0xFF132040),
        const Color(0xFF0B1224),
      ],
    ).createShader(topCapRect);

    canvas.drawOval(topCapRect, Paint()..shader = topDomeGrad);
    canvas.drawOval(
      topCapRect,
      Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(isPumpRunning ? 0.85 : 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );

    // Center Top Manhole Flange Opening with Orbiting Bolts
    final manholeRadius = 22.0;
    final manholeRect = Rect.fromCenter(center: Offset(cx, top), width: manholeRadius * 2, height: capH * 0.55);
    canvas.drawOval(
      manholeRect,
      Paint()
        ..color = const Color(0xFF050B17)
        ..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      manholeRect,
      Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Orbiting Bolt Studs on Top Flange
    final boltPaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..style = PaintingStyle.fill;

    for (int b = 0; b < 6; b++) {
      final bAngle = (b * math.pi / 3) + rotY;
      final bx = cx + (manholeRadius + 4) * math.cos(bAngle);
      final by = top + (capH * 0.35) * math.sin(bAngle);
      canvas.drawCircle(Offset(bx, by), 1.6, boltPaint);
    }

    // ------------------------------------------------------------------------
    // 8. 3D ORBITING GRADUATION SCALE & LABELS (Wrapping around cylinder)
    // ------------------------------------------------------------------------
    final scaleAngle = rotY % (2 * math.pi);
    final scaleZ = math.cos(scaleAngle); // Visible when on front half
    if (scaleZ > -0.2) {
      final scaleX = cx - (r * 0.88 * math.cos(scaleAngle));
      final scaleAlpha = (scaleZ + 0.2).clamp(0.0, 1.0);

      for (int g = 0; g <= 4; g++) {
        final gy = bottom - (h * (g / 4.0));
        final isMajor = g % 2 == 0;
        final lineLen = isMajor ? 14.0 : 8.0;

        canvas.drawLine(
          Offset(scaleX, gy),
          Offset(scaleX + lineLen * (scaleZ > 0 ? 1 : 0.6), gy),
          Paint()
            ..color = Colors.white.withOpacity(0.65 * scaleAlpha)
            ..strokeWidth = isMajor ? 1.8 : 1.0,
        );

        if (isMajor && scaleAlpha > 0.4) {
          final tp = TextPainter(
            text: TextSpan(
              text: '${(g * 25)}%',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8 * scaleAlpha),
                fontSize: 9.0,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(scaleX + lineLen + 4, gy - 5.5));
        }
      }
    }

    // Outer Cylinder Silhouette Glow
    final outerRimGlow = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(isPumpRunning ? 0.35 : 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawPath(frontCylinderPath, outerRimGlow);
  }

  @override
  bool shouldRepaint(covariant _Solid3DVolumetricTankPainter oldDelegate) {
    return oldDelegate.waterLevelPct != waterLevelPct ||
        oldDelegate.isPumpRunning != isPumpRunning ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.splashPhase != splashPhase ||
        oldDelegate.rotY != rotY;
  }
}

// ============================================================================
// C. FIXED MOTOR & PIPE & WATERFALL CASCADE PAINTER
// ============================================================================
class _FixedPipeMotorAndCascadePainter extends CustomPainter {
  final bool isPumpRunning;
  final double pipeFlowPhase;
  final double impellerAngle;
  final double cascadePhase;
  final double splashPhase;
  final double waterLevelPct;

  _FixedPipeMotorAndCascadePainter({
    required this.isPumpRunning,
    required this.pipeFlowPhase,
    required this.impellerAngle,
    required this.cascadePhase,
    required this.splashPhase,
    required this.waterLevelPct,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Motor Anchor Location (Bottom Right)
    final motorCenter = Offset(size.width - 55, size.height - 50);
    final motorRadius = 32.0;

    // 2. High-Pressure Delivery Pipe Geometry — Centered directly above 3D Tank
    final pipeX = size.width - 34;
    final topY = 22.0;
    final spoutX = 110.0; // Spout points exactly at the top horizontal center of the tank (left: 10 + cx: 100)
    final spoutY = 32.0;

    // A. Draw High-Pressure Industrial Pipe
    _drawPipe(canvas, motorCenter, pipeX, topY, spoutX, spoutY);

    // B. Draw Dynamic Water Flow & Cascade into Tank (when Pump is Running)
    if (isPumpRunning) {
      _drawWaterFlowAndCascade(
        canvas,
        motorCenter,
        pipeX,
        topY,
        spoutX,
        spoutY,
        size,
      );
    }

    // C. Draw Centrifugal Motor with Impeller Turbine
    _drawMotor(canvas, motorCenter, motorRadius);
  }

  void _drawPipe(
    Canvas canvas,
    Offset motor,
    double pipeX,
    double topY,
    double spoutX,
    double spoutY,
  ) {
    final pipePath = Path();
    pipePath.moveTo(motor.dx - 10, motor.dy - 24);
    pipePath.lineTo(pipeX, motor.dy - 24);
    pipePath.lineTo(pipeX, topY);
    pipePath.quadraticBezierTo(pipeX, topY - 14, pipeX - 20, topY - 14);
    pipePath.lineTo(spoutX, topY - 14);
    pipePath.quadraticBezierTo(spoutX, topY - 14, spoutX, spoutY);

    // Outer Metallic Pipe Casing
    final outerPipe = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11.0
      ..strokeCap = StrokeCap.round;

    final pipeHighlight = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawPath(pipePath, outerPipe);
    canvas.drawPath(pipePath, pipeHighlight);

    // Flange Joint Collars
    _drawFlange(canvas, Offset(pipeX, motor.dy - 24), 14);
    _drawFlange(canvas, Offset(pipeX, 140), 14);
    _drawFlange(canvas, Offset(pipeX, topY), 14);

    // Nozzle Head Collar at Spout End
    final nozzleRect = Rect.fromCenter(center: Offset(spoutX, spoutY - 2), width: 16, height: 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(nozzleRect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF00E5FF).withOpacity(0.6),
    );
  }

  void _drawFlange(Canvas canvas, Offset pos, double size) {
    final paint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = const Color(0xFF00B4D8).withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final rect = Rect.fromCenter(center: pos, width: size + 4, height: 5.5);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), border);
  }

  void _drawWaterFlowAndCascade(
    Canvas canvas,
    Offset motor,
    double pipeX,
    double topY,
    double spoutX,
    double spoutY,
    Size size,
  ) {
    // ------------------------------------------------------------------------
    // 1. WATER PULSES FLOWING INSIDE PIPE (Motor -> Up -> Arch -> Spout)
    // ------------------------------------------------------------------------
    final waterCore = Path();
    waterCore.moveTo(motor.dx - 10, motor.dy - 24);
    waterCore.lineTo(pipeX, motor.dy - 24);
    waterCore.lineTo(pipeX, topY);
    waterCore.quadraticBezierTo(pipeX, topY - 14, pipeX - 20, topY - 14);
    waterCore.lineTo(spoutX, topY - 14);
    waterCore.quadraticBezierTo(spoutX, topY - 14, spoutX, spoutY);

    final waterFlowPaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(waterCore, waterFlowPaint);

    // Rapid Rising Water Particles inside vertical pipe
    final particlePaint = Paint()
      ..color = const Color(0xFFE0FAFF)
      ..style = PaintingStyle.fill;

    final verticalHeight = (motor.dy - 24) - topY;
    for (int i = 0; i < 5; i++) {
      final progress = (pipeFlowPhase + (i * 0.2)) % 1.0;
      final y = (motor.dy - 24) - (progress * verticalHeight);
      canvas.drawCircle(Offset(pipeX, y), 2.8, particlePaint);
    }

    // ------------------------------------------------------------------------
    // 2. DYNAMIC WATER CASCADE POURING FROM PIPE END DOWN INTO TANK
    // ------------------------------------------------------------------------
    final tankBottomY = 240.0;
    final fluidH = (waterLevelPct / 100.0) * 200.0;
    final landingY = (tankBottomY - fluidH).clamp(spoutY + 15, tankBottomY - 5);

    // Thick Continuous Falling Water Jet
    final cascadeGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF00E5FF),
        const Color(0xFF00B4D8),
        const Color(0xFF48CAE4),
        const Color(0xFF90E0EF),
      ],
    ).createShader(Rect.fromLTRB(spoutX - 5, spoutY, spoutX + 5, landingY));

    final streamPaint = Paint()
      ..shader = cascadeGradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round;

    final cascadePath = Path();
    cascadePath.moveTo(spoutX, spoutY);
    cascadePath.quadraticBezierTo(
      spoutX + (math.sin(cascadePhase * 2 * math.pi) * 1.5),
      (spoutY + landingY) / 2,
      spoutX,
      landingY,
    );
    canvas.drawPath(cascadePath, streamPaint);

    // Core Luminous Stream Highlight
    final streamHighlight = Paint()
      ..color = Colors.white.withOpacity(0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(cascadePath, streamHighlight);

    // Fast-falling Waterfall Droplets along stream
    for (int i = 0; i < 6; i++) {
      final p = (cascadePhase + (i * 0.16)) % 1.0;
      final y = spoutY + (p * (landingY - spoutY));
      canvas.drawCircle(Offset(spoutX + (math.sin(p * math.pi) * 2), y), 2.6, particlePaint);
    }

    // ------------------------------------------------------------------------
    // 3. KINETIC SPLASH SPRAY & FOAM WHERE WATER ENTERS LIQUID
    // ------------------------------------------------------------------------
    final splashPaint = Paint()
      ..color = const Color(0xFFADE8F4)
      ..style = PaintingStyle.fill;

    final splashOffsets = [
      Offset(-12, -14 * (1.0 - splashPhase)),
      Offset(12, -16 * (1.0 - splashPhase)),
      Offset(-6, -18 * (1.0 - splashPhase)),
      Offset(7, -12 * (1.0 - splashPhase)),
      Offset(0, -22 * (1.0 - splashPhase)),
    ];

    for (final off in splashOffsets) {
      canvas.drawCircle(Offset(spoutX + off.dx, landingY + off.dy), 2.0, splashPaint);
    }

    // Concentric Surface Foam Ring
    final foamPaint = Paint()
      ..color = const Color(0xFFE0FAFF).withOpacity((1.0 - splashPhase).clamp(0.0, 0.8))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final splashRadius = 8.0 + (splashPhase * 16.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(spoutX, landingY),
        width: splashRadius * 2,
        height: splashRadius * 0.55,
      ),
      foamPaint,
    );
  }

  void _drawMotor(Canvas canvas, Offset center, double radius) {
    // 1. Cast-Iron Motor Body
    final motorPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFF334155),
          Color(0xFF1E293B),
          Color(0xFF0B1120),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    final rimPaint = Paint()
      ..color = (isPumpRunning ? const Color(0xFF00E5FF) : const Color(0xFF64748B)).withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;

    canvas.drawCircle(center, radius, motorPaint);
    canvas.drawCircle(center, radius, rimPaint);

    // 2. Radial Cooling Fins
    final finPaint = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..strokeWidth = 1.5;

    for (int i = 0; i < 12; i++) {
      final angle = (i * 30) * math.pi / 180;
      final p1 = Offset(center.dx + (radius - 8) * math.cos(angle), center.dy + (radius - 8) * math.sin(angle));
      final p2 = Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      canvas.drawLine(p1, p2, finPaint);
    }

    // 3. Volute Inspection Window
    final windowPaint = Paint()
      ..color = const Color(0xFF020617)
      ..style = PaintingStyle.fill;
    final windowBorder = Paint()
      ..color = (isPumpRunning ? const Color(0xFF00E5FF) : Colors.white24).withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawCircle(center, radius - 10, windowPaint);
    canvas.drawCircle(center, radius - 10, windowBorder);

    // 4. Centrifugal Impeller Turbine (Spins when Running)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(isPumpRunning ? impellerAngle : 0.0);

    final bladePaint = Paint()
      ..color = isPumpRunning ? const Color(0xFF00E5FF) : const Color(0xFF94A3B8)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 4; i++) {
      final angle = (i * 90) * math.pi / 180;
      canvas.save();
      canvas.rotate(angle);

      final blade = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(5, -8, 2, -18)
        ..quadraticBezierTo(0, -20, -2, -18)
        ..quadraticBezierTo(-5, -8, 0, 0)
        ..close();

      canvas.drawPath(blade, bladePaint);
      canvas.restore();
    }

    // Central Hub
    canvas.drawCircle(
      Offset.zero,
      6.0,
      Paint()
        ..color = const Color(0xFF0F172A)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset.zero,
      6.0,
      Paint()
        ..color = isPumpRunning ? Colors.white : Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    canvas.restore();

    // 5. Heavy-Duty Steel Base Mounting Bracket
    final standPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    final standRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + radius + 5),
      width: 40,
      height: 9,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(standRect, const Radius.circular(3)), standPaint);

    // 6. Running Aura Glow
    if (isPumpRunning) {
      final glowPaint = Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, radius + 6, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FixedPipeMotorAndCascadePainter oldDelegate) {
    return oldDelegate.isPumpRunning != isPumpRunning ||
        oldDelegate.pipeFlowPhase != pipeFlowPhase ||
        oldDelegate.impellerAngle != impellerAngle ||
        oldDelegate.cascadePhase != cascadePhase ||
        oldDelegate.splashPhase != splashPhase ||
        oldDelegate.waterLevelPct != waterLevelPct;
  }
}

