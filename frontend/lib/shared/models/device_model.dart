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
      id: (json['id'] ?? json['deviceId'] ?? json['nodeId'] ?? '').toString(),
      name: (json['name'] ?? 'HydroPulse Gateway').toString(),
      macAddress: (json['macAddress'] ?? json['mac'] ?? '').toString(),
      status: (json['status'] ?? 'ONLINE').toString(),
      pumpState: (json['pumpState'] ?? json['pump_state'] ?? 'OFF').toString(),
      mode: (json['mode'] ?? 'AUTO').toString(),
      wifiRssi: (json['wifiRssi'] ?? json['wifi_rssi'] ?? -65) is int ? (json['wifiRssi'] ?? json['wifi_rssi'] ?? -65) as int : -65,
      firmwareVersion: (json['firmwareVersion'] ?? json['firmware_version'] ?? '2.0.7').toString(),
      lastSeen: json['lastSeen'] != null ? (DateTime.tryParse(json['lastSeen'].toString()) ?? DateTime.now()) : DateTime.now(),
      unresolvedAlertCount: json['unresolvedAlertCount'] is int ? json['unresolvedAlertCount'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'deviceId': id,
    'name': name,
    'macAddress': macAddress,
    'status': status,
    'pumpState': pumpState,
    'mode': mode,
    'wifiRssi': wifiRssi,
    'firmwareVersion': firmwareVersion,
    'lastSeen': lastSeen.toIso8601String(),
    'unresolvedAlertCount': unresolvedAlertCount,
  };
}
