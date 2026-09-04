import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/smart_water_system_card.dart';
import '../../../shared/widgets/metric_card.dart';
import '../../../shared/widgets/confirmation_dialog.dart';

class TankControlScreen extends ConsumerStatefulWidget {
  const TankControlScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<TankControlScreen> createState() => _TankControlScreenState();
}

class _TankControlScreenState extends ConsumerState<TankControlScreen> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hardwareStateService,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        final device = hardwareStateService.activeDevice;
        final sensor = hardwareStateService.sensorData;
        final pump = hardwareStateService.pumpStatus;

        final isOnline = hardwareStateService.isHardwareOnline;
        final isPumpRunning = pump?.isRunning ?? (device?.pumpState == 'ON' || device?.pumpState == 'RUNNING');
        final mode = device?.mode ?? 'AUTO';

        final waterLevelPct = sensor?.waterLevelPct ?? 0.0;
        final totalWaterLiters = sensor?.totalWaterLiters ?? (waterLevelPct / 100.0 * 5000.0);
        final flowRate = sensor?.flowRateLpm ?? (isPumpRunning ? 18.5 : 0.0);
        final tdsPpm = sensor?.tdsPpm ?? 120;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tank & Pump Control',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                Text(
                  'Volumetric Telemetry · Actuator Hub',
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                  ),
                ),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppTheme.accentEmerald.withOpacity(isDark ? 0.15 : 0.1)
                      : (isDark ? Colors.white10 : Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isOnline ? AppTheme.accentEmerald.withOpacity(0.4) : Colors.transparent,
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
                        color: isOnline ? AppTheme.accentEmerald : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'LIVE SYNC' : 'OFFLINE',
                      style: TextStyle(
                        color: isOnline ? AppTheme.accentEmerald : Colors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await hardwareStateService.refresh();
            },
            color: colorScheme.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. FULL 3D INTERACTIVE HYDRO SYSTEM CARD
                  SmartWaterSystemCard(
                    waterLevelPct: waterLevelPct,
                    waterVolumeLiters: totalWaterLiters,
                    totalCapacityLiters: 5000.0,
                    isPumpRunning: isPumpRunning,
                    mode: mode,
                    mainNodeStatus: hardwareStateService.mainNodeStatus,
                    subNodeStatus: hardwareStateService.subNodeStatus,
                    systemHealth: hardwareStateService.systemHealth,
                    onTogglePump: () {
                      if (!hardwareStateService.isHardwareOnline) {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            duration: Duration(seconds: 2),
                            backgroundColor: Color(0xFFE11D48),
                            content: Text('🔒 Hardware Offline • Connect ESP32 first to operate motor.'),
                          ),
                        );
                        return;
                      }
                      if (mode == 'AUTO') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            duration: Duration(seconds: 2),
                            content: Text('⚡ Switch to MANUAL mode to start or stop the pump manually.'),
                          ),
                        );
                        return;
                      }

                      if (isPumpRunning) {
                        hardwareStateService.sendPumpCommand('STOP_PUMP');
                      } else {
                        showDialog(
                          context: context,
                          builder: (_) => ConfirmationDialog(
                            title: 'Activate Pump Motor?',
                            content: 'Confirm starting the water pump motor. Local safety watchdogs will automatically halt the pump if the tank fills or dry run is detected.',
                            confirmText: 'Start Motor',
                            confirmColor: colorScheme.primary,
                            onConfirm: () => hardwareStateService.sendPumpCommand('START_PUMP'),
                          ),
                        );
                      }
                    },
                    onModeChanged: (newMode) {
                      if (!hardwareStateService.isHardwareOnline) {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            duration: Duration(seconds: 2),
                            backgroundColor: Color(0xFFE11D48),
                            content: Text('⚠️ Hardware Offline • Cannot switch mode.'),
                          ),
                        );
                        return;
                      }
                      hardwareStateService.setMode(newMode);
                    },
                  ),

                  const SizedBox(height: 16),

                  // 2. SECTION TITLE: VOLUMETRIC TELEMETRY
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TANK METRICS',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        '5,000L Industrial Tank',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // 3. TANK CAPACITY & VOLUME CARD
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Current Water Volume',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      totalWaterLiters.toStringAsFixed(0),
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '/ 5,000 Liters',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${waterLevelPct.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (waterLevelPct / 100.0).clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              waterLevelPct > 80
                                  ? AppTheme.accentEmerald
                                  : (waterLevelPct < 25 ? AppTheme.danger : colorScheme.primary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 4. METRIC CARDS GRID (Water Purity TDS & Dynamic Flow Rate)
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          title: 'Water Purity (TDS)',
                          value: '$tdsPpm',
                          unit: 'ppm',
                          subtitle: Formatters.getTdsClassification(tdsPpm),
                          icon: Icons.biotech_rounded,
                          accentColor: AppTheme.waterBlueDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MetricCard(
                          title: 'Dynamic Flow Rate',
                          value: flowRate.toStringAsFixed(1),
                          unit: 'L/min',
                          subtitle: isPumpRunning ? 'Water Transfer Active' : 'Pipes Resting',
                          icon: Icons.speed_rounded,
                          accentColor: isPumpRunning ? AppTheme.accentEmerald : colorScheme.primary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
