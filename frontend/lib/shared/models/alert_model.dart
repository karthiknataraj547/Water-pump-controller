class AlertModel {
  final String id;
  final String deviceId;
  final String severity; // INFO, WARNING, CRITICAL, EMERGENCY
  final String type;
  final String title;
  final String description;
  final bool isResolved;
  final DateTime createdAt;

  AlertModel({
    required this.id,
    required this.deviceId,
    required this.severity,
    required this.type,
    required this.title,
    required this.description,
    required this.isResolved,
    required this.createdAt,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    return AlertModel(
      id: json['id'] ?? '',
      deviceId: json['deviceId'] ?? '',
      severity: json['severity'] ?? 'WARNING',
      type: json['type'] ?? 'ANOMALY',
      title: json['title'] ?? 'Device Alert',
      description: json['description'] ?? '',
      isResolved: json['isResolved'] ?? false,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
    );
  }
}
