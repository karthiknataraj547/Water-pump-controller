class DeviceModel {
  final String id;
  final String name;
  final String macAddress;
  final String status;
  final String pumpState;
  final String mode;
  final int wifiRssi;
  final String firmwareVersion;
  final DateTime lastSeen;
  final int unresolvedAlertCount;

  DeviceModel({
    required this.id,
    required this.name,
    required this.macAddress,
    required this.status,
    required this.pumpState,
    required this.mode,
    required this.wifiRssi,
    required this.firmwareVersion,
    required this.lastSeen,
    this.unresolvedAlertCount = 0,
  });

  bool get isOnline => status.trim().toUpperCase() == 'ONLINE';
  bool get isPumpRunning {
    final s = pumpState.trim().toUpperCase();
    return s == 'ON' || s == 'RUNNING' || s == 'START_PUMP' || s == '1' || s == 'TRUE';
  }
  bool get isEmergencyStopped {
    final s = pumpState.trim().toUpperCase();
    return s == 'EMERGENCY_STOP' || s == 'E_STOP' || s == 'ESTOP';
  }

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Pump Gateway',
      macAddress: json['macAddress'] ?? '',
      status: json['status'] ?? 'OFFLINE',
      pumpState: json['pumpState'] ?? 'OFF',
      mode: json['mode'] ?? 'AUTO',
      wifiRssi: json['wifiRssi'] ?? -70,
      firmwareVersion: json['firmwareVersion'] ?? '1.0.0',
      lastSeen: json['lastSeen'] != null ? DateTime.parse(json['lastSeen']) : DateTime.now(),
      unresolvedAlertCount: json['unresolvedAlertCount'] ?? 0,
    );
  }
}
