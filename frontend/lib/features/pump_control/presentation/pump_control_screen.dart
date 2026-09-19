import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/hardware/hardware_state_service.dart';
import '../../../shared/widgets/confirmation_dialog.dart';

class PumpControlScreen extends ConsumerStatefulWidget {
  const PumpControlScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PumpControlScreen> createState() => _PumpControlScreenState();
}

class _PumpControlScreenState extends ConsumerState<PumpControlScreen> {
  bool _isPumpRunning = false;
  bool _isAutoMode = true;
  bool _isLoading = false;
  double _autoStartLevel = 30.0;
  double _autoStopLevel = 90.0;

  @override
  void initState() {
    super.initState();
    final dev = hardwareStateService.activeDevice;
    _isPumpRunning = dev?.isPumpRunning ?? false;
    _isAutoMode = (dev?.mode ?? 'AUTO').toUpperCase() != 'MANUAL';
    hardwareStateService.addListener(_onHardwareStateChanged);
  }

  @override
  void dispose() {
    hardwareStateService.removeListener(_onHardwareStateChanged);
    super.dispose();
  }

  void _onHardwareStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPumpData() async {
    setState(() => _isLoading = true);
    final dev = hardwareStateService.activeDevice;
    if (dev != null) {
      _isPumpRunning = dev.isPumpRunning;
      _isAutoMode = dev.mode.toUpperCase() != 'MANUAL';
    }
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _sendCommand(String command, {Map<String, dynamic>? params}) async {
    final isOnline = hardwareStateService.isHardwareOnline;
    if (!isOnline) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.accentRose,
          content: Text('🔒 Hardware Offline • Connect or power on ESP32 first.'),
        ),
      );
      return;
    }

    final devId = hardwareStateService.activeDevice?.id;
    if (devId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.accentRose,
          content: Text('No physical gateway paired. Please pair a gateway using the setup wizard.'),
        ),
      );
      return;
    }

    if (command == 'SET_MODE') {
      final newMode = (params?['mode'] ?? 'AUTO').toString().toUpperCase();
      hardwareStateService.setMode(newMode);
      return;
    }

    if (command == 'EMERGENCY_STOP') {
      hardwareStateService.sendEmergencyStop();
      return;
    }

    // Direct hardware dispatch via MQTT with command_id & strict 5-second ACK timeout SLA.
    // The UI does NOT optimistically flip the pump state; it enters 'STARTING...' or 'STOPPING...'
    // and awaits hardware ACK from the ESP32 before showing the final state.
    hardwareStateService.sendPumpCommand(command, params: params);

    // Asynchronous background backend notification
    apiClient.post(
      '/pumps/$devId/command',
      data: {'command': command, 'parameters': params ?? {}},
    ).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = hardwareStateService.isHardwareOnline;
    final activeDevice = hardwareStateService.activeDevice;
    if (activeDevice != null) {
      _isAutoMode = activeDevice.mode.toUpperCase() != 'MANUAL';
      _isPumpRunning = (hardwareStateService.pumpStatus?.isRunning ?? false) || activeDevice.isPumpRunning;
    }

    final isCommandInFlight = hardwareStateService.lastCommand?.state == CommandTransitState.sending;
    final pendingAction = hardwareStateService.pendingCommandAction;

    String statusTitle;
    Color statusColor;
    if (!isOnline) {
      statusTitle = 'OFFLINE';
      statusColor = AppTheme.accentRose;
    } else if (isCommandInFlight) {
      statusTitle = (pendingAction == 'ON' || hardwareStateService.lastCommand?.command == 'PUMP_ON')
          ? 'STARTING...'
          : 'STOPPING...';
      statusColor = const Color(0xFFF59E0B);
    } else if (_isPumpRunning) {
      statusTitle = 'ACTIVE (PUMPING)';
      statusColor = AppTheme.accentRose;
    } else {
      statusTitle = 'IDLE (STANDBY)';
      statusColor = AppTheme.accentEmerald;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pump Control Center', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              hardwareStateService.refresh();
              _loadPumpData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                children: [
                  // 1. Interactive Pump Relay Toggle Hero
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28.0),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppTheme.darkCardBorder),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'PUMP RELAY STATE',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          statusTitle,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Big Circular Toggle Button (Confirmed by Hardware ACK)
                        GestureDetector(
                          onTap: () {
                            if (isCommandInFlight) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFFF59E0B),
                                  content: Text('⏳ Awaiting hardware confirmation... Please wait.'),
                                ),
                              );
                              return;
                            }
                            if (_isPumpRunning) {
                              _sendCommand('PUMP_OFF');
                            } else {
                              showDialog(
                                context: context,
                                builder: (_) => ConfirmationDialog(
                                  title: 'Activate Pump?',
                                  content: 'Confirm starting the water pump motor. Local safety watchdogs will automatically halt the pump if the tank fills or flow stops.',
                                  confirmText: 'Start Motor',
                                  confirmColor: AppTheme.accentEmerald,
                                  onConfirm: () => _sendCommand('PUMP_ON'),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: isCommandInFlight
                                  ? const LinearGradient(colors: [Color(0xFFD97706), Color(0xFFB45309)])
                                  : (_isPumpRunning ? AppTheme.dangerGradient : AppTheme.emeraldGradient),
                              boxShadow: [
                                BoxShadow(
                                  color: (isCommandInFlight
                                          ? const Color(0xFFF59E0B)
                                          : (_isPumpRunning ? AppTheme.accentRose : AppTheme.accentEmerald))
                                      .withOpacity(0.35),
                                  blurRadius: 32,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: isCommandInFlight
                                  ? const SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 4,
                                      ),
                                    )
                                  : Icon(
                                      _isPumpRunning ? Icons.power_settings_new_rounded : Icons.play_arrow_rounded,
                                      size: 64,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          isCommandInFlight
                              ? (pendingAction == 'ON' || hardwareStateService.lastCommand?.command == 'PUMP_ON'
                                  ? 'Hardware Starting Relay...'
                                  : 'Hardware Stopping Relay...')
                              : (_isPumpRunning ? 'Tap to STOP Pump' : 'Tap to START Pump'),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. Emergency Cutoff Button
                  SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentRose,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                icon: const Icon(Icons.dangerous_rounded, size: 28),
                label: const Text(
                  'EMERGENCY SHUTDOWN (HARD CUTOFF)',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ConfirmationDialog(
                      title: '🚨 EMERGENCY STOP',
                      content: 'This will immediately de-energize the pump relay and lock out automated starts until cleared. Use during leaks or hardware faults.',
                      confirmText: 'Trip Emergency Cutoff',
                      confirmColor: AppTheme.accentRose,
                      onConfirm: () => _sendCommand('EMERGENCY_STOP'),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // 3. Control Mode Switch
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Operating Mode', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      'Auto mode utilizes local ESP32 threshold rules to start and stop the pump independently of the cloud.',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Automatic Mode')),
                            selected: _isAutoMode,
                            onSelected: (val) {
                              if (val) _sendCommand('SET_MODE', params: {'mode': 'AUTO'});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Manual Mode')),
                            selected: !_isAutoMode,
                            onSelected: (val) {
                              if (val) _sendCommand('SET_MODE', params: {'mode': 'MANUAL'});
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 4. Autonomous Threshold Sliders
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Autonomous Water Thresholds', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // Auto-Start Level
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Auto-Start Level', style: TextStyle(fontSize: 14)),
                        Text('${_autoStartLevel.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryCyan)),
                      ],
                    ),
                    Slider(
                      value: _autoStartLevel,
                      min: 10,
                      max: 60,
                      divisions: 10,
                      activeColor: AppTheme.primaryCyan,
                      onChanged: (v) => setState(() => _autoStartLevel = v),
                    ),
                    const SizedBox(height: 12),

                    // Auto-Stop Level
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Auto-Stop Level', style: TextStyle(fontSize: 14)),
                        Text('${_autoStopLevel.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentEmerald)),
                      ],
                    ),
                    Slider(
                      value: _autoStopLevel,
                      min: 70,
                      max: 100,
                      divisions: 6,
                      activeColor: AppTheme.accentEmerald,
                      onChanged: (v) => setState(() => _autoStopLevel = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
