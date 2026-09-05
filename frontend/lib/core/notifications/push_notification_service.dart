import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../hardware/hardware_state_service.dart';

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  // Stream for in-app floating heads-up banner notifications
  final StreamController<InAppNotificationData> _inAppNotificationController =
      StreamController<InAppNotificationData>.broadcast();
  Stream<InAppNotificationData> get inAppNotificationStream => _inAppNotificationController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('[PushNotificationService] Tapped notification: ${response.payload}');
        },
      );

      // Create Android Notification Channels for Android 8.0+
      final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'hydropulse_motor',
            'Motor & Pump Actuation',
            description: 'Alerts when the water pump starts, stops, or transitions mode.',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );

        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'hydropulse_alerts',
            'Safety & Emergency Alerts',
            description: 'Critical alerts including Emergency Stop, Dry Run, and Tank Overflow.',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );

        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'hydropulse_general',
            'General System & Updates',
            description: 'System health, OTA updates, and network notifications.',
            importance: Importance.defaultImportance,
          ),
        );

        // Request POST_NOTIFICATIONS permission on Android 13+
        await androidImpl.requestNotificationsPermission();
      }

      _isInitialized = true;
      debugPrint('[PushNotificationService] Initialized successfully.');

      // Automatically hook into hardware alert stream
      _listenToHardwareAlerts();
    } catch (e) {
      debugPrint('[PushNotificationService] Init error: $e');
    }
  }

  void _listenToHardwareAlerts() {
    hardwareStateService.alertStream.listen((alert) {
      showPushNotification(
        title: alert.title,
        body: alert.message,
        type: alert.type,
        level: alert.level,
      );
    });
  }

  Future<void> showPushNotification({
    required String title,
    required String body,
    String type = 'info',
    AlertLevel level = AlertLevel.info,
    String? payload,
  }) async {
    // 1. Emit to in-app heads-up banner stream for instant visual feedback inside the app
    _inAppNotificationController.add(
      InAppNotificationData(
        id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        body: body,
        type: type,
        level: level,
        timestamp: DateTime.now(),
      ),
    );

    if (!_isInitialized) return;

    try {
      final isAlert = type == 'critical' || type == 'emergency' || level == AlertLevel.danger;
      final channelId = isAlert
          ? 'hydropulse_alerts'
          : (type.contains('motor') ? 'hydropulse_motor' : 'hydropulse_general');
      final channelName = isAlert
          ? 'Safety & Emergency Alerts'
          : (type.contains('motor') ? 'Motor & Pump Actuation' : 'General System & Updates');

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Real-time HydroPulse IoT notifications',
        importance: isAlert ? Importance.max : Importance.high,
        priority: isAlert ? Priority.max : Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(body),
        icon: '@mipmap/ic_launcher',
      );

      final notifDetails = NotificationDetails(android: androidDetails);

      final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _notificationsPlugin.show(
        notifId,
        title,
        body,
        notifDetails,
        payload: payload ?? type,
      );
    } catch (e) {
      debugPrint('[PushNotificationService] Failed to post system notification: $e');
    }
  }
}

class InAppNotificationData {
  final String id;
  final String title;
  final String body;
  final String type;
  final AlertLevel level;
  final DateTime timestamp;

  InAppNotificationData({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.level,
    required this.timestamp,
  });
}

final pushNotificationService = PushNotificationService();
