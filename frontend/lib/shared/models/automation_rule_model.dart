class AutomationRuleModel {
  final String id;
  final String deviceId;
  final String name;
  final bool isEnabled;
  final String conditionType; // WATER_LEVEL_BELOW, WATER_LEVEL_ABOVE
  final double conditionValue;
  final String actionType;    // START_PUMP, STOP_PUMP
  final double autoStopLevelPct;
  final int maxRunMinutes;

  AutomationRuleModel({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.isEnabled,
    required this.conditionType,
    required this.conditionValue,
    required this.actionType,
    required this.autoStopLevelPct,
    required this.maxRunMinutes,
  });

  factory AutomationRuleModel.fromJson(Map<String, dynamic> json) {
    return AutomationRuleModel(
      id: json['id'] ?? '',
      deviceId: json['deviceId'] ?? '',
      name: json['name'] ?? 'Automation Rule',
      isEnabled: json['isEnabled'] ?? true,
      conditionType: json['conditionType'] ?? 'WATER_LEVEL_BELOW',
      conditionValue: (json['conditionValue'] ?? 30.0).toDouble(),
      actionType: json['actionType'] ?? 'START_PUMP',
      autoStopLevelPct: (json['autoStopLevelPct'] ?? 90.0).toDouble(),
      maxRunMinutes: json['maxRunMinutes'] ?? 30,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'isEnabled': isEnabled,
    'conditionType': conditionType,
    'conditionValue': conditionValue,
    'actionType': actionType,
    'autoStopLevelPct': autoStopLevelPct,
    'maxRunMinutes': maxRunMinutes,
  };
}
