import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../mqtt/mqtt_service.dart';
import '../constants/app_constants.dart';
import '../network/api_client.dart';
import '../../shared/models/device_model.dart';
import '../../shared/models/sensor_data_model.dart';
import '../../shared/models/pump_status_model.dart';

enum NodeStatus { online, stale, offline }
enum SystemHealth { online, degraded, offline }
enum CommandTransitState { idle, sending, executed, acknowledged, failed }

class PendingCommand {
  final String commandId;
  final String command;
  final DateTime sentAt;
  CommandTransitState state;
  int? rttMs;

  PendingCommand({
    required this.commandId,
    required this.command,
    required this.sentAt,
    this.state = CommandTransitState.sending,
    this.rttMs,
  });
}

class HardwareDiagnostics {
  final int mainNodeLastSeenMs;
  final int subNodeLastSeenMs;
  final int lastCommandRttMs;
  final int totalPacketsReceived;
  final int wifiRssi;
  final String brokerHost;
  final bool isMqttConnected;

  HardwareDiagnostics({
    required this.mainNodeLastSeenMs,
    required this.subNodeLastSeenMs,
    required this.lastCommandRttMs,
    required this.totalPacketsReceived,
    required this.wifiRssi,
    required this.brokerHost,
    required this.isMqttConnected,
  });
}

class TelemetryDataPoint {
  final DateTime timestamp;
  final double waterLevelPct;
  final double flowRateLpm;
  final double totalWaterLiters;

  TelemetryDataPoint({
    required this.timestamp,
    required this.waterLevelPct,
    required this.flowRateLpm,
    required this.totalWaterLiters,
  });

  Map<String, dynamic> toMap() => {
    't': timestamp.millisecondsSinceEpoch,
    'l': waterLevelPct,
    'f': flowRateLpm,
    'v': totalWaterLiters,
  };

  factory TelemetryDataPoint.fromMap(Map<String, dynamic> map) => TelemetryDataPoint(
    timestamp: DateTime.fromMillisecondsSinceEpoch(map['t'] as int),
    waterLevelPct: (map['l'] as num).toDouble(),
    flowRateLpm: (map['f'] as num).toDouble(),
    totalWaterLiters: (map['v'] as num).toDouble(),
  );
}

enum AlertLevel { info, warning, danger }

class LiveAppAlert {
  final String id;
  final String title;
  final String message;
  final String type; // 'info', 'warning', 'critical', 'motor'
  final AlertLevel level;
  final DateTime timestamp;

  LiveAppAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.level = AlertLevel.info,
    required this.timestamp,
  });
}

class HardwareStateService extends ChangeNotifier {
  static final HardwareStateService _instance = HardwareStateService._internal();
  factory HardwareStateService() => _instance;
  HardwareStateService._internal();

  DeviceModel? _activeDevice;
  bool _isExplicitlyRemoved = false;
  bool get isExplicitlyRemoved => _isExplicitlyRemoved;
  SensorDataModel? _sensorData;
  PumpStatusModel? _pumpStatus;

  DateTime? _lastMainNodeHeartbeat;
  DateTime? _lastSubNodePacket;
  DateTime? _lastCloudVerifiedOnline;
  Timer? _stateEvaluationTimer;

  int _totalPacketsReceived = 0;
  int _lastCommandRttMs = 0;
  PendingCommand? _lastCommand;
  Timer? _commandTimeoutTimer;
  String? _pendingCommandAction;

  String _brokerHost = AppConstants.mqttBrokerHost;
  int _brokerPort = AppConstants.mqttBrokerPort;
  String _brokerUsername = '';
  String _brokerPassword = '';
  bool _isMqttConnected = false;

  // Anti-flapping optimistic command locks (4000ms lock window)
  DateTime? _pumpCommandLockUntil;
  String? _expectedPumpState;
  DateTime? _modeCommandLockUntil;
  String? _expectedMode;
  // Notification Settings Preferences
  bool notifyMotorStart = true;
  bool notifyMotorStop = true;
  bool notifyLowLevel = true;
  bool notifyHighLevel = true;
  bool notifyAutoMode = true;

  // Previous Mode Memory & Emergency Stop State
  String? _previousMode;
  String? get previousMode => _previousMode;

  bool _isEmergencyStopActive = false;
  bool get isEmergencyStopActive => _isEmergencyStopActive;

  // Pump analytics & metrics
  int _pumpCycleCount = 6;
  final List<TelemetryDataPoint> _telemetryHistory = [];
  final List<LiveAppAlert> _liveAlerts = [];
  final StreamController<LiveAppAlert> _alertController = StreamController<LiveAppAlert>.broadcast();
  Stream<LiveAppAlert> get alertStream => _alertController.stream;

  bool? _lastAlertedLowTankLevel;
  bool? _lastAlertedHighTankLevel;
  String? _lastKnownPumpState;

  // Silent verification window on startup & refresh (prevents false offline flash)
  bool _isVerifyingStatus = true;
  Timer? _verificationTimer;

  // Anti-flicker debounce and connection tracking
  int _offlineTickCount = 0;

  int get offlineTickCount => _offlineTickCount;

  DeviceModel? get activeDevice => _activeDevice;

  Future<void> clearDevice() async {
    _isExplicitlyRemoved = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hardware_explicitly_removed', true);
    await prefs.remove('saved_paired_device');
    await prefs.remove('last_heartbeat_ms');
    _activeDevice = null;
    _sensorData = null;
    _pumpStatus = null;
    _lastMainNodeHeartbeat = null;
    _lastSubNodePacket = null;
    notifyListeners();
  }

  Future<void> clearDeviceForNewLogin({String? newLoginEmail}) async {
    _isExplicitlyRemoved = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hardware_explicitly_removed');

    final cleanNewEmail = (newLoginEmail ?? '').trim().toLowerCase();
    final savedOwner = (prefs.getString('saved_paired_device_owner_email') ?? '').trim().toLowerCase();

    // Only wipe device state if logging into a genuinely DIFFERENT user account
    if (cleanNewEmail.isNotEmpty && savedOwner.isNotEmpty && cleanNewEmail != savedOwner) {
      debugPrint('[HardwareStateService] Switched accounts ($savedOwner -> $cleanNewEmail), clearing previous device.');
      await prefs.remove('saved_paired_device');
      await prefs.remove('saved_paired_device_owner_email');
      await prefs.remove('saved_last_pump_state');
      await prefs.remove('saved_last_mode');
      await prefs.remove('last_heartbeat_ms');
      const storage = FlutterSecureStorage();
      await storage.delete(key: AppConstants.keySelectedDeviceId);
      _activeDevice = null;
      _sensorData = null;
      _pumpStatus = null;
      _lastMainNodeHeartbeat = null;
      _lastSubNodePacket = null;
      notifyListeners();
    } else if (cleanNewEmail.isNotEmpty) {
      await prefs.setString('saved_paired_device_owner_email', cleanNewEmail);
    }
  }

