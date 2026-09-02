import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../core/alerts/overflow_alert_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/smart_water_system_card.dart';
import '../../../shared/widgets/metric_card.dart';
import '../../../shared/widgets/animated_pressable.dart';
import '../../../core/update/app_update_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    hardwareStateService.addListener(_onHardwareStateChanged);
    overflowAlertService.addListener(_onHardwareStateChanged);
    ThemeNotifier.instance.addListener(_onHardwareStateChanged);

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));
    _entryController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      appUpdateService.checkForUpdates(context);
    });
  }

  @override
  void dispose() {
    hardwareStateService.removeListener(_onHardwareStateChanged);
    overflowAlertService.removeListener(_onHardwareStateChanged);
    ThemeNotifier.instance.removeListener(_onHardwareStateChanged);
    _entryController.dispose();
    super.dispose();
  }

  void _onHardwareStateChanged() {
    if (mounted) setState(() {});
  }

  void _sendPumpCommand(String command, {Map<String, dynamic>? params}) {
    hardwareStateService.sendPumpCommand(command, params: params);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$command sent to hardware'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = hardwareStateService.activeDevice;
    final isOnline = hardwareStateService.isHardwareOnline;
    final isMqttConnected = hardwareStateService.isMqttConnected;
    final sensorData = hardwareStateService.sensorData;
    final pumpStatus = hardwareStateService.pumpStatus;

    final isPumpOn = (pumpStatus?.isRunning ?? false) || (device?.isPumpRunning ?? false);
    final waterLevel = sensorData?.waterLevelPct ?? 0.0;
    final isDarkMode = ThemeNotifier.instance.isDarkMode;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    device?.name ?? 'HydroPulse',
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                // Smooth animated status badge
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isOnline ? AppTheme.accent : AppTheme.danger).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (isOnline ? AppTheme.accent : AppTheme.danger).withOpacity(0.25),
                      width: 0.5,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      isOnline ? 'ONLINE' : 'OFFLINE',
                      key: ValueKey(isOnline),
                      style: TextStyle(
                        color: isOnline ? AppTheme.accent : AppTheme.danger,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              device != null
                  ? 'ID: ${device.id} • ${isOnline ? "Hardware Ping ${hardwareStateService.lastCommandRttMs}ms" : (isMqttConnected ? "MQTT Connected · Hardware Offline" : "Connecting Broker...")}'
                  : 'Ready to connect',
              style: textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          // Theme Toggle with smooth animated icon transition
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween(begin: 0.75, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                key: ValueKey(isDarkMode),
                color: isDarkMode ? AppTheme.warning : colorScheme.primary,
                size: 22,
              ),
            ),
            tooltip: isDarkMode ? 'Switch to Light' : 'Switch to Dark',
            onPressed: () => ThemeNotifier.instance.toggleTheme(),
          ),
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded, color: colorScheme.primary, size: 22),
            tooltip: 'Pair Gateway',
            onPressed: () => context.push('/provisioning'),
          ),
          IconButton(
            icon: Icon(Icons.notifications_none_rounded, size: 22, color: isDarkMode ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, size: 22, color: isDarkMode ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
            tooltip: 'Settings & Config',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await hardwareStateService.refresh();
        },
        color: colorScheme.primary,
        child: FadeTransition(
          opacity: _fadeIn,
          child: SlideTransition(
            position: _slideUp,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Overflow Emergency Alarm Banner with animated entrance
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, anim) => SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(anim),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: overflowAlertService.isOverflowing
                        ? Padding(
                            key: const ValueKey('overflow-banner'),
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildOverflowAlertBanner(overflowAlertService.currentLevelPct),
                          )
                        : const SizedBox.shrink(key: ValueKey('no-overflow')),
                  ),

                  // No hardware or offline banners with animated transitions
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SizeTransition(sizeFactor: anim, child: child),
                    ),
                    child: device == null
                        ? Padding(
                            key: const ValueKey('no-hw'),
                            padding: const EdgeInsets.only(bottom: 20),
                            child: _buildNoHardwareCard(),
                          )
                        : (!isOnline
                            ? Padding(
                                key: const ValueKey('hw-offline'),
                                padding: const EdgeInsets.only(bottom: 20),
                                child: _buildHardwareOfflineBanner(device.id),
                              )
                            : const SizedBox.shrink(key: ValueKey('hw-online'))),
                  ),

                  // 3D Rotatable SMART WATER SYSTEM
                  SmartWaterSystemCard(
                    waterLevelPct: waterLevel,
                    waterVolumeLiters: sensorData?.waterVolumeL ?? 0.0,
                    totalCapacityLiters: 5000.0,
                    isPumpRunning: isPumpOn,
                    mode: device?.mode ?? 'AUTO',
                    mainNodeStatus: hardwareStateService.mainNodeStatus,
                    subNodeStatus: hardwareStateService.subNodeStatus,
                    systemHealth: hardwareStateService.systemHealth,
                    commandState: hardwareStateService.lastCommand?.state ?? CommandTransitState.idle,
                    onModeChanged: (newMode) {
                      hardwareStateService.setMode(newMode);
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Mode switched to $newMode'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    onTogglePump: () {
                      if (!isOnline && !isMqttConnected) {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Hardware offline. Power on ESP32 first.'),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                        return;
                      }
                      if (isPumpOn) {
                        _sendPumpCommand('STOP_PUMP');
                      } else {
                        _sendPumpCommand('START_PUMP');
                      }
                    },
                  ),
                  const SizedBox(height: 20),

                  // Sensor Metrics Grid
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.15,
                    children: [
                      MetricCard(
                        title: 'Flow Rate',
                        value: sensorData != null ? sensorData.flowRateLpm.toStringAsFixed(1) : '—',
                        unit: sensorData != null ? 'L/min' : '',
                        icon: Icons.speed_rounded,
                        accentColor: colorScheme.primary,
                        subtitle: isPumpOn ? 'Pumping' : (sensorData != null ? 'Idle' : 'No sensor'),
                      ),
                      MetricCard(
                        title: 'Volume',
                        value: sensorData != null ? Formatters.formatVolume(sensorData.totalWaterLiters) : '—',
                        unit: '',
                        icon: Icons.water_drop_outlined,
                        accentColor: AppTheme.waterBlueDark,
                        subtitle: sensorData != null ? 'Level: ${waterLevel.toStringAsFixed(0)}%' : 'Offline',
                      ),
                      MetricCard(
                        title: 'TDS',
                        value: sensorData != null ? '${sensorData.tdsPpm}' : '—',
                        unit: sensorData != null ? 'PPM' : '',
                        icon: Icons.science_outlined,
                        accentColor: AppTheme.accent,
                        subtitle: sensorData != null ? Formatters.getTdsClassification(sensorData.tdsPpm) : 'No signal',
                      ),
                      MetricCard(
                        title: 'Quality',
                        value: sensorData != null ? sensorData.waterQualityString : '—',
                        unit: '',
                        icon: Icons.verified_outlined,
                        accentColor: AppTheme.waterBlueDark,
                        subtitle: sensorData != null ? 'TDS monitored' : 'No signal',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Quick Nav — theme-aware
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedPressable(
                          onTap: () => context.go('/hardware'),
                          pressedScale: 0.96,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDarkMode ? AppTheme.darkCard : AppTheme.lightCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDarkMode ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.developer_board_outlined, color: colorScheme.primary, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Hardware Nodes',
                                  style: textTheme.labelLarge?.copyWith(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedPressable(
                          onTap: () => context.push('/automation'),
                          pressedScale: 0.96,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDarkMode ? AppTheme.darkCard : AppTheme.lightCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDarkMode ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.auto_fix_high_outlined, color: AppTheme.accent, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Automation',
                                  style: textTheme.labelLarge?.copyWith(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoHardwareCard() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDarkMode ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withOpacity(0.2), width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.bluetooth_searching_rounded, size: 32, color: colorScheme.primary),
          const SizedBox(height: 10),
          Text('No Gateway Paired', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Connect your ESP32 via Bluetooth to start streaming live telemetry.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          AnimatedPressable(
            onTap: () => context.push('/provisioning'),
            pressedScale: 0.95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Pair Gateway via BLE',
                    style: textTheme.labelLarge?.copyWith(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareOfflineBanner(String deviceId) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(isDarkMode ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.danger.withOpacity(0.2), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: AppTheme.danger, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hardware Offline',
                  style: textTheme.labelLarge?.copyWith(color: AppTheme.danger, fontSize: 13),
                ),
                Text(
                  'Waiting for ESP32 ($deviceId) heartbeat...',
                  style: textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverflowAlertBanner(double levelPct) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.danger, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TANK OVERFLOW WARNING',
                      style: textTheme.labelLarge?.copyWith(
                        color: AppTheme.danger,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      'Water level at ${levelPct.toStringAsFixed(1)}%',
                      style: textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AnimatedPressable(
                  onTap: () => overflowAlertService.stopPumpAndDismiss(),
                  pressedScale: 0.96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'STOP MOTOR',
                      style: textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedPressable(
                onTap: () => overflowAlertService.muteAlarm(),
                pressedScale: 0.96,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.volume_off_rounded, color: Colors.white70, size: 15),
                      const SizedBox(width: 5),
                      Text('Mute', style: textTheme.labelSmall?.copyWith(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
