import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../hardware/hardware_state_service.dart';

class OverflowAlertService extends ChangeNotifier {
  static final OverflowAlertService instance = OverflowAlertService._internal();
  factory OverflowAlertService() => instance;
  OverflowAlertService._internal();

  bool _isOverflowing = false;
  bool _isMuted = false;
  Timer? _soundLoopTimer;
  double _currentLevelPct = 0.0;

  bool get isOverflowing => _isOverflowing;
  bool get isMuted => _isMuted;
  double get currentLevelPct => _currentLevelPct;

  void initialize() {
    hardwareStateService.addListener(_onHardwareStateChanged);
  }

  void _onHardwareStateChanged() {
    final sensorData = hardwareStateService.sensorData;
    if (sensorData == null) {
      if (_isOverflowing) {
        _isOverflowing = false;
        _stopAlarmSound();
        notifyListeners();
      }
      return;
    }

    _currentLevelPct = sensorData.waterLevelPct;

    // Trigger overflow if water level reaches or exceeds 95%
    if (_currentLevelPct >= 95.0) {
      if (!_isOverflowing) {
        _isOverflowing = true;
        _isMuted = false;
        _startAlarmSound();
        notifyListeners();
      }
    } else {
      if (_isOverflowing) {
        _isOverflowing = false;
        _isMuted = false;
        _stopAlarmSound();
        notifyListeners();
      }
    }
  }

  void muteAlarm() {
    _isMuted = true;
    _stopAlarmSound();
    notifyListeners();
  }

  void stopPumpAndDismiss() {
    hardwareStateService.sendPumpCommand('STOP_PUMP');
    _isMuted = true;
    _stopAlarmSound();
    notifyListeners();
  }

  void _startAlarmSound() {
    _soundLoopTimer?.cancel();
    _triggerSoundPulse();

    // Pulse alert sound and vibration every 1.2 seconds while overflowing
    _soundLoopTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (_isOverflowing && !_isMuted) {
        _triggerSoundPulse();
      }
    });
  }

  void _triggerSoundPulse() {
    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  void _stopAlarmSound() {
    _soundLoopTimer?.cancel();
    _soundLoopTimer = null;
  }

  @override
  void dispose() {
    _soundLoopTimer?.cancel();
    hardwareStateService.removeListener(_onHardwareStateChanged);
    super.dispose();
  }
}

final overflowAlertService = OverflowAlertService.instance;