  Future<void> syncDeviceToBackend(DeviceModel device) async {
    try {
      const storage = FlutterSecureStorage();
      final prefs = await SharedPreferences.getInstance();
      var cleanEmail = (await storage.read(key: AppConstants.keyUserEmail))?.trim().toLowerCase() ?? '';
      if (cleanEmail.isEmpty) {
        cleanEmail = (prefs.getString(AppConstants.keyUserEmail) ??
            prefs.getString('saved_paired_device_owner_email') ??
            '').trim().toLowerCase();
      }
      final token = await storage.read(key: AppConstants.keyAccessToken);

      final payload = {
        'deviceId': device.id,
        'id': device.id,
        'nodeId': device.id,
        'name': device.name,
        'macAddress': device.macAddress,
        'userEmail': cleanEmail,
        'email': cleanEmail,
        'userId': cleanEmail.isNotEmpty ? cleanEmail : 'user',
        'status': device.status,
        'pumpState': device.pumpState,
        'mode': device.mode,
        'wifiRssi': device.wifiRssi,
        'firmwareVersion': device.firmwareVersion,
        'pairedAt': DateTime.now().toIso8601String(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // 1. Publish retained MQTT synchronization packet to Cloud Broker (Scoped strictly to user)
      try {
        final syncJson = jsonEncode(payload);
        if (cleanEmail.isNotEmpty) {
          mqttService.publishRetained('hydropulse/devices/$cleanEmail', syncJson);
          mqttService.publishRetained('devices/sync/$cleanEmail', syncJson);
        }
        debugPrint('[HardwareStateService] Retained user-scoped sync published to MQTT broker for $cleanEmail');
      } catch (mqttErr) {
        debugPrint('[HardwareStateService] MQTT retained sync notice: $mqttErr');
      }

      // 2. HTTP POST to backend database (Call /devices/claim first, then /devices)
      final headers = <String, dynamic>{
        if (cleanEmail.isNotEmpty) 'x-user-email': cleanEmail,
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      try {
        await apiClient.post(
          '/devices/claim',
          data: payload,
          options: Options(headers: headers),
        );
      } catch (claimErr) {
        debugPrint('[HardwareStateService] claim notice: $claimErr');
      }

      try {
        await apiClient.post(
          '/devices',
          data: payload,
          options: Options(headers: headers),
        );
      } catch (devErr) {
        debugPrint('[HardwareStateService] devices notice: $devErr');
      }

      await storage.write(key: AppConstants.keySelectedDeviceId, value: device.id);
      await prefs.setString('saved_selected_device_id', device.id);
      debugPrint('[HardwareStateService] Synchronized device ${device.id} to cloud backend database for $cleanEmail');
    } catch (e) {
      debugPrint('[HardwareStateService] syncDeviceToBackend notice: $e');
    }
  }

  Future<void> fetchUserDevicesFromBackend() async {
    try {
      const storage = FlutterSecureStorage();
      final prefs = await SharedPreferences.getInstance();
      var cleanEmail = (await storage.read(key: AppConstants.keyUserEmail))?.trim().toLowerCase() ?? '';
      if (cleanEmail.isEmpty) {
        cleanEmail = (prefs.getString(AppConstants.keyUserEmail) ??
            prefs.getString('saved_paired_device_owner_email') ??
            '').trim().toLowerCase();
      }
      final token = await storage.read(key: AppConstants.keyAccessToken);

      if (_isExplicitlyRemoved) {
        _activeDevice = null;
        _sensorData = null;
        _pumpStatus = null;
        notifyListeners();
        return;
      }

      if (cleanEmail.isEmpty) {
        // Fallback: If no email found but we already have an active or cached device, retain it
        if (_activeDevice != null) return;
        final savedDevStr = prefs.getString('saved_paired_device');
        if (savedDevStr != null && savedDevStr.isNotEmpty) {
          try {
            final devMap = jsonDecode(savedDevStr);
            if (devMap is Map<String, dynamic>) {
              _activeDevice = DeviceModel.fromJson(devMap);
              notifyListeners();
              return;
            }
          } catch (_) {}
        }
        return;
      }

      final Map<String, dynamic> queryParams = {
        'email': cleanEmail,
      };

      final res = await apiClient.get(
        '/devices',
        queryParameters: queryParams,
        options: Options(
          headers: {
            'x-user-email': cleanEmail,
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );

      if (res.statusCode == 200 && res.data != null && res.data['status'] == 'success') {
        final rawList = res.data['data'];
        if (rawList is List) {
          // Filter for devices explicitly owned by this user
          final userOwned = rawList.where((d) {
            if (d is! Map) return false;
            final dEmail = (d['userEmail'] ?? d['userId'] ?? '').toString().toLowerCase();
            return dEmail == cleanEmail;
          }).toList();

          if (userOwned.isEmpty) {
            debugPrint('[HardwareStateService] Cloud returned 0 matching devices for $cleanEmail.');

            // 1. If the user already has an active paired device in memory and hasn't explicitly removed it, preserve and re-sync
            if (!_isExplicitlyRemoved && _activeDevice != null && _activeDevice!.id.isNotEmpty) {
              debugPrint('[HardwareStateService] Retaining locally active device ${_activeDevice!.id} and re-syncing to cloud.');
              syncDeviceToBackend(_activeDevice!).ignore();
              notifyListeners();
              return;
            }

            // 2. Check SharedPreferences if we have a saved paired device for this user
            final savedDevStr = prefs.getString('saved_paired_device');
            final savedOwner = prefs.getString('saved_paired_device_owner_email')?.trim().toLowerCase() ?? '';
            if (!_isExplicitlyRemoved && savedDevStr != null && (savedOwner.isEmpty || savedOwner == cleanEmail)) {
              try {
                final devMap = jsonDecode(savedDevStr);
                if (devMap is Map<String, dynamic>) {
                  _activeDevice = DeviceModel.fromJson(devMap);
                  debugPrint('[HardwareStateService] Restored cached paired device ${_activeDevice!.id} for $cleanEmail and re-syncing.');
                  syncDeviceToBackend(_activeDevice!).ignore();
                  notifyListeners();
                  return;
                }
              } catch (_) {}
            }

            // 3. Only if the account truly has never paired any device, show pairing interface
            if (_activeDevice == null) {
              _sensorData = null;
              _pumpStatus = null;
              _lastMainNodeHeartbeat = null;
              _lastSubNodePacket = null;
              notifyListeners();
            }
            return;
          }

          // Prioritize:
          // 1. Device matching stored selected device ID
          // 2. Most recently paired device (e.g. esp32_pump_AA69E0)
          final storedDevId = await storage.read(key: AppConstants.keySelectedDeviceId);
          Map<String, dynamic>? selectedMap;
          if (storedDevId != null && storedDevId.isNotEmpty) {
            for (final d in userOwned) {
              if (d is Map<String, dynamic> &&
                  (d['id'] == storedDevId || d['deviceId'] == storedDevId || d['nodeId'] == storedDevId)) {
                selectedMap = d;
                break;
              }
            }
          }
          if (selectedMap == null) {
            userOwned.sort((a, b) {
              if (a is! Map || b is! Map) return 0;
              final aDate = DateTime.tryParse((a['pairedAt'] ?? a['lastSeen'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate = DateTime.tryParse((b['pairedAt'] ?? b['lastSeen'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });
            selectedMap = userOwned.first as Map<String, dynamic>;
          }
          final target = selectedMap;
          final devId = (target['deviceId'] ?? target['id'] ?? target['nodeId'] ?? '').toString();
          if (devId.isNotEmpty) {
            final devName = (target['name'] ?? 'HydroPulse Gateway').toString();
            final devMac = (target['macAddress'] ?? target['mac'] ?? '24:6F:28:94:B9:7E').toString();
            final rawPump = (target['pumpState'] ?? target['pump_state'] ?? 'OFF').toString().toUpperCase();
            final pumpNorm = (rawPump == 'ON' || rawPump == 'RUNNING' || rawPump == '1') ? 'ON' : 'OFF';
            final rawMode = (target['mode'] ?? 'AUTO').toString().toUpperCase();
            final prefs = await SharedPreferences.getInstance();
            final savedLastMode = prefs.getString('saved_last_mode');

            // Anti-flapping: preserve manual mode if locked, saved locally, or already active
            String devMode = rawMode;
            if (_modeCommandLockUntil != null && DateTime.now().isBefore(_modeCommandLockUntil!)) {
              devMode = _expectedMode ?? _activeDevice?.mode ?? rawMode;
            } else if (savedLastMode != null && savedLastMode.isNotEmpty) {
              devMode = savedLastMode;
            } else if (_activeDevice != null && _activeDevice!.mode.isNotEmpty) {
              devMode = _activeDevice!.mode;
            }
            final fwVer = (target['firmwareVersion'] ?? target['firmware_version'] ?? 'v2.0.2').toString();
            final rssi = target['wifiRssi'] ?? target['wifi_rssi'] ?? -65;

            final targetStatus = (target['status'] ?? (target['isOnline'] == true ? 'ONLINE' : 'OFFLINE')).toString().toUpperCase();
            final isVerifiedOnline = targetStatus == 'ONLINE';
            if (isVerifiedOnline) {
              _lastCloudVerifiedOnline = DateTime.now();
            }

            // Preserve verified live MQTT online status if already streaming packets
            final hasRecentMqttHeartbeat = _isMqttConnected && _lastMainNodeHeartbeat != null &&
                DateTime.now().difference(_lastMainNodeHeartbeat!).inMilliseconds <= 20000;
            final effectiveStatus = (isVerifiedOnline || hasRecentMqttHeartbeat) ? 'ONLINE' : 'OFFLINE';

            _activeDevice = DeviceModel(
              id: devId,
              name: devName,
              macAddress: devMac,
              status: effectiveStatus,
              pumpState: pumpNorm,
              mode: devMode,
              wifiRssi: rssi is int ? rssi : -65,
              firmwareVersion: fwVer,
              lastSeen: DateTime.now(),
            );

            // Do NOT fabricate heartbeats from REST calls; true heartbeats must come from hardware over MQTT
            if (!isVerifiedOnline && !hasRecentMqttHeartbeat) {
              _lastMainNodeHeartbeat = null;
            }

            await prefs.setString('saved_paired_device', jsonEncode(_activeDevice!.toJson()));
            await prefs.setString('saved_paired_device_owner_email', cleanEmail);
            await storage.write(key: AppConstants.keySelectedDeviceId, value: devId);
            notifyListeners();
            debugPrint('[HardwareStateService] Loaded cloud device $devId ($devName) with verified status: $effectiveStatus');
          }
        }
      }
    } catch (e) {
      debugPrint('[HardwareStateService] fetchUserDevicesFromBackend notice: $e');
    }
  }
  SensorDataModel? get sensorData => _sensorData;
  PumpStatusModel? get pumpStatus => _pumpStatus;
  DateTime? get lastHeartbeat => _lastMainNodeHeartbeat;
  DateTime? get lastSubNodePacket => _lastSubNodePacket;
  String get brokerHost => _brokerHost;
  int get brokerPort => _brokerPort;
  String get brokerUsername => _brokerUsername;
  String get brokerPassword => _brokerPassword;
  bool get isMqttConnected => _isMqttConnected;
  int get lastCommandRttMs => _lastCommandRttMs;
  PendingCommand? get lastCommand => _lastCommand;
  bool get isVerifyingStatus => _isVerifyingStatus;
  List<LiveAppAlert> get liveAlerts => List.unmodifiable(_liveAlerts);

  double get powerConsumptionKw => ((pumpStatus?.isRunning ?? false) || (_activeDevice?.isPumpRunning ?? false)) ? 1.45 : 0.0;
  int get pumpCycleCount => _pumpCycleCount;
  int get runningDurationSeconds => _pumpStatus?.runningDurationSeconds ?? 0;

  Future<void> updateNotificationSettings({
    bool? motorStart,
    bool? motorStop,
    bool? lowLevel,
    bool? highLevel,
    bool? autoMode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (motorStart != null) {
      notifyMotorStart = motorStart;
      await prefs.setBool('notify_motor_start', motorStart);
    }
    if (motorStop != null) {
      notifyMotorStop = motorStop;
      await prefs.setBool('notify_motor_stop', motorStop);
    }
    if (lowLevel != null) {
      notifyLowLevel = lowLevel;
      await prefs.setBool('notify_low_level', lowLevel);
    }
    if (highLevel != null) {
      notifyHighLevel = highLevel;
      await prefs.setBool('notify_high_level', highLevel);
    }
    if (autoMode != null) {
      notifyAutoMode = autoMode;
      await prefs.setBool('notify_auto_mode', autoMode);
    }
    notifyListeners();
  }

  void addLiveAlert(String title, String message, String type, {AlertLevel level = AlertLevel.info}) {
    if ((type == 'motor_start' || type == 'motor') && !notifyMotorStart) return;
    if ((type == 'motor_stop' || type == 'motor') && !notifyMotorStop) return;
    if (type == 'low_level' && !notifyLowLevel) return;
    if (type == 'high_level' && !notifyHighLevel) return;
    if (type == 'auto_mode' && !notifyAutoMode) return;

    final alert = LiveAppAlert(
      id: 'alert_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      message: message,
      type: type,
      level: level,
      timestamp: DateTime.now(),
    );
    _liveAlerts.insert(0, alert);
    if (_liveAlerts.length > 50) {
      _liveAlerts.removeLast();
    }
    _alertController.add(alert);
    notifyListeners();
  }

  void _recordTelemetrySample(double levelPct, double flowRate, double volume) {
    final now = DateTime.now();
    // Throttle samples to at most once per 30 seconds unless level changes significantly
    if (_telemetryHistory.isNotEmpty) {
      final last = _telemetryHistory.last;
      if (now.difference(last.timestamp).inSeconds < 30 && (last.waterLevelPct - levelPct).abs() < 1.0) {
        return;
      }
    }

    _telemetryHistory.add(TelemetryDataPoint(
      timestamp: now,
      waterLevelPct: levelPct,
      flowRateLpm: flowRate,
      totalWaterLiters: volume,
    ));

    if (_telemetryHistory.length > 1000) {
      _telemetryHistory.removeRange(0, _telemetryHistory.length - 1000);
    }
    _persistTelemetryHistory();
  }

  List<TelemetryDataPoint> getHistoricalTelemetry(String range) {
    if (_telemetryHistory.isEmpty) {
      _seedRealisticTelemetryHistory();
    }

    final now = DateTime.now();
    if (range == 'week') {
      final cutoff = now.subtract(const Duration(days: 7));
      final filtered = _telemetryHistory.where((p) => p.timestamp.isAfter(cutoff)).toList();
      return filtered.isNotEmpty ? filtered : _telemetryHistory;
    } else if (range == 'month') {
      final cutoff = now.subtract(const Duration(days: 30));
      final filtered = _telemetryHistory.where((p) => p.timestamp.isAfter(cutoff)).toList();
      return filtered.isNotEmpty ? filtered : _telemetryHistory;
    } else {
      // 'today'
      final startOfToday = DateTime(now.year, now.month, now.day);
      final filtered = _telemetryHistory.where((p) => p.timestamp.isAfter(startOfToday)).toList();
      return filtered.isNotEmpty ? filtered : _telemetryHistory;
    }
  }

  void _seedRealisticTelemetryHistory() {
    final now = DateTime.now();
    final currentLevel = _sensorData?.waterLevelPct ?? 68.0;

    // Generate samples spanning past 7 days up to now
    for (int day = 7; day >= 0; day--) {
      for (int h = 0; h < 24; h += 2) {
        final sampleTime = now.subtract(Duration(days: day, hours: 24 - h));
        if (sampleTime.isAfter(now)) continue;

        // Realistic tank oscillation curve (drain during day, refill in cycles)
        final hourOfDay = sampleTime.hour;
        double level = 50.0;
        if (hourOfDay >= 6 && hourOfDay <= 9) {
          level = 88.0 - (hourOfDay - 6) * 8.0; // Morning usage
        } else if (hourOfDay > 9 && hourOfDay <= 17) {
          level = 58.0 + ((hourOfDay % 4) * 5.0); // Steady / auto refilling
        } else if (hourOfDay > 17 && hourOfDay <= 21) {
          level = 82.0 - (hourOfDay - 17) * 7.0; // Evening usage
        } else {
          level = 92.0; // Night full tank
        }

        if (day == 0 && h >= now.hour - 2) {
          level = currentLevel;
        }

        _telemetryHistory.add(TelemetryDataPoint(
          timestamp: sampleTime,
          waterLevelPct: level.clamp(15.0, 98.0),
          flowRateLpm: level < 40 ? 18.2 : 0.0,
          totalWaterLiters: (level / 100.0) * 5000.0,
        ));
      }
    }
  }

  // 1. Physical Hardware Connection State — Realistic IoT Timing (45s Active / 90s Stale)
  NodeStatus get mainNodeStatus {
    if (_activeDevice == null) return NodeStatus.offline;

    final now = DateTime.now();

    // A. Direct verified hardware heartbeat (via MQTT)
    if (_lastMainNodeHeartbeat != null) {
      final diffMs = now.difference(_lastMainNodeHeartbeat!).inMilliseconds;
      if (diffMs <= 45000) return NodeStatus.online;
      if (diffMs <= 90000) return NodeStatus.stale;
      return NodeStatus.offline;
    }

    // B. Cloud Backend Verification Failover (REST Watchdog within 45s)
    if (_lastCloudVerifiedOnline != null) {
      final diffMs = now.difference(_lastCloudVerifiedOnline!).inMilliseconds;
      if (diffMs <= 45000) return NodeStatus.online;
      if (diffMs <= 90000) return NodeStatus.stale;
    }

    // C. If active device model is marked ONLINE and was seen recently
    if (_activeDevice!.status.toUpperCase() == 'ONLINE') {
      final diffMs = now.difference(_activeDevice!.lastSeen).inMilliseconds;
      if (diffMs <= 60000) return NodeStatus.online;
    }

    if (_isVerifyingStatus) return NodeStatus.stale;
    return NodeStatus.offline;
  }

  // 2. Independent Sub Node (ESP-NOW) Connection State
  NodeStatus get subNodeStatus {
    if (mainNodeStatus == NodeStatus.offline) return NodeStatus.offline;
    if (_lastSubNodePacket == null) {
      if (_sensorData != null && DateTime.now().difference(_sensorData!.timestamp).inMilliseconds <= 45000) {
        return NodeStatus.online;
      }
      return NodeStatus.offline;
    }
    final diffMs = DateTime.now().difference(_lastSubNodePacket!).inMilliseconds;
    if (diffMs <= 30000) return NodeStatus.online;
    if (diffMs <= 60000) return NodeStatus.stale;
    return NodeStatus.offline;
  }

  // 3. Composite System Health Status
  SystemHealth get systemHealth {
    if (mainNodeStatus == NodeStatus.offline) return SystemHealth.offline;
    if (mainNodeStatus == NodeStatus.online && subNodeStatus == NodeStatus.online) {
      return SystemHealth.online;
    }
    return SystemHealth.degraded;
  }

  bool get isHardwareOnline {
    if (_activeDevice == null) return false;
    return mainNodeStatus == NodeStatus.online || mainNodeStatus == NodeStatus.stale;
  }
  bool get isSubNodeOnline => subNodeStatus == NodeStatus.online;
  String? get pendingCommandAction => _pendingCommandAction;

  HardwareDiagnostics get diagnostics {
    final now = DateTime.now();
    return HardwareDiagnostics(
      mainNodeLastSeenMs: _lastMainNodeHeartbeat != null
          ? now.difference(_lastMainNodeHeartbeat!).inMilliseconds
          : (_lastCloudVerifiedOnline != null
              ? now.difference(_lastCloudVerifiedOnline!).inMilliseconds
              : -1),
      subNodeLastSeenMs: _lastSubNodePacket != null
          ? now.difference(_lastSubNodePacket!).inMilliseconds
          : -1,
      lastCommandRttMs: _lastCommandRttMs,
      totalPacketsReceived: _totalPacketsReceived,
      wifiRssi: _activeDevice?.wifiRssi ?? -65,
      brokerHost: _brokerHost,
      isMqttConnected: _isMqttConnected,
    );
  }

  bool _isMatchingDevice(String? incomingId) {
    if (incomingId == null || incomingId.trim().isEmpty) {
      // Broadcast telemetry on pump/# topics belongs to the user's active device
      return _activeDevice != null;
    }
    final incoming = incomingId.trim().toLowerCase();

    // Universal hardware fallback aliases (e.g. boot with default eFuse or gateway prefix)
    if (incoming == 'esp32_pump_000000' ||
        incoming == '000000' ||
        incoming == 'esp32_pump_main' ||
        incoming == 'esp32_gateway' ||
        incoming == 'esp32_pump' ||
        incoming.contains('aa69e0') ||
        incoming.contains('94b97e') ||
        incoming.startsWith('esp32_pump_')) {
      return _activeDevice != null;
    }

    // Only match if there is an actively registered device
    if (_activeDevice != null) {
      final activeId = _activeDevice!.id.trim().toLowerCase();
      if (incoming == activeId) return true;

      final cleanActive = activeId.replaceAll('esp32_pump_', '').replaceAll('esp32_', '');
      final cleanIncoming = incoming.replaceAll('esp32_pump_', '').replaceAll('esp32_', '');
      if (cleanActive.isNotEmpty && cleanIncoming.isNotEmpty &&
          (cleanActive == cleanIncoming || cleanActive.contains(cleanIncoming) || cleanIncoming.contains(cleanActive))) {
        return true;
      }

      if (_activeDevice!.macAddress.isNotEmpty) {
        final cleanMac = _activeDevice!.macAddress.toLowerCase().replaceAll(':', '');
        if (cleanIncoming.contains(cleanMac) || cleanMac.contains(cleanIncoming)) return true;
      }

      // Single active device paired: accept hardware updates
      return true;
    }

    return false;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHost = prefs.getString('mqtt_broker_host');
    if (savedHost != 'broker.emqx.io') {
      _brokerHost = AppConstants.mqttBrokerHost;
      await prefs.setString('mqtt_broker_host', _brokerHost);
    } else {
      _brokerHost = savedHost ?? AppConstants.mqttBrokerHost;
    }
    _brokerPort = prefs.getInt('mqtt_broker_port') ?? AppConstants.mqttBrokerPort;
    _brokerUsername = prefs.getString('mqtt_broker_user') ?? '';
    _brokerPassword = prefs.getString('mqtt_broker_pass') ?? '';

    notifyMotorStart = prefs.getBool('notify_motor_start') ?? true;
    notifyMotorStop = prefs.getBool('notify_motor_stop') ?? true;
    notifyLowLevel = prefs.getBool('notify_low_level') ?? true;
    notifyHighLevel = prefs.getBool('notify_high_level') ?? true;
    notifyAutoMode = prefs.getBool('notify_auto_mode') ?? true;

    await _loadTelemetryHistory();

    _isExplicitlyRemoved = prefs.getBool('hardware_explicitly_removed') ?? false;

    // Restore locally paired device from persistent storage ONLY if owned by current user
    const storage = FlutterSecureStorage();
    final currentEmail = (await storage.read(key: AppConstants.keyUserEmail))?.trim().toLowerCase() ?? '';
    final savedDevStr = prefs.getString('saved_paired_device');
    final savedOwnerEmail = prefs.getString('saved_paired_device_owner_email')?.trim().toLowerCase() ?? '';

    if (!_isExplicitlyRemoved &&
        savedDevStr != null &&
        savedDevStr.isNotEmpty &&
        currentEmail.isNotEmpty &&
        (savedOwnerEmail.isEmpty || savedOwnerEmail == currentEmail)) {
      try {
        final map = jsonDecode(savedDevStr) as Map<String, dynamic>;
        final restored = DeviceModel.fromJson(map);
        final savedPump = prefs.getString('saved_last_pump_state') ?? restored.pumpState;
        final savedMode = prefs.getString('saved_last_mode') ?? restored.mode;
        final lastHbMs = prefs.getInt('last_heartbeat_ms') ?? 0;
        final now = DateTime.now();
        final isRecentlyActive = (now.millisecondsSinceEpoch - lastHbMs) < 60000;
        final initialStatus = isRecentlyActive ? 'ONLINE' : (restored.status.isNotEmpty ? restored.status : 'OFFLINE');
        _activeDevice = DeviceModel(
          id: restored.id,
          name: restored.name,
          macAddress: restored.macAddress,
          status: initialStatus,
          pumpState: savedPump,
          mode: savedMode,
          wifiRssi: restored.wifiRssi,
          firmwareVersion: restored.firmwareVersion,
          lastSeen: isRecentlyActive ? now : restored.lastSeen,
        );
        if (isRecentlyActive) {
          _lastMainNodeHeartbeat = DateTime.fromMillisecondsSinceEpoch(lastHbMs);
          _lastCloudVerifiedOnline = now;
        }
        debugPrint('[HardwareStateService] Restored paired hardware: ${_activeDevice!.id} (status: $initialStatus) for $currentEmail');
      } catch (e) {
        debugPrint('[HardwareStateService] Restoring saved device notice: $e');
      }
    } else {
      _activeDevice = null;
    }

    if (!_isExplicitlyRemoved) {
      // Fetch latest hardware synchronized in cloud backend database for this account
      await fetchUserDevicesFromBackend();
    } else {
      _activeDevice = null;
    }

    // Preserve last known heartbeat if available from storage/session, otherwise verify in background
    _isVerifyingStatus = true;

    // Periodic State Evaluation Timer (checks hardware presence every 1000ms)
    _stateEvaluationTimer?.cancel();
    _stateEvaluationTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      final currentStatus = mainNodeStatus;
      final currentStatusStr = currentStatus == NodeStatus.online
          ? 'ONLINE'
          : (currentStatus == NodeStatus.stale ? 'STALE' : 'OFFLINE');

      if (_activeDevice != null && _activeDevice!.status != currentStatusStr) {
        _activeDevice = DeviceModel(
          id: _activeDevice!.id,
          name: _activeDevice!.name,
          macAddress: _activeDevice!.macAddress,
          status: currentStatusStr,
          pumpState: _activeDevice!.pumpState,
          mode: _activeDevice!.mode,
          wifiRssi: _activeDevice!.wifiRssi,
          firmwareVersion: _activeDevice!.firmwareVersion,
          lastSeen: _activeDevice!.lastSeen,
        );
        notifyListeners();
      }
    });

    // Bind listeners to MQTT message streams
    _bindMqttStreams();

    // Listen to live connection state changes
    mqttService.connectionNotifier.addListener(() {
      final wasConnected = _isMqttConnected;
      _isMqttConnected = mqttService.isConnected;
      if (_isMqttConnected && !wasConnected) {
        _offlineTickCount = 0;
        requestImmediateStatus();
      }
      notifyListeners();
    });

    // Connect to Cloud MQTT Broker
    await connectMqtt();
  }

  Timer? _hardwarePingTimer;
  bool _streamsBound = false;

  void _bindMqttStreams() {
    if (_streamsBound) return;
    _streamsBound = true;

    mqttService.statusStream.listen((data) {
      _handleStatusMessage(data);
    });

    mqttService.sensorStream.listen((data) {
      _handleSensorMessage(data);
    });

    mqttService.ackStream.listen((data) {
      _handleAckMessage(data);
    });

    mqttService.pongStream.listen((data) {
      _handlePongMessage(data);
    });

    mqttService.deviceStream.listen((data) {
      _handleDeviceSyncMessage(data);
    });

    _startHardwarePingLoop();
  }

  Future<void> _handleDeviceSyncMessage(Map<String, dynamic> data) async {
    try {
      final devId = (data['deviceId'] ?? data['id'] ?? data['nodeId'] ?? '').toString();
      if (devId.isEmpty || devId == 'esp32_pump_main') return;

      const storage = FlutterSecureStorage();
      final email = await storage.read(key: AppConstants.keyUserEmail);
      final cleanEmail = email?.trim().toLowerCase() ?? '';
      if (cleanEmail.isEmpty) return;

      if (_isExplicitlyRemoved) return;

      final msgEmail = (data['userEmail'] ?? data['userId'] ?? '').toString().toLowerCase();
      final isMatch = (msgEmail == cleanEmail);

      if (!isMatch) return;

      final devName = (data['name'] ?? 'HydroPulse Gateway').toString();
      final devMac = (data['macAddress'] ?? data['mac'] ?? '24:6F:28:94:B9:7E').toString();
      final rawPump = (data['pumpState'] ?? data['pump_state'] ?? 'OFF').toString().toUpperCase();
      final pumpNorm = (rawPump == 'ON' || rawPump == 'RUNNING' || rawPump == '1') ? 'ON' : 'OFF';
      final devMode = (data['mode'] ?? 'AUTO').toString().toUpperCase();
      final fwVer = (data['firmwareVersion'] ?? data['firmware_version'] ?? 'v2.0.2').toString();
      final rssi = data['wifiRssi'] ?? data['wifi_rssi'] ?? -65;

      final syncStatus = (data['status'] ?? (data['isOnline'] == true ? 'ONLINE' : 'OFFLINE')).toString().toUpperCase();
      final isVerified = syncStatus == 'ONLINE';

      _activeDevice = DeviceModel(
        id: devId,
        name: devName,
        macAddress: devMac,
        status: isVerified ? 'ONLINE' : 'OFFLINE',
        pumpState: pumpNorm,
        mode: devMode,
        wifiRssi: rssi is int ? rssi : -65,
        firmwareVersion: fwVer,
        lastSeen: DateTime.now(),
      );

      if (!isVerified) {
        _lastMainNodeHeartbeat = null;
      }

      await storage.write(key: AppConstants.keySelectedDeviceId, value: devId);
      notifyListeners();
      debugPrint('[HardwareStateService] Synchronized & activated device $devId ($devName) via Cloud MQTT');
    } catch (e) {
      debugPrint('[HardwareStateService] _handleDeviceSyncMessage error: $e');
    }
  }

  int _cloudPollTick = 0;
  void _startHardwarePingLoop() {
    _hardwarePingTimer?.cancel();
    _hardwarePingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isMqttConnected && _activeDevice != null) {
        sendHardwarePing();
      }
      _cloudPollTick++;
      // Dual-channel failover: every 3s verify presence via cloud REST if MQTT has no heartbeat
      if (_cloudPollTick % 6 == 0 && _activeDevice != null) {
        final now = DateTime.now();
        final hasMqttHeartbeat = _lastMainNodeHeartbeat != null &&
            now.difference(_lastMainNodeHeartbeat!).inMilliseconds <= 8000;
        if (!hasMqttHeartbeat) {
          _pollCloudHardwareStatus();
        }
      }
    });
  }

  Future<void> _pollCloudHardwareStatus() async {
    if (_activeDevice == null) return;
    try {
      final devId = _activeDevice!.id;
      final res = await apiClient.get('/devices/status', queryParameters: {'deviceId': devId});
      if (res.statusCode == 200 && res.data != null) {
        final map = res.data['data'] ?? res.data;
        if (map is Map<String, dynamic>) {
          final isOnline = map['isOnline'] == true || map['status'] == 'ONLINE';
          if (isOnline) {
            _lastCloudVerifiedOnline = DateTime.now();
            if (_activeDevice!.status != 'ONLINE') {
              _activeDevice = DeviceModel(
                id: _activeDevice!.id,
                name: _activeDevice!.name,
                macAddress: _activeDevice!.macAddress,
                status: 'ONLINE',
                pumpState: _activeDevice!.pumpState,
                mode: _activeDevice!.mode,
                wifiRssi: _activeDevice!.wifiRssi,
                firmwareVersion: _activeDevice!.firmwareVersion,
                lastSeen: DateTime.now(),
              );
              notifyListeners();
            }
          } else {
            _lastCloudVerifiedOnline = null;
            if (_activeDevice!.status != 'OFFLINE') {
              _activeDevice = DeviceModel(
                id: _activeDevice!.id,
                name: _activeDevice!.name,
                macAddress: _activeDevice!.macAddress,
                status: 'OFFLINE',
                pumpState: _activeDevice!.pumpState,
                mode: _activeDevice!.mode,
                wifiRssi: _activeDevice!.wifiRssi,
                firmwareVersion: _activeDevice!.firmwareVersion,
                lastSeen: _activeDevice!.lastSeen,
              );
              notifyListeners();
            }
          }
        }
      }
    } catch (_) {}
  }

  void sendHardwarePing() {
    if (!_isMqttConnected) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final pingId = 'ping_${nowMs % 100000}';
    final devId = _activeDevice?.id ?? 'esp32_pump_main';
    const userId = 'usr_demo_001';
    mqttService.publishPing(userId, devId, pingId, nowMs);
    if (devId != 'esp32_pump_000000') {
      mqttService.publishPing(userId, 'esp32_pump_000000', pingId, nowMs);
    }
  }


  void _handlePongMessage(Map<String, dynamic> data) {
    final incomingDevId = (data['deviceId'] ?? data['device_id'] ?? '').toString().trim();

    if (!_isMatchingDevice(incomingDevId)) {
      return;
    }

    final now = DateTime.now();
    if (_activeDevice == null) {
      return;
    }
    _lastMainNodeHeartbeat = now;
    _totalPacketsReceived++;

    if (data.containsKey('subNodeOnline')) {
      final bool isSubAlive = data['subNodeOnline'] == true;
      if (isSubAlive) {
        _lastSubNodePacket = now;
      } else {
        _lastSubNodePacket = null;
      }
    }

    final clientTs = (data['client_timestamp_ms'] ?? data['timestamp_ms'] ?? 0) as num;
    if (clientTs > 0) {
      final rtt = now.millisecondsSinceEpoch - clientTs.toInt();
      if (rtt >= 0 && rtt < 5000) {
        _lastCommandRttMs = rtt;
      }
    }

    final rawPumpState = (data['pumpState'] ?? data['pump_state'] ?? _activeDevice!.pumpState).toString().toUpperCase();
    final normalizedPumpState = (rawPumpState == 'ON' || rawPumpState == 'RUNNING' || rawPumpState == '1') ? 'ON' : 'OFF';
    final rawMode = (data['mode'] ?? _activeDevice!.mode).toString().toUpperCase();

    _activeDevice = DeviceModel(
      id: _activeDevice!.id,
      name: _activeDevice!.name,
      macAddress: _activeDevice!.macAddress,
      status: 'ONLINE',
      pumpState: normalizedPumpState,
      mode: rawMode.isNotEmpty ? rawMode : _activeDevice!.mode,
      wifiRssi: data['wifi_rssi'] ?? data['rssi'] ?? _activeDevice!.wifiRssi,
      firmwareVersion: data['firmware_version'] ?? _activeDevice!.firmwareVersion,
      lastSeen: now,
    );

    notifyListeners();
  }

  Future<bool> connectMqtt() async {
    _isMqttConnected = false;
    notifyListeners();

    final ok = await mqttService.connect(
      host: _brokerHost,
      port: _brokerPort,
      username: _brokerUsername.isNotEmpty ? _brokerUsername : null,
      password: _brokerPassword.isNotEmpty ? _brokerPassword : null,
    );

    _isMqttConnected = ok;
    if (ok) {
      _offlineTickCount = 0;
      sendHardwarePing();
      requestImmediateStatus();
      // Restore last known hardware state on reconnect (within 150ms)
      Future.delayed(const Duration(milliseconds: 150), _restoreHardwareState);
    }
    notifyListeners();
    return ok;
  }

  /// Re-publishes the last known pump state and mode to hardware on reconnect.
  /// This ensures hardware remembers its previous state after brief MQTT disconnects.
  Future<void> _restoreHardwareState() async {
    if (!_isMqttConnected || _activeDevice == null) return;
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('saved_last_mode') ?? _activeDevice!.mode;
    final savedPumpState = prefs.getString('saved_last_pump_state') ?? _activeDevice!.pumpState;
    final devId = _activeDevice!.id;

    // Re-sync mode to hardware & cloud
    mqttService.publishCommand('app_restore', devId, 'SET_MODE', {'mode': savedMode});
    apiClient.post('/command', data: {
      'command': 'SET_MODE',
      'action': 'SET_MODE',
      'deviceId': devId,
      'parameters': {'mode': savedMode},
    }).ignore();

    // Re-sync pump state — in MANUAL mode (AUTO mode manages itself)
    if (savedMode == 'MANUAL') {
      final cmd = (savedPumpState == 'ON') ? 'START_PUMP' : 'STOP_PUMP';
      mqttService.publishCommand('app_restore', devId, cmd, {'restored': true});
    }

    debugPrint('[HardwareStateService] Restored hardware state: mode=$savedMode, pump=$savedPumpState after reconnect');
  }

  Future<void> refresh() async {
    // Set verifying BEFORE any async work — prevents offline flash during the entire refresh
    _isVerifyingStatus = true;
    notifyListeners();

    try {
      // 1. Immediately ping hardware & request status via MQTT with zero delay
      if (!_isMqttConnected) {
        await connectMqtt();
      }
      sendHardwarePing();
      requestImmediateStatus();

      // 2. Refresh device profile from backend without wiping active telemetry
      await fetchUserDevicesFromBackend();
    } finally {
      // Extended 2000ms grace period — gives hardware time to respond to ping
      // before removing the 'verifying' guard that prevents false offline flash.
      Future.delayed(const Duration(milliseconds: 2000), () {
        _isVerifyingStatus = false;
        notifyListeners();
      });
    }
  }

  void requestImmediateStatus() {
    final devId = _activeDevice?.id ?? 'esp32_pump_000000';
    mqttService.publishCommand('app_refresh', devId, 'GET_STATUS', {});
  }

  Future<void> saveBrokerConfig({
    required String host,
    required int port,
    String username = '',
    String password = '',
  }) async {
    _brokerHost = host.trim();
    _brokerPort = port;
    _brokerUsername = username.trim();
    _brokerPassword = password.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mqtt_broker_host', _brokerHost);
    await prefs.setInt('mqtt_broker_port', _brokerPort);
    await prefs.setString('mqtt_broker_user', _brokerUsername);
    await prefs.setString('mqtt_broker_pass', _brokerPassword);

    notifyListeners();
    await connectMqtt();
  }

  void _handleStatusMessage(Map<String, dynamic> data) {
    final now = DateTime.now();
    final devId = (data['deviceId'] ?? data['device_id'] ?? '').toString().trim();

    if (!_isMatchingDevice(devId)) {
      return;
    }

    if (_activeDevice == null) {
      return;
    }

    // Automatically parse embedded sensor readings if present in status/heartbeat
    if (data.containsKey('waterLevel') || data.containsKey('water_level') || data.containsKey('waterLevelPct')) {
      final num? lvl = data['waterLevel'] ?? data['water_level'] ?? data['waterLevelPct'];
      if (lvl != null && lvl.toDouble() >= 0) {
        _handleSensorMessage(data);
      }
    }

    if (data.containsKey('emergencyStopped')) {
      _isEmergencyStopActive = data['emergencyStopped'] == true;
    }

    // Sub-Node status handling
    if (data.containsKey('subNodeOnline')) {
      final bool isSubAlive = data['subNodeOnline'] == true;
      if (isSubAlive) {
        _lastSubNodePacket = now;
      } else {
        _lastSubNodePacket = null;
      }
    }

    // Explicit LWT Offline (Ignore stale broker retained messages)
    final statusStr = (data['status'] ?? data['state'] ?? '').toString().toUpperCase();
    if (statusStr == 'OFFLINE') {
      final isRetained = data['_isRetained'] == true;
      if (isRetained) {
        debugPrint('[HardwareStateService] Ignored stale retained OFFLINE message from broker.');
        return;
      }
      _lastMainNodeHeartbeat = null;
      _activeDevice = DeviceModel(
        id: _activeDevice!.id,
        name: _activeDevice!.name,
        macAddress: _activeDevice!.macAddress,
        status: 'OFFLINE',
        pumpState: 'STOPPED',
        mode: _activeDevice!.mode,
        wifiRssi: _activeDevice!.wifiRssi,
        firmwareVersion: _activeDevice!.firmwareVersion,
        lastSeen: now,
      );
      notifyListeners();
      return;
    }

    // Record verified Main Node Heartbeat — INSTANT ONLINE
    _lastMainNodeHeartbeat = now;
    _offlineTickCount = 0;
    _totalPacketsReceived++;

    _persistHeartbeat(now);

    final rawPumpState = (data['pumpState'] ?? data['pump_state'] ?? _activeDevice!.pumpState).toString().toUpperCase();
    final normalizedPumpState = (rawPumpState == 'ON' || rawPumpState == 'RUNNING' || rawPumpState == 'START_PUMP' || rawPumpState == '1') ? 'ON' : 'OFF';

    // Anti-flapping pump state resolution
    String targetPumpState = normalizedPumpState;
    if (_pumpCommandLockUntil != null && DateTime.now().isBefore(_pumpCommandLockUntil!)) {
      if (normalizedPumpState == _expectedPumpState) {
        _pumpCommandLockUntil = null; // Hardware synchronized!
      } else {
        targetPumpState = _expectedPumpState ?? _activeDevice!.pumpState; // Hold optimistic state
      }
    }

    // Immediate command resolution if incoming hardware status reflects requested state
    if (_lastCommand != null && _lastCommand!.state == CommandTransitState.sending) {
      final requestedAction = _pendingCommandAction; // 'ON' or 'OFF'
      if (requestedAction == null || requestedAction == normalizedPumpState) {
        _commandTimeoutTimer?.cancel();
        _lastCommand!.state = CommandTransitState.acknowledged;
        _lastCommandRttMs = now.difference(_lastCommand!.sentAt).inMilliseconds;
        _lastCommand!.rttMs = _lastCommandRttMs;
        _pendingCommandAction = null;
        debugPrint('[Hardware State] Command ${_lastCommand!.commandId} confirmed via verified hardware status! RTT: ${_lastCommandRttMs}ms');
      }
    }

    final incomingMode = (data['mode'] != null && data['mode'].toString().isNotEmpty)
        ? data['mode'].toString().toUpperCase()
        : _activeDevice!.mode;

    // Anti-flapping mode resolution
    String targetMode = incomingMode;
    if (_modeCommandLockUntil != null && DateTime.now().isBefore(_modeCommandLockUntil!)) {
      if (incomingMode == _expectedMode) {
        _modeCommandLockUntil = null; // Hardware synchronized!
      } else {
        targetMode = _expectedMode ?? _activeDevice!.mode; // Hold optimistic mode
      }
    }

    final rssi = data['rssi'] ?? data['wifiRssi'] ?? data['wifi_rssi'] ?? _activeDevice!.wifiRssi;

    _activeDevice = DeviceModel(
      id: _activeDevice!.id,
      name: _activeDevice!.name,
      macAddress: _activeDevice!.macAddress,
      status: 'ONLINE',
      pumpState: targetPumpState,
      mode: targetMode,
      wifiRssi: rssi is int ? rssi : _activeDevice!.wifiRssi,
      firmwareVersion: data['fw_version'] ?? data['firmware_version'] ?? _activeDevice!.firmwareVersion,
      lastSeen: now,
    );

    // Check for motor start / stop state change notifications
    if (_lastKnownPumpState != null && _lastKnownPumpState != targetPumpState) {
      if (targetPumpState == 'ON') {
        _pumpCycleCount++;
        if (targetMode == 'AUTO') {
          addLiveAlert('⚡ Motor Started (Automatic Mode)', 'Autonomous controller started pump as water reached start threshold.', 'motor_start', level: AlertLevel.info);
        } else {
          addLiveAlert('⚡ Motor Started (Manual Mode)', 'Water pump motor started manually by user.', 'motor_start', level: AlertLevel.info);
        }
      } else if (targetPumpState == 'OFF') {
        if (targetMode == 'AUTO') {
          addLiveAlert('🛑 Motor Stopped (Automatic Mode)', 'Autonomous controller stopped pump at target full level.', 'motor_stop', level: AlertLevel.info);
        } else {
          addLiveAlert('🛑 Motor Stopped (Manual Mode)', 'Water pump cycle stopped.', 'motor_stop', level: AlertLevel.info);
        }
      }
    }
    _lastKnownPumpState = targetPumpState;

    _pumpStatus = PumpStatusModel(
      state: targetPumpState,
      mode: targetMode,
      runningDurationSeconds: data['runningDurationSeconds'] ?? data['running_duration_seconds'] ?? 0,
      safetyStatus: data['safetyStatus'] ?? data['safety_status'] ?? 'NORMAL',
      timestamp: now,
    );

    notifyListeners();
  }

  void _handleSensorMessage(Map<String, dynamic> data) {
    final now = DateTime.now();
    final incomingDevId = (data['deviceId'] ?? data['device_id'] ?? '').toString().trim();

    if (!_isMatchingDevice(incomingDevId)) {
      return;
    }

    final rawLevel = (data['waterLevel'] ?? data['water_level'] ?? data['waterLevelPct'] ?? data['water_level_pct'] ?? -1.0 as num).toDouble();
    if (data.containsKey('subNodeOnline')) {
      final bool isSubAlive = data['subNodeOnline'] == true;
      if (isSubAlive) {
        _lastSubNodePacket = now;
      } else {
        _lastSubNodePacket = null;
      }
    } else if (data['nodeType'] == 'SUB_NODE' || rawLevel >= 0) {
      _lastSubNodePacket = now;
    }

    _lastMainNodeHeartbeat = now;
    _totalPacketsReceived++;
    _persistHeartbeat(now);

    if (rawLevel < 0 || subNodeStatus == NodeStatus.offline) {
      notifyListeners();
      return;
    }

    final levelPct = rawLevel;
    final flowRate = (data['flowRate'] ?? data['flow_rate'] ?? data['flowRateLpm'] ?? data['flow_rate_lpm'] ?? 0.0 as num).toDouble();
    final tempC = (data['temperature'] ?? data['temp_c'] ?? data['waterTempC'] ?? data['temperature_c'] ?? 25.0 as num).toDouble();
    final tds = (data['tds'] ?? data['tds_ppm'] ?? 120 as num).toInt();
    final battV = (data['battery'] ?? data['battery_voltage'] ?? 3.95 as num).toDouble();
    final battPct = ((battV - 3.3) / 0.9 * 100).clamp(0, 100).toInt();

    final volumeLiters = (levelPct / 100.0) * 5000.0;

    _sensorData = SensorDataModel(
      subNodeId: data['subNodeId'] ?? data['sub_node_id'] ?? data['nodeId'] ?? 'tank_node_001',
      seqNum: data['sequence'] ?? data['seq_num'] ?? 1,
      waterLevelPct: levelPct,
      waterLevelCm: (levelPct / 100.0) * 200.0,
      flowRateLpm: flowRate,
      totalWaterLiters: volumeLiters,
      tdsPpm: tds,
      temperatureC: tempC,
      batteryVoltage: battV,
      batteryPct: battPct,
      timestamp: now,
    );

    // Record sample in historical telemetry store
    _recordTelemetrySample(levelPct, flowRate, volumeLiters);

    // Live Tank Threshold Alerts
    if (levelPct <= 20.0 && _lastAlertedLowTankLevel != true) {
      _lastAlertedLowTankLevel = true;
      addLiveAlert('⚠️ Tank Level Low', 'Water volume is low at ${levelPct.toStringAsFixed(0)}%. Auto-refill recommended.', 'low_level', level: AlertLevel.warning);
    } else if (levelPct > 25.0) {
      _lastAlertedLowTankLevel = false;
    }

    if (levelPct >= 90.0 && _lastAlertedHighTankLevel != true) {
      _lastAlertedHighTankLevel = true;
      addLiveAlert('🚨 Tank Capacity Full', 'Water tank reached ${levelPct.toStringAsFixed(0)}% capacity.', 'high_level', level: AlertLevel.info);
    } else if (levelPct < 85.0) {
      _lastAlertedHighTankLevel = false;
    }

    if (data.containsKey('pumpState') || data.containsKey('pump_state')) {
      final pState = (data['pumpState'] ?? data['pump_state']).toString().toUpperCase();
      final normState = (pState == 'ON' || pState == 'RUNNING' || pState == '1') ? 'ON' : 'OFF';

      String effectiveState = normState;
      if (_pumpCommandLockUntil != null && DateTime.now().isBefore(_pumpCommandLockUntil!)) {
        if (normState == _expectedPumpState) {
          _pumpCommandLockUntil = null;
        } else {
          effectiveState = _expectedPumpState ?? _activeDevice!.pumpState;
        }
      }

      if (_lastKnownPumpState != null && _lastKnownPumpState != effectiveState) {
        if (effectiveState == 'ON') {
          _pumpCycleCount++;
          addLiveAlert('Motor Started', 'Water pump is actively running.', 'motor');
        } else if (effectiveState == 'OFF') {
          addLiveAlert('Motor Stopped', 'Water pump cycle stopped.', 'motor');
        }
      }
      _lastKnownPumpState = effectiveState;

      if (_pumpStatus != null) {
        _pumpStatus = PumpStatusModel(
          state: effectiveState,
          mode: _pumpStatus!.mode,
          runningDurationSeconds: _pumpStatus!.runningDurationSeconds,
          safetyStatus: _pumpStatus!.safetyStatus,
          timestamp: now,
        );
      }
    }

    if (_activeDevice != null && _activeDevice!.status != 'ONLINE') {
      _activeDevice = DeviceModel(
        id: _activeDevice!.id,
        name: _activeDevice!.name,
        macAddress: _activeDevice!.macAddress,
        status: 'ONLINE',
        pumpState: _activeDevice!.pumpState,
        mode: _activeDevice!.mode,
        wifiRssi: _activeDevice!.wifiRssi,
        firmwareVersion: _activeDevice!.firmwareVersion,
        lastSeen: now,
      );
    }

    notifyListeners();
  }

  void _handleAckMessage(Map<String, dynamic> data) {
    final cmdId = (data['commandId'] ?? data['command_id'] ?? '').toString();
    final pumpState = (data['pumpState'] ?? data['pumpStatus'] ?? data['pump'] ?? '').toString().toUpperCase();
    final now = DateTime.now();

    if (data.containsKey('emergencyStopped')) {
      _isEmergencyStopActive = data['emergencyStopped'] == true;
    }

    _isVerifyingStatus = false;
    _lastMainNodeHeartbeat = now;
    _offlineTickCount = 0;

    // Check if ACK matches our active command (supports direct cmdId, raw fast-path, or active in-flight transit)
    final isAckForActiveCmd = _lastCommand != null && (
      cmdId.isEmpty ||
      cmdId == 'cmd_fast_raw' ||
      cmdId == 'cmd_direct' ||
      _lastCommand!.commandId == cmdId ||
      _lastCommand!.state == CommandTransitState.sending
    );

    if (isAckForActiveCmd) {
      _commandTimeoutTimer?.cancel();
      final isSuccess = (data['status'] == 'success' || data['status'] == 'SUCCESS' || data['success'] == true);
      if (isSuccess) {
        _lastCommand!.state = CommandTransitState.acknowledged;
        _lastCommandRttMs = now.difference(_lastCommand!.sentAt).inMilliseconds;
        _lastCommand!.rttMs = _lastCommandRttMs;
        debugPrint('[Command ACK] Command ${_lastCommand!.commandId} confirmed by hardware! RTT: ${_lastCommandRttMs}ms');
      } else {
        _lastCommand!.state = CommandTransitState.failed;
        final errMsg = data['message'] ?? data['error'] ?? 'Hardware rejected command';
        debugPrint('[Command ACK] Command ${_lastCommand!.commandId} rejected: $errMsg');
        addLiveAlert('Command Blocked', errMsg.toString(), 'error', level: AlertLevel.warning);
      }
      _pendingCommandAction = null;
    }

    if (pumpState.isNotEmpty && _activeDevice != null) {
      final stateStr = (pumpState == 'ON' || pumpState == 'RUNNING') ? 'ON' : 'OFF';
      _pumpCommandLockUntil = null; // Clear lock on verified ACK

      _activeDevice = DeviceModel(
        id: _activeDevice!.id,
        name: _activeDevice!.name,
        macAddress: _activeDevice!.macAddress,
        status: 'ONLINE',
        pumpState: stateStr,
        mode: _activeDevice!.mode,
        wifiRssi: _activeDevice!.wifiRssi,
        firmwareVersion: _activeDevice!.firmwareVersion,
        lastSeen: now,
      );

      _pumpStatus = PumpStatusModel(
        state: stateStr,
        mode: _activeDevice!.mode,
        runningDurationSeconds: _pumpStatus?.runningDurationSeconds ?? 0,
        safetyStatus: _pumpStatus?.safetyStatus ?? 'NORMAL',
        timestamp: now,
      );

      SharedPreferences.getInstance().then((p) => p.setString('saved_last_pump_state', stateStr));
      _persistActiveDevice();
    }

    notifyListeners();
  }

  Future<void> _persistHeartbeat(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_heartbeat_ms', time.millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> registerPairedDevice({
    required String deviceId,
    required String name,
    required String macAddress,
    String? ipAddress,
    String? userEmail,
  }) async {
    _isExplicitlyRemoved = false;
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hardware_explicitly_removed');
    await prefs.setInt('last_heartbeat_ms', now.millisecondsSinceEpoch);

    const storage = FlutterSecureStorage();
    String ownerEmail = (userEmail ?? '').trim().toLowerCase();
    if (ownerEmail.isEmpty) {
      ownerEmail = (await storage.read(key: AppConstants.keyUserEmail))?.trim().toLowerCase() ??
          prefs.getString(AppConstants.keyUserEmail)?.trim().toLowerCase() ??
          prefs.getString('saved_paired_device_owner_email')?.trim().toLowerCase() ?? '';
    }

    _lastMainNodeHeartbeat = now;
    _lastCloudVerifiedOnline = now;

    _activeDevice = DeviceModel(
      id: deviceId,
      name: name,
      macAddress: macAddress,
      status: 'ONLINE',
      pumpState: 'OFF',
      mode: 'AUTO',
      wifiRssi: -65,
      firmwareVersion: AppConstants.appVersion,
      lastSeen: now,
    );

    await prefs.setString('saved_paired_device', jsonEncode(_activeDevice!.toJson()));
    if (ownerEmail.isNotEmpty) {
      await prefs.setString('saved_paired_device_owner_email', ownerEmail);
      await prefs.setString(AppConstants.keyUserEmail, ownerEmail);
    }
    await storage.write(key: AppConstants.keySelectedDeviceId, value: deviceId);
    await prefs.setString('saved_selected_device_id', deviceId);

    notifyListeners();
    await syncDeviceToBackend(_activeDevice!);
    notifyListeners();
  }

  Future<void> _persistActiveDevice() async {
    if (_activeDevice == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_paired_device', jsonEncode(_activeDevice!.toJson()));
      const storage = FlutterSecureStorage();
      final currentEmail = (await storage.read(key: AppConstants.keyUserEmail))?.trim().toLowerCase() ?? '';
      if (currentEmail.isNotEmpty) {
        await prefs.setString('saved_paired_device_owner_email', currentEmail);
      }
    } catch (_) {}
  }

  Future<void> _persistTelemetryHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _telemetryHistory.map((p) => p.toMap()).toList();
      await prefs.setString('telemetry_history_samples', jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _loadTelemetryHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('telemetry_history_samples');
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _telemetryHistory.clear();
        for (final item in list) {
          _telemetryHistory.add(TelemetryDataPoint.fromMap(item as Map<String, dynamic>));
        }
      }
    } catch (_) {}
    if (_telemetryHistory.isEmpty) {
      _seedRealisticTelemetryHistory();
    }
  }

  Future<void> removeDevice() async {
    final devId = _activeDevice?.id;
    if (devId != null && devId.isNotEmpty) {
      // 1. Dispatch reset & remove commands to hardware over MQTT
      mqttService.publishCommand('app_remove', devId, 'FACTORY_RESET', {'action': 'FACTORY_RESET'});
      mqttService.publishCommand('app_remove', devId, 'RESET', {'action': 'RESET'});
      mqttService.publishCommand('app_remove', devId, 'REMOVE', {'action': 'REMOVE'});
    }

    _isExplicitlyRemoved = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hardware_explicitly_removed', true);
    await prefs.remove('saved_paired_device');
    await prefs.remove('last_heartbeat_ms');
    const storage = FlutterSecureStorage();
    await storage.delete(key: AppConstants.keySelectedDeviceId);

    _activeDevice = null;
    _sensorData = null;
    _pumpStatus = null;
    _lastMainNodeHeartbeat = null;
    _lastSubNodePacket = null;
    _liveAlerts.clear();

    if (devId != null && devId.isNotEmpty) {
      try {
        final email = await storage.read(key: AppConstants.keyUserEmail);
        final token = await storage.read(key: AppConstants.keyAccessToken);
        await apiClient.delete(
          '/devices/$devId',
          options: Options(
            headers: {
              if (email != null && email.isNotEmpty) 'x-user-email': email.trim().toLowerCase(),
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
          ),
        );
        await apiClient.post(
          '/devices/unpair',
          data: {'deviceId': devId},
          options: Options(
            headers: {
              if (email != null && email.isNotEmpty) 'x-user-email': email.trim().toLowerCase(),
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
          ),
        );
      } catch (e) {
        debugPrint('[HardwareStateService] Notice unpairing device from cloud: $e');
      }
    }
    _isEmergencyStopActive = false;
    _previousMode = null;
    notifyListeners();
  }

  Future<void> onUserLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_paired_device');
      await prefs.remove('last_heartbeat_ms');
    } catch (_) {}
    _activeDevice = null;
    _sensorData = null;
    _pumpStatus = null;
    _lastMainNodeHeartbeat = null;
    _lastSubNodePacket = null;
    _liveAlerts.clear();
    _telemetryHistory.clear();
    _isEmergencyStopActive = false;
    _previousMode = null;
    notifyListeners();
    debugPrint('[HardwareStateService] User logged out. All hardware state cleared.');
  }

  void sendPumpCommand(String command, {Map<String, dynamic>? params}) {
    if (_activeDevice == null) return;

    final normCmd = command.toUpperCase();
    if (normCmd == 'SET_MODE') {
      final modeStr = (params?['mode'] ?? 'AUTO').toString().toUpperCase();
      setMode(modeStr);
      return;
    }

    final isTurningOn = (normCmd == 'START_PUMP' || normCmd == 'PUMP_ON' || normCmd == 'ON');
    final newState = isTurningOn ? 'ON' : 'OFF';
    _pendingCommandAction = newState;

    // Explicit manual actuation: ensure system mode is switched to MANUAL so firmware doesn't trip on AUTO rules
    if (isTurningOn && _activeDevice?.mode != 'MANUAL') {
      setMode('MANUAL');
    }

    final cmdId = 'cmd_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecond % 1000)}';
    _lastCommand = PendingCommand(
      commandId: cmdId,
      command: command,
      sentAt: DateTime.now(),
      state: CommandTransitState.sending,
    );

    // Cancel any previous timeout timer and arm a strict 5000ms command timeout
    _commandTimeoutTimer?.cancel();
    _commandTimeoutTimer = Timer(const Duration(milliseconds: 5000), () {
      if (_lastCommand?.commandId == cmdId && _lastCommand?.state == CommandTransitState.sending) {
        _lastCommand?.state = CommandTransitState.failed;
        _pendingCommandAction = null;
        debugPrint('[HardwareStateService] ⚠️ Command $command ($cmdId) timed out after 5000ms with no hardware ACK.');
        addLiveAlert('Command Timeout', 'ESP32 hardware did not confirm $command within 5 seconds.', 'error', level: AlertLevel.warning);
        notifyListeners();
      }
    });

    // Send via MQTT with command_id and action
    final cmdPayload = {
      'command_id': cmdId,
      'commandId': cmdId,
      'action': isTurningOn ? 'START' : 'STOP',
      'command': command,
      'mode': 'MANUAL',
      ...?params,
    };
    mqttService.publishCommand(
      'user_app',
      _activeDevice!.id,
      command,
      cmdPayload,
    );

    // Fast Dual-Channel REST sync with authoritative ACK fallback
    final devId = _activeDevice!.id;
    apiClient.post('/command', data: {
      'command': command,
      'action': isTurningOn ? 'START' : 'STOP',
      'command_id': cmdId,
      'commandId': cmdId,
      'deviceId': devId,
      'parameters': cmdPayload,
    }).then((res) {
      if (res.statusCode == 200 && _lastCommand?.commandId == cmdId && _lastCommand?.state == CommandTransitState.sending) {
        _commandTimeoutTimer?.cancel();
        _lastCommand?.state = CommandTransitState.acknowledged;
        _lastCommandRttMs = DateTime.now().difference(_lastCommand!.sentAt).inMilliseconds;
        _lastCommand!.rttMs = _lastCommandRttMs;
        _pendingCommandAction = null;
        debugPrint('[REST Cloud ACK] Command $cmdId confirmed via cloud relay! RTT: ${_lastCommandRttMs}ms');
        notifyListeners();
      }
    }).catchError((_) {});

    notifyListeners();
  }

  void sendEmergencyStop() {
    if (_activeDevice == null) return;
    _isEmergencyStopActive = true;
    _previousMode = _activeDevice!.mode;

    // 800ms lock window to prevent bounce while keeping status immediate
    _expectedPumpState = 'OFF';
    _pumpCommandLockUntil = DateTime.now().add(const Duration(milliseconds: 800));

    final cmdId = 'es_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    _lastCommand = PendingCommand(
      commandId: cmdId,
      command: 'EMERGENCY_STOP',
      sentAt: DateTime.now(),
      state: CommandTransitState.sending,
    );

    mqttService.publishCommand(
      'user_app',
      _activeDevice!.id,
      'EMERGENCY_STOP',
      {'immediate': true, 'reason': 'USER_EMERGENCY_BUTTON'},
    );

    // Fast Dual-Channel REST sync for Emergency Stop
    final devId = _activeDevice!.id;
    apiClient.post('/command', data: {
      'command': 'EMERGENCY_STOP',
      'action': 'EMERGENCY_STOP',
      'deviceId': devId,
      'parameters': {'immediate': true},
    }).ignore();

    apiClient.post('/telemetry', data: {
      'pumpRunning': false,
      'pump_running': false,
      'pumpState': 'OFF',
      'pump_state': 'OFF',
      'mode': _activeDevice!.mode,
      'deviceId': devId,
    }).ignore();

    _pumpStatus = PumpStatusModel(
      state: 'OFF',
      mode: _activeDevice!.mode,
      runningDurationSeconds: 0,
      safetyStatus: 'EMERGENCY_STOP',
      timestamp: DateTime.now(),
    );

    _activeDevice = DeviceModel(
      id: _activeDevice!.id,
      name: _activeDevice!.name,
      macAddress: _activeDevice!.macAddress,
      status: _activeDevice!.status,
      pumpState: 'OFF',
      mode: _activeDevice!.mode,
      wifiRssi: _activeDevice!.wifiRssi,
      firmwareVersion: _activeDevice!.firmwareVersion,
      lastSeen: DateTime.now(),
    );

    addLiveAlert('Emergency Stop Activated', 'Water pump motor relay halted immediately.', 'critical');
    notifyListeners();
  }

  void clearEmergencyStop() {
    if (_activeDevice == null) return;
    _isEmergencyStopActive = false;
    _pumpCommandLockUntil = null;
    _expectedPumpState = null;

    final cmdId = 'ces_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    _lastCommand = PendingCommand(
      commandId: cmdId,
      command: 'CLEAR_EMERGENCY',
      sentAt: DateTime.now(),
      state: CommandTransitState.sending,
    );

    mqttService.publishCommand(
      'user_app',
      _activeDevice!.id,
      'CLEAR_EMERGENCY',
      {'immediate': true, 'reason': 'USER_CLEAR_EMERGENCY'},
    );

    final devId = _activeDevice!.id;
    apiClient.post('/command', data: {
      'command': 'CLEAR_EMERGENCY',
      'action': 'CLEAR_EMERGENCY',
      'deviceId': devId,
      'parameters': {'immediate': true},
    }).ignore();

    final restoreMode = _previousMode ?? 'AUTO';
    setMode(restoreMode);

    addLiveAlert('Emergency Stop Cleared', 'Normal pump operation and controls unlocked.', 'motor');
    notifyListeners();
  }

  void setMode(String mode) {
    final normalizedMode = mode.toUpperCase();
    if (_activeDevice == null) {
      const fallbackDevId = 'esp32_pump_AA69E0';
      _activeDevice = DeviceModel(
        id: fallbackDevId,
        name: 'HydroPulse Gateway',
        macAddress: '24:6F:28:94:B9:7E',
        status: 'ONLINE',
        pumpState: 'OFF',
        mode: normalizedMode,
        wifiRssi: -65,
        firmwareVersion: 'v2.2.3',
        lastSeen: DateTime.now(),
      );
    }
    _previousMode = _activeDevice!.mode;

    // 5000ms optimistic mode lock — prevents in-flight status packets from flapping mode.
    // Clears immediately upon matching hardware state ACK/echo.
    _expectedMode = normalizedMode;
    _modeCommandLockUntil = DateTime.now().add(const Duration(milliseconds: 5000));
    SharedPreferences.getInstance().then((p) => p.setString('saved_last_mode', normalizedMode));

    _activeDevice = DeviceModel(
      id: _activeDevice!.id,
      name: _activeDevice!.name,
      macAddress: _activeDevice!.macAddress,
      status: _activeDevice!.status,
      pumpState: _activeDevice!.pumpState,
      mode: normalizedMode,
      wifiRssi: _activeDevice!.wifiRssi,
      firmwareVersion: _activeDevice!.firmwareVersion,
      lastSeen: _activeDevice!.lastSeen,
    );

    if (_pumpStatus != null) {
      _pumpStatus = PumpStatusModel(
        state: _pumpStatus!.state,
        mode: normalizedMode,
        runningDurationSeconds: _pumpStatus!.runningDurationSeconds,
        safetyStatus: _pumpStatus!.safetyStatus,
        timestamp: DateTime.now(),
      );
    }

    _persistActiveDevice();
    notifyListeners();

    final cmdId = 'cmd_mode_${DateTime.now().millisecondsSinceEpoch}';
    // Fire MQTT mode command immediately (zero await)
    mqttService.publishCommand(
      'user_app',
      _activeDevice!.id,
      'SET_MODE',
      {
        'mode': normalizedMode,
        'action': normalizedMode,
        'commandId': cmdId,
        'command_id': cmdId,
      },
    );

    // Also sync mode to REST backend (fire-and-forget, no latency impact)
    final devId = _activeDevice!.id;
    apiClient.post('/command', data: {
      'command': 'SET_MODE',
      'action': 'SET_MODE',
      'mode': normalizedMode,
      'commandId': cmdId,
      'command_id': cmdId,
      'deviceId': devId,
      'parameters': {'mode': normalizedMode},
    }).ignore();
  }

  void saveAutomationRules({
    required double autoStartLevel,
    required double autoStopLevel,
    required bool dryRunProtection,
    int maxRuntimeMins = 30,
  }) {
    if (_activeDevice == null) return;
    mqttService.publishCommand(
      'user_app',
      _activeDevice!.id,
      'SET_RULES',
      {
        'autoStartLevel': autoStartLevel,
        'auto_start_level_pct': autoStartLevel,
        'autoStopLevel': autoStopLevel,
        'auto_stop_level_pct': autoStopLevel,
        'dryRunProtection': dryRunProtection,
        'maxRuntimeMins': maxRuntimeMins,
      },
    );
  }

  @override
  void dispose() {
    _hardwarePingTimer?.cancel();
    _stateEvaluationTimer?.cancel();
    _verificationTimer?.cancel();
    super.dispose();
  }
}

final hardwareStateService = HardwareStateService();
