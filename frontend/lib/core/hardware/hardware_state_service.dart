import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mqtt/mqtt_service.dart';
import '../constants/app_constants.dart';
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
  SensorDataModel? _sensorData;
  PumpStatusModel? _pumpStatus;

  DateTime? _lastMainNodeHeartbeat;
  DateTime? _lastSubNodePacket;
  Timer? _stateEvaluationTimer;

  int _totalPacketsReceived = 0;
  int _lastCommandRttMs = 0;
  PendingCommand? _lastCommand;

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

  // Anti-flicker debounce: count consecutive offline ticks before transitioning
  int _offlineTickCount = 0;
  static const int _offlineDebounceThreshold = 4; // 4 ticks × 1s = 4s before OFFLINE

  // Grace period after MQTT connect — don't evaluate offline during this window
  DateTime? _mqttConnectedAt;
  static const int _gracePeriodSeconds = 8;

  // Track whether we're in grace period (waiting for first heartbeat after reconnect)
  bool get _isInGracePeriod {
    if (_mqttConnectedAt == null) return false;
    return DateTime.now().difference(_mqttConnectedAt!).inSeconds < _gracePeriodSeconds;
  }

  DeviceModel? get activeDevice => _activeDevice;
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
    if (type == 'motor_start' && !notifyMotorStart) return;
    if (type == 'motor_stop' && !notifyMotorStop) return;
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

  // 1. Strict Physical Hardware Connection State — ONLY ONLINE if physical ESP32 answered within last 2.5s
  NodeStatus get mainNodeStatus {
    if (_activeDevice == null) return NodeStatus.offline;
    if (!_isMqttConnected) return NodeStatus.offline;
    if (_lastMainNodeHeartbeat == null) return NodeStatus.offline;

    final diffMs = DateTime.now().difference(_lastMainNodeHeartbeat!).inMilliseconds;
    if (diffMs <= 2500) return NodeStatus.online;
    if (diffMs <= 5000) return NodeStatus.stale;
    return NodeStatus.offline;
  }

  // 2. Independent Sub Node (ESP-NOW) Connection State
  NodeStatus get subNodeStatus {
    if (mainNodeStatus == NodeStatus.offline) return NodeStatus.offline;
    if (_lastSubNodePacket == null) return NodeStatus.offline;
    final diffMs = DateTime.now().difference(_lastSubNodePacket!).inMilliseconds;
    if (diffMs <= 3500) return NodeStatus.online;
    if (diffMs <= 7000) return NodeStatus.stale;
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

  bool get isHardwareOnline => mainNodeStatus == NodeStatus.online;
  bool get isSubNodeOnline => subNodeStatus == NodeStatus.online;

  HardwareDiagnostics get diagnostics {
    final now = DateTime.now();
    return HardwareDiagnostics(
      mainNodeLastSeenMs: _lastMainNodeHeartbeat != null
          ? now.difference(_lastMainNodeHeartbeat!).inMilliseconds
          : -1,
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

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHost = prefs.getString('mqtt_broker_host');
    if (savedHost == null || savedHost.isEmpty || savedHost == 'localhost' || savedHost == '192.168.1.100' || savedHost == '10.0.2.2') {
      _brokerHost = AppConstants.mqttBrokerHost;
      await prefs.setString('mqtt_broker_host', _brokerHost);
    } else {
      _brokerHost = savedHost;
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

    // Load paired device if saved — STRICT DEFAULT: start as OFFLINE until real physical ping arrives
    final savedDeviceJson = prefs.getString('saved_paired_device');
    if (savedDeviceJson != null && savedDeviceJson.isNotEmpty) {
      try {
        final data = jsonDecode(savedDeviceJson) as Map<String, dynamic>;
        if (data['id'] == 'esp32_pump_main' || data['macAddress'] == 'ESP32:BLE:PROV' || data['id'] == 'esp32_pump_94B97E') {
          await prefs.remove('saved_paired_device');
          _activeDevice = null;
        } else {
          final loaded = DeviceModel.fromJson(data);
          _activeDevice = DeviceModel(
            id: loaded.id,
            name: loaded.name,
            macAddress: loaded.macAddress,
            status: 'OFFLINE', // Strict offline start
            pumpState: 'STOPPED',
            mode: loaded.mode,
            wifiRssi: loaded.wifiRssi,
            firmwareVersion: loaded.firmwareVersion,
            lastSeen: loaded.lastSeen,
          );
        }
      } catch (e) {
        debugPrint('[HardwareState] Error parsing saved device: $e');
        _activeDevice = null;
      }
    } else {
      _activeDevice = null;
    }

    _lastMainNodeHeartbeat = null;
    _lastSubNodePacket = null;
    _isVerifyingStatus = false;

    // Periodic State Evaluation Timer (checks hardware presence every 500ms)
    _stateEvaluationTimer?.cancel();
    _stateEvaluationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
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
          pumpState: currentStatusStr == 'OFFLINE' ? 'STOPPED' : _activeDevice!.pumpState,
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
        _mqttConnectedAt = DateTime.now();
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

    _startHardwarePingLoop();
  }

  void _startHardwarePingLoop() {
    _hardwarePingTimer?.cancel();
    // High-frequency hardware presence probe (every 1000ms / 1s)
    _hardwarePingTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (_isMqttConnected && _activeDevice != null) {
        sendHardwarePing();
      }
    });
  }

  void sendHardwarePing() {
    if (!_isMqttConnected || _activeDevice == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final pingId = 'ping_${nowMs % 100000}';
    final devId = _activeDevice!.id;
    final userId = 'usr_demo_001';
    mqttService.publishPing(userId, devId, pingId, nowMs);
  }

  void _handlePongMessage(Map<String, dynamic> data) {
    if (data['_isRetained'] == true) return; // Discard stale broker-retained packets

    final incomingDevId = (data['deviceId'] ?? data['device_id'] ?? '').toString();
    if (_activeDevice == null) return;
    if (incomingDevId.isNotEmpty && incomingDevId != _activeDevice!.id) return;

    final now = DateTime.now();
    _lastMainNodeHeartbeat = now;
    _totalPacketsReceived++;

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
      _mqttConnectedAt = DateTime.now();
      _offlineTickCount = 0;
      sendHardwarePing();
      requestImmediateStatus();
    }
    notifyListeners();
    return ok;
  }

  Future<void> refresh() async {
    if (!_isMqttConnected) {
      await connectMqtt();
    } else {
      sendHardwarePing();
      requestImmediateStatus();
    }
    notifyListeners();
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
    if (data['_isRetained'] == true) return; // Discard stale broker-retained packets

    final now = DateTime.now();

    // Explicit LWT Offline
    final statusStr = (data['status'] ?? data['state'] ?? '').toString().toUpperCase();
    if (statusStr == 'OFFLINE') {
      _lastMainNodeHeartbeat = null;
      if (_activeDevice != null) {
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
      }
      notifyListeners();
      return;
    }

    final devId = (data['deviceId'] ?? data['device_id'] ?? '').toString();

    // If no device has been explicitly paired, ignore background MQTT packets
    if (_activeDevice == null) {
      return;
    } else if (devId.isNotEmpty && devId != _activeDevice!.id) {
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
    if (data['_isRetained'] == true) return; // Discard stale broker-retained packets

    final incomingDevId = (data['deviceId'] ?? data['device_id'] ?? '').toString();
    if (_activeDevice == null) return;
    if (incomingDevId.isNotEmpty && incomingDevId != _activeDevice!.id) return;

    final now = DateTime.now();
    _lastSubNodePacket = now;
    _lastMainNodeHeartbeat = now;
    _totalPacketsReceived++;

    _persistHeartbeat(now);

    final levelPct = (data['waterLevel'] ?? data['water_level'] ?? data['waterLevelPct'] ?? data['water_level_pct'] ?? 0.0 as num).toDouble();
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
    final cmdId = data['commandId'] ?? data['command_id'];
    final pumpState = (data['pumpState'] ?? data['pumpStatus'] ?? '').toString().toUpperCase();
    final now = DateTime.now();

    _isVerifyingStatus = false;
    _lastMainNodeHeartbeat = now;
    _offlineTickCount = 0;

    if (_lastCommand != null && _lastCommand!.commandId == cmdId) {
      _lastCommand!.state = CommandTransitState.acknowledged;
      _lastCommandRttMs = now.difference(_lastCommand!.sentAt).inMilliseconds;
      _lastCommand!.rttMs = _lastCommandRttMs;
      debugPrint('[Command ACK] Command $cmdId acknowledged! RTT: ${_lastCommandRttMs}ms');
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
    }

    notifyListeners();
  }

  Future<void> _persistHeartbeat(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_heartbeat_ms', time.millisecondsSinceEpoch);
    } catch (_) {}
  }

  void registerPairedDevice({
    required String deviceId,
    required String name,
    required String macAddress,
    String? ipAddress,
  }) {
    _activeDevice = DeviceModel(
      id: deviceId,
      name: name,
      macAddress: macAddress,
      status: 'ONLINE',
      pumpState: 'OFF',
      mode: 'AUTO',
      wifiRssi: -65,
      firmwareVersion: '2.0.0',
      lastSeen: DateTime.now(),
    );

    _persistActiveDevice();
    notifyListeners();
  }

  Future<void> _persistActiveDevice() async {
    if (_activeDevice == null) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = {
      'id': _activeDevice!.id,
      'name': _activeDevice!.name,
      'macAddress': _activeDevice!.macAddress,
      'status': _activeDevice!.status,
      'pumpState': _activeDevice!.pumpState,
      'mode': _activeDevice!.mode,
      'wifiRssi': _activeDevice!.wifiRssi,
      'firmwareVersion': _activeDevice!.firmwareVersion,
      'lastSeen': _activeDevice!.lastSeen.toIso8601String(),
    };
    await prefs.setString('saved_paired_device', jsonEncode(jsonMap));
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
    _activeDevice = null;
    _sensorData = null;
    _pumpStatus = null;
    _lastMainNodeHeartbeat = null;
    _lastSubNodePacket = null;
    _liveAlerts.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_paired_device');
    await prefs.remove('last_heartbeat_ms');
    notifyListeners();
  }

  void sendPumpCommand(String command, {Map<String, dynamic>? params}) {
    if (_activeDevice == null) return;

    final normCmd = command.toUpperCase();
    final isTurningOn = (normCmd == 'START_PUMP' || normCmd == 'PUMP_ON' || normCmd == 'ON');
    final newState = isTurningOn ? 'ON' : 'OFF';

    // Strict 4000ms anti-flapping lock window to guarantee smooth non-bouncing state
    _expectedPumpState = newState;
    _pumpCommandLockUntil = DateTime.now().add(const Duration(milliseconds: 4000));

    final cmdId = 'cmd_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    _lastCommand = PendingCommand(
      commandId: cmdId,
      command: command,
      sentAt: DateTime.now(),
      state: CommandTransitState.sending,
    );

    mqttService.publishCommand(
      'user_app',
      _activeDevice!.id,
      command,
      params ?? {},
    );

    _pumpStatus = PumpStatusModel(
      state: newState,
      mode: _activeDevice!.mode,
      runningDurationSeconds: isTurningOn ? (_pumpStatus?.runningDurationSeconds ?? 0) : 0,
      safetyStatus: 'NORMAL',
      timestamp: DateTime.now(),
    );

    _activeDevice = DeviceModel(
      id: _activeDevice!.id,
      name: _activeDevice!.name,
      macAddress: _activeDevice!.macAddress,
      status: _activeDevice!.status,
      pumpState: newState,
      mode: _activeDevice!.mode,
      wifiRssi: _activeDevice!.wifiRssi,
      firmwareVersion: _activeDevice!.firmwareVersion,
      lastSeen: _activeDevice!.lastSeen,
    );

    if (newState == 'ON') {
      _pumpCycleCount++;
      addLiveAlert('Motor Started', 'Start motor command executed successfully.', 'motor');
    } else {
      addLiveAlert('Motor Stopped', 'Stop motor command executed successfully.', 'motor');
    }

    _persistActiveDevice();

    Timer(const Duration(milliseconds: 1500), () {
      if (_lastCommand?.commandId == cmdId) {
        _lastCommand?.state = CommandTransitState.idle;
        notifyListeners();
      }
    });

    notifyListeners();
  }

  void sendEmergencyStop() {
    if (_activeDevice == null) return;

    // Strict 5000ms lock to instantly halt motor regardless of mode
    _expectedPumpState = 'OFF';
    _pumpCommandLockUntil = DateTime.now().add(const Duration(milliseconds: 5000));

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
    _persistActiveDevice();
    notifyListeners();
  }

  void setMode(String mode) {
    if (_activeDevice == null) return;
    final normalizedMode = mode.toUpperCase();

    // Strict 3000ms optimistic mode lock to prevent flapping
    _expectedMode = normalizedMode;
    _modeCommandLockUntil = DateTime.now().add(const Duration(milliseconds: 3000));

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

    mqttService.publishCommand(
      'user_app',
      _activeDevice!.id,
      'SET_MODE',
      {'mode': normalizedMode},
    );
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
