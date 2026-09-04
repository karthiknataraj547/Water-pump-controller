import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../core/alerts/overflow_alert_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/constants/app_constants.dart';
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
  String _userName = '';
  String _userEmail = '';
  String _initials = '';

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    hardwareStateService.addListener(_onHardwareStateChanged);
    hardwareStateService.fetchUserDevicesFromBackend();
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

  Future<void> _loadUserProfile() async {
    const storage = FlutterSecureStorage();
    final name = await storage.read(key: AppConstants.keyUserName);
    final email = await storage.read(key: AppConstants.keyUserEmail);
    if (mounted) {
      setState(() {
        _userName = (name != null && name.trim().isNotEmpty) ? name.trim() : 'HydroPulse User';
        _userEmail = (email != null && email.trim().isNotEmpty) ? email.trim() : '';
        final parts = _userName.split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          _initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
        } else if (_userName.isNotEmpty) {
          _initials = _userName.substring(0, math.min(2, _userName.length)).toUpperCase();
        } else {
          _initials = 'HP';
        }
      });
    }
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
                    device?.name ?? (_userName.isNotEmpty ? '$_userName’s Space' : 'HydroPulse Hub'),
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
                    color: (device == null ? const Color(0xFF10B981) : (isOnline ? AppTheme.accent : AppTheme.danger)).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (device == null ? const Color(0xFF10B981) : (isOnline ? AppTheme.accent : AppTheme.danger)).withValues(alpha: 0.25),
                      width: 0.5,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      device == null ? 'ACCOUNT ACTIVE' : (isOnline ? 'ONLINE' : 'OFFLINE'),
                      key: ValueKey(device == null ? 'acc-active' : (isOnline ? 'online' : 'offline')),
                      style: TextStyle(
                        color: device == null ? const Color(0xFF10B981) : (isOnline ? AppTheme.accent : AppTheme.danger),
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
                  : (_userEmail.isNotEmpty ? 'Account: $_userEmail' : 'Ready to connect'),
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
          if (device != null)
            IconButton(
              icon: const Icon(Icons.link_off_rounded, color: AppTheme.danger, size: 22),
              tooltip: 'Remove',
              onPressed: () => _confirmRemoveHardware(context),
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

                  if (device == null) ...[
                    // =========================================================
                    // NO DEVICE ADDED: DISPLAY USER PROFILE SETTINGS & ONBOARDING
                    // =========================================================
                    _buildNoDeviceProfileView(isDarkMode, colorScheme, textTheme),
                  ] else ...[
                    // =========================================================
                    // ACTIVE DEVICE DASHBOARD
                    // =========================================================
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SizeTransition(sizeFactor: anim, child: child),
                      ),
                      child: !isOnline
                          ? Padding(
                              key: const ValueKey('hw-offline'),
                              padding: const EdgeInsets.only(bottom: 20),
                              child: _buildHardwareOfflineBanner(device.id),
                            )
                          : const SizedBox.shrink(key: ValueKey('hw-online')),
                    ),

                    // 3D Rotatable SMART WATER SYSTEM
                    SmartWaterSystemCard(
                      waterLevelPct: waterLevel,
                      waterVolumeLiters: sensorData?.waterVolumeL ?? 0.0,
                      totalCapacityLiters: 5000.0,
                      isPumpRunning: isPumpOn,
                      mode: device.mode,
                      mainNodeStatus: hardwareStateService.mainNodeStatus,
                      subNodeStatus: hardwareStateService.subNodeStatus,
                      systemHealth: hardwareStateService.systemHealth,
                      commandState: hardwareStateService.lastCommand?.state ?? CommandTransitState.idle,
                      onModeChanged: (newMode) {
                        if (!isOnline) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ Hardware Offline • Cannot switch mode.'),
                              backgroundColor: AppTheme.danger,
                            ),
                          );
                          return;
                        }
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
                        if (!isOnline) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🔒 Hardware Offline • Power on or connect ESP32 first.'),
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmRemoveHardware(context),
                        icon: const Icon(Icons.link_off_rounded, color: AppTheme.danger, size: 16),
                        label: const Text('Remove', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700, fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.35)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // ZERO-DEVICE USER PROFILE SETTINGS & ONBOARDING VIEW
  // =========================================================================
  Widget _buildNoDeviceProfileView(
    bool isDarkMode,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. User Profile Account Identification Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDarkMode ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.3 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary.withValues(alpha: isDarkMode ? 0.2 : 0.12),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _initials.isNotEmpty ? _initials : 'HP',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName.isNotEmpty ? _userName : 'HydroPulse User',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _userEmail.isNotEmpty ? _userEmail : 'Authenticated Member',
                          style: textTheme.bodySmall?.copyWith(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '✓ Verified Account Holder',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(
                color: isDarkMode ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
                height: 1,
              ),
              const SizedBox(height: 14),
              _buildProfileRow('Account Holder', _userName.isNotEmpty ? _userName : 'Registered User', textTheme),
              _buildProfileRow('Account Email', _userEmail.isNotEmpty ? _userEmail : 'Active Session', textTheme),
              _buildProfileRow('Linked Hardware', '0 Nodes Attached', textTheme),
              _buildProfileRow('Account Status', 'Active & Centrally Synced', textTheme),
              _buildProfileRow('Session Security', 'Encrypted JWT Bearer', textTheme),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/settings'),
                      icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                      label: const Text('Account Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      const storage = FlutterSecureStorage();
                      await storage.deleteAll();
                      hardwareStateService.clearDevice();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. Dedicated App Updates & Maintenance Card (Accessible without hardware)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDarkMode ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: AppTheme.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'App Updates & Maintenance',
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'OTA ACTIVE',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Installed: v${AppUpdateService.currentVersion} • Build ${AppUpdateService.currentBuildNumber}',
                          style: textTheme.bodySmall?.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Keep your HydroPulse client up to date. Direct in-app updates and system patches work seamlessly even before linking your ESP32 controller.',
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => appUpdateService.checkForUpdates(context, isManual: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check for Updates & Update App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 2. Hardware Pairing Setup Hero Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: isDarkMode ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.3),
              width: 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDarkMode
                  ? [
                      const Color(0xFF1E293B),
                      const Color(0xFF0F172A),
                    ]
                  : [
                      Colors.white,
                      const Color(0xFFF0F9FF),
                    ],
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withValues(alpha: 0.15),
                ),
                child: Icon(
                  Icons.developer_board_rounded,
                  size: 42,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ready to Connect Your Water Pump',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'No ESP32 pump controller is paired to your account yet. Pair your hardware node via Bluetooth BLE or WiFi to start live tank level monitoring and automated control.',
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => context.push('/provisioning'),
                icon: const Icon(Icons.bluetooth_searching_rounded),
                label: const Text('Pair New ESP32 Controller'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => context.push('/provisioning'),
                icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                label: const Text('Configure via WiFi Direct'),
                style: TextButton.styleFrom(
                  foregroundColor: isDarkMode ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 3. Simple Setup Guide
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDarkMode ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Quick Hardware Setup Guide',
                    style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSetupStep('1', 'Power on your ESP32 Water Pump Controller.'),
              _buildSetupStep('2', 'Turn on Bluetooth and Location on your mobile device.'),
              _buildSetupStep('3', 'Tap "Pair New ESP32 Controller" above to connect.'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileRow(String label, String value, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(fontSize: 12)),
          Flexible(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupStep(String stepNumber, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accent.withValues(alpha: 0.2),
            ),
            alignment: Alignment.center,
            child: Text(
              stepNumber,
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12),
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
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmRemoveHardware(context),
            icon: const Icon(Icons.link_off_rounded, size: 14),
            label: const Text('Remove'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.4), width: 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveHardware(BuildContext context) {
    final device = hardwareStateService.activeDevice;
    if (device == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.link_off_rounded, color: AppTheme.danger, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Remove Hardware?'),
          ],
        ),
        content: Text(
          'This will send a reset signal to the ESP32 (${device.id}) to wipe Wi-Fi credentials, unpair it from your account, and remove it from your dashboard.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await hardwareStateService.removeDevice();
              if (context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✓ Hardware reset signal dispatched and removed from dashboard.'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppTheme.danger,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.w700)),
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
