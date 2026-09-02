class PumpStatusModel {
  final String state; // ON, OFF, EMERGENCY_STOP
  final String mode;  // MANUAL, AUTO
  final int runningDurationSeconds;
  final String safetyStatus; // NORMAL, WARNING, CRITICAL
  final DateTime timestamp;

  PumpStatusModel({
    required this.state,
    required this.mode,
    required this.runningDurationSeconds,
    required this.safetyStatus,
    required this.timestamp,
  });

  bool get isRunning {
    final s = state.trim().toUpperCase();
    return s == 'ON' || s == 'RUNNING' || s == 'START_PUMP' || s == '1' || s == 'TRUE';
  }
  bool get isEmergencyStopped {
    final s = state.trim().toUpperCase();
    return s == 'EMERGENCY_STOP' || s == 'E_STOP' || s == 'ESTOP';
  }
  bool get isAutoMode => mode.trim().toUpperCase() == 'AUTO';

  factory PumpStatusModel.fromJson(Map<String, dynamic> json) {
    return PumpStatusModel(
      state: json['pump_state'] ?? json['state'] ?? 'OFF',
      mode: json['mode'] ?? 'AUTO',
      runningDurationSeconds: json['running_duration_seconds'] ?? 0,
      safetyStatus: json['safety_status'] ?? 'NORMAL',
      timestamp: json['timestamp'] != null
          ? (json['timestamp'] is int
              ? DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as int) * 1000)
              : DateTime.parse(json['timestamp']))
          : DateTime.now(),
    );
  }
}
