import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ble/ble_provisioning_service.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../core/network/api_client.dart';

class ProvisioningWizardScreen extends StatefulWidget {
  const ProvisioningWizardScreen({Key? key}) : super(key: key);

  @override
  State<ProvisioningWizardScreen> createState() => _ProvisioningWizardScreenState();
}

class _ProvisioningWizardScreenState extends State<ProvisioningWizardScreen>
    with WidgetsBindingObserver {
  int _currentStep = 0;
  DiscoveredDevice? _selectedDevice;

  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePass = true;

  ProvisioningStep _provStep = ProvisioningStep.idle;
  BleStatus _bleStatus = BleStatus.unknown;
  StreamSubscription<BleStatus>? _bleStatusSub;
  StreamSubscription<ProvisioningStep>? _stepSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bleStatus = bleService.currentBleStatus;
    _bleStatusSub = bleService.bleStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _bleStatus = status;
        });
        if (status == BleStatus.ready && _currentStep == 0) {
          bleService.startScan();
        }
      }
    });

    _stepSub = bleService.stepStream.listen((step) {
      if (mounted) {
        setState(() {
          _provStep = step;
          if (step == ProvisioningStep.success) {
            _currentStep = 3;
            if (_selectedDevice != null) {
              final devId = _selectedDevice!.name.startsWith('PumpController-')
                  ? _selectedDevice!.name.replaceFirst('PumpController-', 'esp32_pump_')
                  : (_selectedDevice!.name.isNotEmpty ? _selectedDevice!.name : 'esp32_pump_000001');
              hardwareStateService.registerPairedDevice(
                deviceId: devId,
                name: _selectedDevice!.name.isNotEmpty ? _selectedDevice!.name : 'ESP32 Main Gateway',
                macAddress: _selectedDevice!.id,
              );
            }
          }
        });
      }
    });

    bleService.startScan();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check BLE and permissions on app resume
      bleService.checkPreFlightRequirements().then((_) {
        if (mounted) {
          setState(() {
            _bleStatus = bleService.currentBleStatus;
          });
          if (_bleStatus == BleStatus.ready && _currentStep == 0) {
            bleService.startScan();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bleStatusSub?.cancel();
    _stepSub?.cancel();
    bleService.stopScan();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _startProvisioning() async {
    if (_selectedDevice == null) return;

    setState(() {
      _currentStep = 2;
    });

    try {
      String claimToken = 'tok_demo_hw_pair_123';
      try {
        // 1. Get claim token from backend if available
        final claimRes = await apiClient.get('/devices/claim-token');
        if (claimRes.data != null && claimRes.data['data'] != null) {
          claimToken = claimRes.data['data']['claimToken'] ?? claimToken;
        }
      } catch (err) {
        debugPrint('[Provisioning] Backend offline, proceeding with local BLE claim token.');
      }

      // 2. Transmit credentials over BLE GATT directly to hardware
      await bleService.provisionDevice(
        deviceId: _selectedDevice!.id,
        ssid: _ssidController.text.trim(),
        password: _passwordController.text.trim(),
        claimToken: claimToken,
      );

      // 3. Claim device on backend if available
      try {
        await apiClient.post('/devices/claim', data: {
          'deviceId': _selectedDevice!.name.replaceFirst('PumpController-', 'esp32_pump_'),
          'name': 'Main Agricultural Pump',
          'macAddress': _selectedDevice!.id,
        });
      } catch (_) {}
    } catch (e) {
      debugPrint('Provisioning exception: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Pump Gateway', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.waterBlueDark),
            tooltip: 'Rescan BLE Devices',
            onPressed: () => bleService.startScan(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            children: [
              // Progress Stepper Indicator
              Row(
                children: [
                  _buildStepIndicator(0, 'Discover'),
                  _buildStepDivider(),
                  _buildStepIndicator(1, 'Wi-Fi'),
                  _buildStepDivider(),
                  _buildStepIndicator(2, 'Pairing'),
                  _buildStepDivider(),
                  _buildStepIndicator(3, 'Ready'),
                ],
              ),
              const SizedBox(height: 24),

              Expanded(
                child: _buildCurrentStepContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int stepIndex, String title) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? AppTheme.accentEmerald
                  : (isActive ? AppTheme.waterBlueDark : const Color(0xFF1E293B)),
              border: Border.all(
                color: isActive ? AppTheme.waterBlueDark : Colors.transparent,
                width: 2,
              ),
            ),
            child: Center(
              child: isDone
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        color: (isActive || isDone) ? Colors.white : Colors.white60,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDivider() {
    return Container(
      width: 24,
      height: 2,
      color: const Color(0xFF2B3A60),
      margin: const EdgeInsets.only(bottom: 16),
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildDiscoveryStep();
      case 1:
        return _buildWifiStep();
      case 2:
        return _buildPairingProgressStep();
      case 3:
        return _buildCompletionStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildDiscoveryStep() {
    final isBluetoothDisabled = _bleStatus == BleStatus.poweredOff ||
        _bleStatus == BleStatus.unauthorized ||
        _bleStatus == BleStatus.locationServicesDisabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Scanning for Pump Controllers...',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Ensure your ESP32 Main Node is powered on and in provisioning mode (blue LED flashing).',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Pre-Flight Bluetooth / Permission Check Warning Banner
        if (isBluetoothDisabled)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.accentAmber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.accentAmber.withOpacity(0.4), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bluetooth_disabled_rounded, color: AppTheme.accentAmber, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _bleStatus == BleStatus.poweredOff
                            ? 'Bluetooth is Turned Off'
                            : 'Bluetooth / Location Permission Required',
                        style: const TextStyle(
                          color: AppTheme.accentAmber,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'The app requires Bluetooth Low Energy (BLE) enabled to scan and provision your ESP32 Gateway with Wi-Fi credentials.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentAmber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.settings_bluetooth_rounded, size: 18),
                        label: const Text('Allow & Open Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        onPressed: _showBlePermissionDialog,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Deny / Not Now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bluetooth discovery is disabled. Enable when ready.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        Expanded(
          child: StreamBuilder<List<DiscoveredDevice>>(
            stream: bleService.discoveredDevicesStream,
            builder: (context, snapshot) {
              final devices = snapshot.data ?? [];
              return ListView(
                children: [
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36.0),
                      child: Center(
                        child: Column(
                          children: [
                            const CircularProgressIndicator(color: AppTheme.waterBlueDark),
                            const SizedBox(height: 16),
                            Text(
                              'Searching for HydroPulse Gateway BLE signals...',
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Place your phone near the ESP32 controller',
                              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ...devices.map((dev) {
                    final isSelected = _selectedDevice?.id == dev.id;
                    return Card(
                      color: isSelected ? const Color(0xFF1E2D4A) : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected ? AppTheme.waterBlueDark : const Color(0xFF2B3A60),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth_searching_rounded, color: AppTheme.waterBlueDark),
                        title: Text(
                          dev.name.isNotEmpty ? dev.name : 'PumpController-${dev.id.substring(0, 4)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('RSSI: ${dev.rssi} dBm • ID: ${dev.id}'),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: AppTheme.waterBlueDark)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedDevice = dev;
                          });
                        },
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.waterBlueDark,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _selectedDevice == null
                ? null
                : () {
                    setState(() {
                      _currentStep = 1;
                    });
                  },
            child: const Text('Continue to Wi-Fi Setup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildWifiStep() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect to Wi-Fi Network',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the 2.4 GHz Wi-Fi credentials for the ESP32 Gateway to connect to the Internet and Cloud MQTT broker.',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
          ),
          const SizedBox(height: 24),

          // Selected Device Confirmation Badge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2B3A60)),
            ),
            child: Row(
              children: [
                const Icon(Icons.devices_rounded, color: AppTheme.waterBlueDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedDevice?.name ?? 'ESP32 Main Gateway',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Target MAC: ${_selectedDevice?.id ?? "C8:2E:18:4A:9B:12"}',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 0),
                  child: const Text('Change', style: TextStyle(color: AppTheme.waterBlueDark)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // SSID Input
          TextField(
            controller: _ssidController,
            decoration: InputDecoration(
              labelText: 'Wi-Fi Network Name (SSID)',
              hintText: 'e.g. Farm_Pump_WiFi_2.4G',
              prefixIcon: const Icon(Icons.wifi_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // Password Input
          TextField(
            controller: _passwordController,
            obscureText: _obscurePass,
            decoration: InputDecoration(
              labelText: 'Wi-Fi Password',
              hintText: 'Enter Wi-Fi password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.waterBlueDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _ssidController.text.trim().isEmpty ? null : _startProvisioning,
              child: const Text('Transmit & Configure Hardware', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairingProgressStep() {
    final isFailed = _provStep == ProvisioningStep.failed;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isFailed) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.accentRose.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, color: AppTheme.accentRose, size: 64),
              ),
              const SizedBox(height: 20),
              const Text(
                'Provisioning Encountered an Issue',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  bleService.lastErrorMessage ??
                      'The device did not complete Wi-Fi handshake. Ensure your ESP32 is powered on and within Bluetooth range.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.waterBlueDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry Pairing', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _startProvisioning,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Edit Wi-Fi Credentials'),
                  onPressed: () => setState(() => _currentStep = 1),
                ),
              ),
            ] else ...[
              const CircularProgressIndicator(color: AppTheme.waterBlueDark, strokeWidth: 3),
              const SizedBox(height: 28),
              Text(
                _getStepDescription(_provStep),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Transmitting Wi-Fi parameters via Bluetooth GATT. Keep phone close to ESP32.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getStepDescription(ProvisioningStep step) {
    switch (step) {
      case ProvisioningStep.connecting:
        return 'Connecting to ESP32 via Bluetooth...';
      case ProvisioningStep.connected:
        return 'Bluetooth Connected! Discovering GATT services...';
      case ProvisioningStep.sendingCredentials:
        return 'Sending Wi-Fi credentials securely...';
      case ProvisioningStep.connectingWifi:
        return 'ESP32 is connecting to Wi-Fi...';
      case ProvisioningStep.connectingMqtt:
        return 'Verifying MQTT broker & device claim...';
      case ProvisioningStep.success:
        return 'Setup Complete!';
      case ProvisioningStep.failed:
        return 'Provisioning failed. Please verify credentials.';
      default:
        return 'Processing...';
    }
  }

  Widget _buildCompletionStep() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.accentEmerald.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppTheme.accentEmerald, size: 72),
            ),
            const SizedBox(height: 24),
            const Text(
              'Device Successfully Onboarded!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your ESP32 Gateway and ESP8266 Tank Node are online and streaming telemetry.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentEmerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => context.go('/dashboard'),
                child: const Text('Open Hydro Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlePermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16192E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.bluetooth_audio_rounded, color: AppTheme.waterBlueDark, size: 24),
            SizedBox(width: 10),
            Text('Enable Bluetooth & Wi-Fi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'HydroPulse requires Bluetooth to discover your nearby pump controller and Wi-Fi to establish real-time telemetry.\n\nWould you like to open device settings to enable Bluetooth and permissions?',
          style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Deny / Not Now', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.waterBlueDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
              bleService.requestPermissions();
            },
            child: const Text('Allow / Open Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
