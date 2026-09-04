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
    final lvl = (json['waterLevel'] ?? json['water_level'] ?? json['water_level_pct'] ?? json['waterLevelPct'] ?? 0.0 as num).toDouble();
    final lvlCm = (json['water_level_cm'] ?? json['waterLevelCm'] ?? ((lvl / 100.0) * 200.0) as num).toDouble();
    final flow = (json['flowRate'] ?? json['flow_rate'] ?? json['flow_rate_lpm'] ?? json['flowRateLpm'] ?? 0.0 as num).toDouble();
    final vol = (json['waterVolume'] ?? json['water_volume'] ?? json['total_water_liters'] ?? json['totalWaterLiters'] ?? ((lvl / 100.0) * 5000.0) as num).toDouble();
    final tds = (json['tds'] ?? json['tds_ppm'] ?? json['tdsPpm'] ?? 0 as num).toInt();
    final temp = (json['temperature'] ?? json['temperature_c'] ?? json['temperatureC'] ?? json['waterTempC'] ?? 25.0 as num).toDouble();
    final battV = (json['battery'] ?? json['battery_voltage'] ?? json['batteryVoltage'] ?? 4.2 as num).toDouble();
    final battPct = json['battery_pct'] ?? json['batteryPct'] ?? (((battV - 3.3) / 0.9 * 100).clamp(0, 100).toInt());

    return SensorDataModel(
      subNodeId: (json['subNodeId'] ?? json['sub_node_id'] ?? json['nodeId'] ?? 'tank_node_001').toString(),
      seqNum: (json['sequence'] ?? json['seq_num'] ?? json['seqNum'] ?? 0 as num).toInt(),
      waterLevelPct: lvl,
      waterLevelCm: lvlCm,
      flowRateLpm: flow,
      totalWaterLiters: vol,
      tdsPpm: tds,
      temperatureC: temp,
      batteryVoltage: battV,
      batteryPct: battPct is int ? battPct : (battPct as num).toInt(),
      timestamp: json['timestamp'] != null
          ? (json['timestamp'] is int
              ? DateTime.fromMillisecondsSinceEpoch(
                  (json['timestamp'] as int) > 100000000000
                      ? (json['timestamp'] as int)
                      : (json['timestamp'] as int) * 1000)
              : (DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()))
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'subNodeId': subNodeId,
    'seqNum': seqNum,
    'waterLevel': waterLevelPct,
    'water_level_pct': waterLevelPct,
    'water_level_cm': waterLevelCm,
    'flowRate': flowRateLpm,
    'flow_rate_lpm': flowRateLpm,
    'waterVolume': totalWaterLiters,
    'total_water_liters': totalWaterLiters,
    'tds': tdsPpm,
    'tds_ppm': tdsPpm,
    'temperature': temperatureC,
    'temperature_c': temperatureC,
    'battery': batteryVoltage,
    'battery_voltage': batteryVoltage,
    'battery_pct': batteryPct,
    'timestamp': timestamp.toIso8601String(),
  };
}
