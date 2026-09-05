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

  Future<void> _loadPumpData() async {
    setState(() => _isLoading = true);
    // Add logic to fetch initial state
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _isLoading = false);
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

    // 1. Instantaneous optimistic state update (0ms UI latency)
    setState(() {
      if (command == 'PUMP_ON') _isPumpRunning = true;
      if (command == 'PUMP_OFF' || command == 'EMERGENCY_STOP') _isPumpRunning = false;
      if (command == 'SET_MODE') _isAutoMode = (params?['mode'] == 'AUTO');
    });

    // 2. Immediate direct hardware dispatch via MQTT (< 5ms)
    hardwareStateService.sendPumpCommand(command, params: params);

    // 3. Asynchronous background backend sync (never blocks UI or delays actuation)
    apiClient.post(
      '/pumps/$devId/command',
      data: {'command': command, 'parameters': params ?? {}},
    ).then((res) {
      if (mounted && res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.accentEmerald,
            duration: const Duration(milliseconds: 1200),
            content: Text('✓ ${res.data['data']['message'] ?? 'Command executed!'}'),
          ),
        );
      }
    }).catchError((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E2D4A),
            duration: const Duration(milliseconds: 1200),
            content: Text('⚡ Instant Direct Action: $command dispatched'),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = hardwareStateService.isHardwareOnline;
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
                          !isOnline
                              ? 'OFFLINE'
                              : (_isPumpRunning ? 'ACTIVE (PUMPING)' : 'IDLE (STANDBY)'),
                          style: TextStyle(
                            color: !isOnline
                                ? AppTheme.accentRose
                                : (_isPumpRunning ? AppTheme.accentRose : AppTheme.accentEmerald),
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Big Circular Toggle Button
                        GestureDetector(
                          onTap: () {
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
                              gradient: !isOnline
                                  ? null
                                  : (_isPumpRunning ? AppTheme.dangerGradient : AppTheme.emeraldGradient),
                              color: !isOnline ? const Color(0xFF1E293B) : null,
                              boxShadow: [
                                BoxShadow(
                                  color: (!isOnline
                                          ? Colors.black26
                                          : (_isPumpRunning ? AppTheme.accentRose : AppTheme.accentEmerald))
                                      .withOpacity(0.35),
                                  blurRadius: 32,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                !isOnline
                                    ? Icons.cloud_off_rounded
                                    : (_isPumpRunning ? Icons.power_settings_new_rounded : Icons.play_arrow_rounded),
                                size: 64,
                                color: !isOnline ? AppTheme.darkTextTertiary : Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          !isOnline
                              ? 'Hardware Offline • Control Locked'
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
