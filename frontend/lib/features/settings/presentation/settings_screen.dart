import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../../shared/widgets/animated_pressable.dart';
import '../../../core/update/app_update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    hardwareStateService.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    hardwareStateService.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final device = hardwareStateService.activeDevice;
    final isOnline = hardwareStateService.isHardwareOnline;
    final isMqttConnected = hardwareStateService.isMqttConnected;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings & Config', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. User Profile Section
            Container(
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary.withOpacity(isDark ? 0.15 : 0.1),
                        ),
                        child: Center(
                          child: Text(
                            'KN',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
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
                              'Karthik N',
                              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'admin@waterpump.io',
                              style: textTheme.bodySmall?.copyWith(fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Primary Administrator',
                                style: TextStyle(color: colorScheme.primary, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
                  const SizedBox(height: 12),
                  _buildInfoRow('Organization', 'HydroPulse Smart Irrigation'),
                  _buildInfoRow('Account Status', 'Active & Verified'),
                  _buildInfoRow('Session Security', 'Encrypted JWT Bearer'),
                  _buildInfoRow('App Version', '2.0.0 (Fast Stream Engine)'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1. MQTT Broker Status Card
            Container(
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('MQTT Broker Connection', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isMqttConnected ? AppTheme.accent : AppTheme.danger).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: (isMqttConnected ? AppTheme.accent : AppTheme.danger).withOpacity(0.3), width: 0.5),
                        ),
                        child: Text(
                          isMqttConnected ? 'CONNECTED' : 'DISCONNECTED',
                          style: TextStyle(
                            color: isMqttConnected ? AppTheme.accent : AppTheme.danger,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Broker Host', hardwareStateService.brokerHost),
                  _buildInfoRow('Port', hardwareStateService.brokerPort.toString()),
                  _buildInfoRow('Topics', 'pump/#, devices/# (QoS 0)'),
                  const SizedBox(height: 10),
                  AnimatedPressable(
                    onTap: () => context.go('/hardware'),
                    pressedScale: 0.97,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(isDark ? 0.1 : 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, size: 14, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Text('Manage Broker in Hardware Tab', style: TextStyle(color: colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. Hardware Summary Card
            Container(
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Active Hardware Gateway', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (device == null) ...[
                    Text(
                      'No physical hardware currently paired.',
                      style: textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
                      label: const Text('Pair ESP32 Gateway (BLE)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      onPressed: () => context.push('/provisioning'),
                    ),
                  ] else ...[
                    _buildInfoRow('Device ID', device.id),
                    _buildInfoRow('MAC Address', device.macAddress),
                    _buildInfoRow('Live Status', isOnline ? 'ONLINE' : 'OFFLINE'),
                    _buildInfoRow('Firmware', device.firmwareVersion),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. Notification Settings Card
            Container(
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications_active_rounded, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Notification Settings', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Configure push alerts and live floating status notifications',
                    style: textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Motor Started Notification', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: const Text('Alert when pump turns ON in automatic or manual mode', style: TextStyle(fontSize: 11)),
                    value: hardwareStateService.notifyMotorStart,
                    activeColor: AppTheme.accent,
                    onChanged: (val) {
                      hardwareStateService.updateNotificationSettings(motorStart: val);
                    },
                  ),
                  Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Motor Stopped Notification', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: const Text('Alert when pump turns OFF upon reaching full capacity', style: TextStyle(fontSize: 11)),
                    value: hardwareStateService.notifyMotorStop,
                    activeColor: AppTheme.accent,
                    onChanged: (val) {
                      hardwareStateService.updateNotificationSettings(motorStop: val);
                    },
                  ),
                  Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Low Water Level Warning', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: const Text('Alert when tank volume drops below 20%', style: TextStyle(fontSize: 11)),
                    value: hardwareStateService.notifyLowLevel,
                    activeColor: AppTheme.accentAmber,
                    onChanged: (val) {
                      hardwareStateService.updateNotificationSettings(lowLevel: val);
                    },
                  ),
                  Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tank Full / Overflow Alert', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: const Text('Alert when tank reaches 90%+ capacity', style: TextStyle(fontSize: 11)),
                    value: hardwareStateService.notifyHighLevel,
                    activeColor: colorScheme.primary,
                    onChanged: (val) {
                      hardwareStateService.updateNotificationSettings(highLevel: val);
                    },
                  ),
                  Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Autonomous Mode Automation Alert', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: const Text('Alert when smart rules auto-trigger cycles', style: TextStyle(fontSize: 11)),
                    value: hardwareStateService.notifyAutoMode,
                    activeColor: colorScheme.primary,
                    onChanged: (val) {
                      hardwareStateService.updateNotificationSettings(autoMode: val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. Maintenance Actions
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.developer_board_rounded, color: colorScheme.primary, size: 20),
                    title: Text('Hardware Nodes & Gateway Hub', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text('View ESP32 & ESP8266 live telemetry & sensors', style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () => context.go('/hardware'),
                  ),
                  Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
                  ListTile(
                    leading: const Icon(Icons.wifi_password_rounded, color: AppTheme.accent, size: 20),
                    title: Text('Pair New Gateway (BLE Wizard)', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text('Scan for ESP32 and transmit Wi-Fi credentials', style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () => context.push('/provisioning'),
                  ),
                  if (device != null) ...[
                    Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
                    ListTile(
                      leading: const Icon(Icons.link_off_rounded, color: AppTheme.accentAmber, size: 20),
                      title: const Text('Unlink Active Gateway', style: TextStyle(color: AppTheme.accentAmber, fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('Remove paired ESP32 (${device.id}) and test onboarding', style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => ConfirmationDialog(
                            title: 'Unlink Gateway?',
                            content: 'This will disconnect ${device.id} from this app and return to the Link Device onboarding screen. You can re-pair anytime.',
                            confirmText: 'Unlink',
                            confirmColor: AppTheme.accentAmber,
                            onConfirm: () async {
                              await hardwareStateService.removeDevice();
                              if (mounted) {
                                context.go('/dashboard');
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. App Version & Updates Card
            Container(
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.system_update_rounded, color: AppTheme.accent, size: 20),
                          const SizedBox(width: 8),
                          Text('App Version & Updates', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'v${AppUpdateService.currentVersion}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'HydroPulse IoT Platform • Build ${AppUpdateService.currentBuildNumber}',
                    style: textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        foregroundColor: isDark ? Colors.white : Colors.black87,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
                            width: 0.5,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'Check for Updates',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      onPressed: () {
                        appUpdateService.checkForUpdates(context, isManual: true);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 6. Account & System Card
            Container(
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Account & System', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildInfoRow('User Role', 'Administrator'),
                  _buildInfoRow('Cloud Server', 'Active (Mosquitto)'),
                  const SizedBox(height: 10),
                  Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: AppTheme.danger, size: 20),
                    title: const Text('Sign Out of Account', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Clear session token and lock app', style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => ConfirmationDialog(
                          title: 'Sign Out?',
                          content: 'Are you sure you want to sign out of your HydroPulse account?',
                          confirmText: 'Sign Out',
                          confirmColor: AppTheme.danger,
                          onConfirm: () async {
                            const storage = FlutterSecureStorage();
                            await storage.deleteAll();
                            if (mounted) {
                              context.go('/login');
                            }
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
