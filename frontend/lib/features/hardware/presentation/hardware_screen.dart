import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../../shared/widgets/spatial_hardware_topology_3d.dart';
import '../../../shared/widgets/animated_pressable.dart';

class HardwareScreen extends StatefulWidget {
  const HardwareScreen({Key? key}) : super(key: key);

  @override
  State<HardwareScreen> createState() => _HardwareScreenState();
}

class _HardwareScreenState extends State<HardwareScreen> {
  @override
  void initState() {
    super.initState();
    hardwareStateService.addListener(_onHardwareStateChanged);
    hardwareStateService.fetchUserDevicesFromBackend();
  }

  @override
  void dispose() {
    hardwareStateService.removeListener(_onHardwareStateChanged);
    super.dispose();
  }

  void _onHardwareStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final device = hardwareStateService.activeDevice;
    final isOnline = hardwareStateService.isHardwareOnline;
    final isMqttConnected = hardwareStateService.isMqttConnected;
    final sensorData = hardwareStateService.sensorData;
    final isSubOnline = hardwareStateService.isSubNodeOnline;
    final lastHeartbeat = hardwareStateService.lastHeartbeat;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hardware Nodes', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded, color: colorScheme.primary),
            tooltip: 'Pair New Hardware',
            onPressed: () => context.push('/provisioning'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status',
            onPressed: () async {
              await hardwareStateService.fetchUserDevicesFromBackend();
              await hardwareStateService.connectMqtt();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await hardwareStateService.fetchUserDevicesFromBackend();
          await hardwareStateService.connectMqtt();
        },
        color: colorScheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Cloud Telemetry Backend Status Banner
              _buildCloudSyncBar(isMqttConnected),
              const SizedBox(height: 18),

              // 2. 3D Spatial Radio Network Topology Stage
              SpatialHardwareTopology3D(
                isGatewayOnline: isOnline,
                isSubNodeOnline: isSubOnline,
                gatewayMac: device?.macAddress ?? 'ESP32 Gateway',
                subNodeMac: sensorData?.subNodeId ?? 'ESP8266 Tank Node',
                rssiDbm: device?.wifiRssi ?? -65,
                packetsReceived: sensorData?.seqNum ?? 0,
              ),
              const SizedBox(height: 22),

              // 3. Main Gateway Card (ESP32)
              Text('MAIN NODE (GATEWAY)', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.0)),
              const SizedBox(height: 10),
              if (device == null)
                _buildEmptyGatewayCard()
              else
                _buildEsp32GatewayCard(device, isOnline, lastHeartbeat),

              const SizedBox(height: 22),

