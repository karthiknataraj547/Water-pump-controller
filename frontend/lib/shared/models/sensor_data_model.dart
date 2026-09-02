class SensorDataModel {
  final String subNodeId;
  final int seqNum;
  final double waterLevelPct;
  final double waterLevelCm;
  final double flowRateLpm;
  final double totalWaterLiters;
  final int tdsPpm;
  final double temperatureC;
  final double batteryVoltage;
  final int batteryPct;
  final DateTime timestamp;

  SensorDataModel({
    required this.subNodeId,
    required this.seqNum,
    required this.waterLevelPct,
    required this.waterLevelCm,
    required this.flowRateLpm,
    required this.totalWaterLiters,
    required this.tdsPpm,
    required this.temperatureC,
    required this.batteryVoltage,
    required this.batteryPct,
    required this.timestamp,
  });

  double get waterVolumeL => totalWaterLiters;

  String get waterQualityString {
    if (tdsPpm < 50) return 'Excellent';
    if (tdsPpm < 150) return 'Good';
    if (tdsPpm < 300) return 'Fair';
    if (tdsPpm < 500) return 'Poor';
    return 'Unsafe';
  }

  factory SensorDataModel.fromJson(Map<String, dynamic> json) {
    return SensorDataModel(
      subNodeId: json['sub_node_id'] ?? json['nodeId'] ?? 'tank_node_001',
      seqNum: json['seq_num'] ?? 0,
      waterLevelPct: (json['water_level_pct'] ?? json['waterLevelPct'] ?? 0.0).toDouble(),
      waterLevelCm: (json['water_level_cm'] ?? json['waterLevelCm'] ?? 0.0).toDouble(),
      flowRateLpm: (json['flow_rate_lpm'] ?? json['flowRateLpm'] ?? 0.0).toDouble(),
      totalWaterLiters: (json['total_water_liters'] ?? json['totalWaterLiters'] ?? 0.0).toDouble(),
      tdsPpm: json['tds_ppm'] ?? json['tdsPpm'] ?? 0,
      temperatureC: (json['temperature_c'] ?? json['temperatureC'] ?? 25.0).toDouble(),
      batteryVoltage: (json['battery_voltage'] ?? json['batteryVoltage'] ?? 4.2).toDouble(),
      batteryPct: json['battery_pct'] ?? json['batteryPct'] ?? 100,
      timestamp: json['timestamp'] != null
          ? (json['timestamp'] is int
              ? DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as int) * 1000)
              : DateTime.parse(json['timestamp']))
          : DateTime.now(),
    );
  }
}