              // 4. Sub Node / Tank Sensor Card (ESP8266)
              Text('SUB NODE (SENSOR HUB - ESP-NOW)', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.0)),
              const SizedBox(height: 10),
              _buildEsp8266SensorCard(sensorData, isSubOnline),

              const SizedBox(height: 22),

              // 5. Diagnostics Card
              Text('SYSTEM DIAGNOSTICS & TELEMETRY RTT', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.0)),
              const SizedBox(height: 10),
              _buildDiagnosticsCard(hardwareStateService.diagnostics),

              const SizedBox(height: 24),

              // 6. Pair New Gateway Action
              SizedBox(
                width: double.infinity,
                child: AnimatedPressable(
                  onTap: () => context.push('/provisioning'),
                  pressedScale: 0.97,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(isDark ? 0.12 : 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colorScheme.primary.withOpacity(0.3), width: 0.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bluetooth_searching_rounded, color: colorScheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Add / Re-pair Hardware Gateway (BLE)',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCloudSyncBar(bool isConnected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isConnected ? AppTheme.accent : AppTheme.warning).withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? AppTheme.accent : AppTheme.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'Cloud Telemetry Link Active' : 'Connecting to Cloud IoT Gateway...',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isConnected ? AppTheme.accent : AppTheme.warning,
                  ),
                ),
                Text(
                  isConnected ? 'Real-time telemetry and pump command channel online' : 'Establishing secure channel to cloud broker...',
                  style: textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          if (!isConnected)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.warning),
            )
          else
            const Icon(Icons.cloud_done_rounded, color: AppTheme.accent, size: 18),
        ],
      ),
    );
  }

  Widget _buildEmptyGatewayCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.memory_rounded, size: 40, color: isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
          const SizedBox(height: 12),
          Text('No Main Gateway Connected', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Pair your ESP32 Main Gateway over Bluetooth to view live telemetry and control the pump.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
            label: const Text('Pair ESP32 Gateway (BLE)', style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () => context.push('/provisioning'),
          ),
        ],
      ),
    );
  }

  Widget _buildEsp32GatewayCard(dynamic device, bool isOnline, DateTime? lastHeartbeat) {
    final diffSec = lastHeartbeat != null ? DateTime.now().difference(lastHeartbeat).inSeconds : null;
    final heartbeatText = diffSec == null
        ? 'No heartbeat received'
        : diffSec < 5
            ? 'Live (just now)'
            : 'Last seen ${diffSec}s ago';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isRunning = device.pumpState == 'ON' || device.pumpState == 'RUNNING';

    return Container(
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
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(isDark ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.developer_board_rounded, color: colorScheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.name,
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text(
                            device.id,
                            style: textTheme.bodySmall?.copyWith(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isOnline ? AppTheme.accent : AppTheme.danger).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (isOnline ? AppTheme.accent : AppTheme.danger).withOpacity(0.3), width: 0.5),
                ),
                child: Text(
                  isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color: isOnline ? AppTheme.accent : AppTheme.danger,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
          const SizedBox(height: 14),

          _buildSpecRow('Connection State', isOnline ? 'Active MQTT Stream' : 'Awaiting Heartbeat'),
          _buildSpecRow('Heartbeat Status', heartbeatText),
          _buildSpecRow('MAC Address', device.macAddress),
          _buildSpecRow('Firmware Version', device.firmwareVersion),
          _buildSpecRow('Relay Status', isRunning ? 'RELAY CLOSED (ON)' : 'RELAY OPEN (OFF)'),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AnimatedPressable(
                  onTap: isOnline
                      ? () {
                          final next = isRunning ? 'STOP_PUMP' : 'START_PUMP';
                          hardwareStateService.sendPumpCommand(next);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Dispatched $next signal to ESP32 Gateway.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      : null,
                  pressedScale: 0.96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? (isRunning ? AppTheme.danger : colorScheme.primary)
                          : (isDark ? AppTheme.darkSurface : AppTheme.lightBg),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                          color: isOnline ? Colors.white : textTheme.bodySmall?.color,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isRunning ? 'STOP WATER PUMP' : 'START WATER PUMP',
                          style: TextStyle(
                            color: isOnline ? Colors.white : textTheme.bodySmall?.color,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedPressable(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => ConfirmationDialog(
                      title: 'Unpair Gateway?',
                      content: 'This will remove the saved gateway from this phone until re-paired.',
                      confirmText: 'Unpair',
                      confirmColor: AppTheme.danger,
                      onConfirm: () async {
                        await hardwareStateService.removeDevice();
                      },
                    ),
                  );
                },
                pressedScale: 0.95,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.danger.withOpacity(0.2), width: 0.5),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.danger),
                      SizedBox(width: 4),
                      Text('Unpair', style: TextStyle(fontSize: 12, color: AppTheme.danger, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: AnimatedPressable(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => ConfirmationDialog(
                    title: 'Factory Reset Hardware?',
                    content: 'This will erase all saved Wi-Fi credentials from the ESP32 flash memory and restart it into BLE Pairing Mode.',
                    confirmText: 'Reset Hardware',
                    confirmColor: AppTheme.danger,
                    onConfirm: () async {
                      hardwareStateService.sendPumpCommand('FACTORY_RESET');
                      await hardwareStateService.removeDevice();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Factory Reset signal sent to ESP32. Hardware is wiping Wi-Fi & restarting in BLE mode.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                );
              },
              pressedScale: 0.97,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, width: 0.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Factory Reset Hardware (Wipe Wi-Fi & BLE)',
                  style: textTheme.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEsp8266SensorCard(dynamic sensorData, bool isSubOnline) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isSubOnline ? AppTheme.accent : AppTheme.warning).withOpacity(isDark ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.sensors_rounded,
                        color: isSubOnline ? AppTheme.accent : AppTheme.warning,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tank Sensor Node 1', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                          Text('ESP8266 (ESP-NOW Hub)', style: textTheme.bodySmall?.copyWith(fontSize: 11), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isSubOnline ? AppTheme.accent : AppTheme.darkTextTertiary).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (isSubOnline ? AppTheme.accent : AppTheme.darkTextTertiary).withOpacity(0.3), width: 0.5),
                ),
                child: Text(
                  isSubOnline ? 'STREAM ACTIVE' : 'OFFLINE',
                  style: TextStyle(
                    color: isSubOnline ? AppTheme.accent : (isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
          const SizedBox(height: 14),

          if (sensorData == null) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  'Waiting for ESP-NOW telemetry packets from ESP8266...',
                  style: textTheme.bodySmall,
                ),
              ),
            ),
          ] else ...[
            _buildSpecRow('Water Level', '${sensorData.waterLevelPct.toStringAsFixed(1)}% (${sensorData.waterVolumeL.toStringAsFixed(0)} Liters)'),
            _buildSpecRow('Flow Rate', '${sensorData.flowRateLpm.toStringAsFixed(1)} L/min (${sensorData.totalWaterLiters.toStringAsFixed(0)} L Total)'),
            _buildSpecRow('TDS Purity', '${sensorData.tdsPpm} PPM (${sensorData.waterQualityString})'),
            _buildSpecRow('Telemetry Rate', 'Fast 100ms Stream'),
            _buildSpecRow('Battery Status', '${sensorData.batteryVoltage.toStringAsFixed(2)} V (${sensorData.batteryPct}%)'),
          ],
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard(HardwareDiagnostics diag) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.analytics_outlined, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Communication Diagnostics', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Real-time Latency & Packet Flow', style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder, height: 1),
          const SizedBox(height: 14),

          _buildSpecRow(
            'Main Node Heartbeat',
            diag.mainNodeLastSeenMs >= 0 ? '${diag.mainNodeLastSeenMs} ms ago' : 'No Heartbeat',
          ),
          _buildSpecRow(
            'Sub Node Packet',
            diag.subNodeLastSeenMs >= 0 ? '${diag.subNodeLastSeenMs} ms ago' : 'No Stream',
          ),
          _buildSpecRow(
            'Command RTT',
            diag.lastCommandRttMs > 0 ? '${diag.lastCommandRttMs} ms' : '< 100 ms (Target)',
          ),
          _buildSpecRow('Telemetry Packets', '${diag.totalPacketsReceived} pkts'),
          _buildSpecRow('Wi-Fi Signal', '${diag.wifiRssi} dBm'),
          _buildSpecRow('Active Broker', diag.brokerHost),
          _buildSpecRow(
            'Broker Connection',
            diag.isMqttConnected ? 'CONNECTED (QoS 0)' : 'RECONNECTING',
          ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(fontSize: 12)),
          Text(value, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}
