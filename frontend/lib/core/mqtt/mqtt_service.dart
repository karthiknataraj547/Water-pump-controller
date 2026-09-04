import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';

class MqttService {
  MqttServerClient? _client;
  bool isConnected = false;
  String currentBroker = 'broker.emqx.io';
  final ValueNotifier<bool> connectionNotifier = ValueNotifier<bool>(false);

  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _sensorController = StreamController<Map<String, dynamic>>.broadcast();
  final _ackController = StreamController<Map<String, dynamic>>.broadcast();
  final _alertController = StreamController<Map<String, dynamic>>.broadcast();
  final _pongController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get sensorStream => _sensorController.stream;
  Stream<Map<String, dynamic>> get ackStream => _ackController.stream;
  Stream<Map<String, dynamic>> get alertStream => _alertController.stream;
  Stream<Map<String, dynamic>> get pongStream => _pongController.stream;

  // Cloud Broker candidate targets (Prioritizing Mosquitto MQTT broker for low-latency IoT communication)
  static const List<Map<String, dynamic>> brokerTargets = [
    {
      'server': 'test.mosquitto.org',
      'host': 'test.mosquitto.org',
      'label': 'Mosquitto Public TCP (Port 1883)',
      'port': 1883,
      'isTls': false,
      'useWebSocket': false,
    },
    {
      'server': 'broker.emqx.io',
      'host': 'broker.emqx.io',
      'label': 'EMQX Cloud TCP (Port 1883)',
      'port': 1883,
      'isTls': false,
      'useWebSocket': false,
    },
    {
      'server': 'broker.hivemq.com',
      'host': 'broker.hivemq.com',
      'label': 'HiveMQ Cloud TCP (Port 1883)',
      'port': 1883,
      'isTls': false,
      'useWebSocket': false,
    },
    {
      'server': 'ws://test.mosquitto.org:8080/mqtt',
      'host': 'test.mosquitto.org',
      'label': 'Mosquitto WebSocket (Port 8080)',
      'port': 8080,
      'isTls': false,
      'useWebSocket': true,
    },
    {
      'server': 'wss://broker.emqx.io:8084/mqtt',
      'host': 'broker.emqx.io',
      'label': 'EMQX Secure WSS (Port 8084)',
      'port': 8084,
      'isTls': true,
      'useWebSocket': true,
    },
    {
      'server': 'wss://broker.hivemq.com:8884/mqtt',
      'host': 'broker.hivemq.com',
      'label': 'HiveMQ Secure WSS (Port 8884)',
      'port': 8884,
      'isTls': true,
      'useWebSocket': true,
    },
  ];

  bool _isConnecting = false;
  Timer? _reconnectTimer;
  String? _lastHost;
  int? _lastPort;
  String? _lastUser;
  String? _lastPass;

  Future<bool> connect({String? host, int? port, String? username, String? password}) async {
    if (_isConnecting) {
      debugPrint('[MQTT] Connection attempt already in progress. Skipping duplicate.');
      return isConnected;
    }
    _isConnecting = true;
    _reconnectTimer?.cancel();

    _lastHost = host;
    _lastPort = port;
    _lastUser = username;
    _lastPass = password;

    List<Map<String, dynamic>> targetsToTry = [];
    if (host != null && host.isNotEmpty && host != 'broker.emqx.io' && host != 'broker.hivemq.com' && host != 'test.mosquitto.org') {
      final isWs = port == 8083 || port == 8084 || port == 8000 || port == 8080 || host.startsWith('ws://') || host.startsWith('wss://');
      final isTls = port == 8883;
      final targetP = port ?? (isWs ? 8083 : (isTls ? 8883 : AppConstants.mqttBrokerPort));
      final wsServer = host.startsWith('ws') ? host : 'ws://$host:$targetP/mqtt';
      targetsToTry.add({
        'server': isWs ? wsServer : host,
        'host': host,
        'label': 'Custom Broker',
        'port': targetP,
        'isTls': isTls,
        'useWebSocket': isWs,
      });
    }
    targetsToTry.addAll(brokerTargets);

    // Test connectivity probe
    try {
      final testClient = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await testClient.getUrl(Uri.parse('https://httpbin.org/get'));
      final resp = await req.close();
      debugPrint('[Network Probe] HTTP Reachable -> StatusCode: ${resp.statusCode}');
    } catch (e) {
      debugPrint('[Network Probe Error] $e');
    }

    for (final target in targetsToTry) {
      final targetHost = target['host'] as String;
      final serverIdentifier = (target['server'] as String?) ?? targetHost;
      final label = target['label'] ?? targetHost;
      final targetPort = target['port'] as int;
      final isTls = (target['isTls'] as bool?) ?? false;
      final isWs = (target['useWebSocket'] as bool?) ?? false;

      currentBroker = '$targetHost:$targetPort';
      final clientId = 'hydropulse_mob_${const Uuid().v4().substring(0, 6)}';

      if (_client != null) {
        try {
          _client!.onDisconnected = null;
          _client!.onConnected = null;
          _client!.disconnect();
        } catch (_) {}
        _client = null;
      }

      debugPrint('[MQTT] Attempting connect to $label ($targetHost:$targetPort, TLS: $isTls, WS: $isWs)...');

      final client = MqttServerClient.withPort(serverIdentifier, clientId, targetPort)
        ..keepAlivePeriod = 15  // Reduced from 30s for faster disconnect detection
        ..connectTimeoutPeriod = 6000
        ..setProtocolV311()
        ..logging(on: false)
        ..onConnected = _onConnected
        ..onDisconnected = _onDisconnected
        ..onSubscribed = (topic) => debugPrint('[MQTT] Subscribed to topic: $topic');

      if (isTls && !isWs) {
        client.secure = true;
        client.securityContext = SecurityContext.defaultContext;
        client.onBadCertificate = (Object cert) => true;
      }

      if (isWs) {
        client.useWebSocket = true;
        client.websocketProtocols = const ['mqtt', 'mqttv3.1', 'mqttv3.1.1'];
      }

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean();

      client.connectionMessage = connMessage;
      _client = client;

      try {
        final status = await client.connect(
          username?.isNotEmpty == true ? username : null,
          password?.isNotEmpty == true ? password : null,
        ).timeout(const Duration(seconds: 6), onTimeout: () {
          debugPrint('[MQTT] Timeout connecting to $targetHost:$targetPort after 6s.');
          return null;
        });

        if (status?.state == MqttConnectionState.connected) {
          isConnected = true;
          connectionNotifier.value = true;
          _subscribeToAllHardwareTopics();
          _listenToMessages();
          _isConnecting = false;
          debugPrint('[MQTT] >>> CONNECTED SUCCESSFULLY to $label ($targetHost:$targetPort) <<<');
          return true;
        } else {
          debugPrint('[MQTT] Endpoint $targetHost:$targetPort state: ${status?.state}. Trying next...');
          client.onDisconnected = null;
          client.disconnect();
        }
      } catch (e, stack) {
        debugPrint('[MQTT] Error connecting to $targetHost:$targetPort: $e\nStack: $stack');
        try {
          client.onDisconnected = null;
          client.disconnect();
        } catch (_) {}
      }
    }

    _isConnecting = false;
    isConnected = false;
    connectionNotifier.value = false;
    _scheduleReconnect();
    return false;
  }

  void _subscribeToAllHardwareTopics() {
    if (_client == null || !isConnected) return;

    // Single wildcard covers all device topics — QoS 0 for fastest delivery
    _client!.subscribe('pump/#', MqttQos.atMostOnce);
    _client!.subscribe('devices/#', MqttQos.atMostOnce);
    _client!.subscribe('waterpump/#', MqttQos.atMostOnce);
    debugPrint('[MQTT] Subscribed to pump/#, devices/#, and waterpump/# (QoS 0).');
  }

  void subscribeToDevice(String userId, String deviceId) {
    if (_client == null || !isConnected) return;

    final topicPrefix = 'pump/$userId/$deviceId';
    _client!.subscribe('$topicPrefix/#', MqttQos.atMostOnce);
  }

  void publishCommand(String userId, String deviceId, String command, Map<String, dynamic> params) {
    if (_client == null || !isConnected) {
      debugPrint('[MQTT] Cannot publish command: MQTT Client is disconnected.');
      return;
    }

    final cmdId = 'cmd_${const Uuid().v4().substring(0, 8)}';
    final payload = {
      'action': command,
      'command': command,
      'commandId': cmdId,
      'command_id': cmdId,
      'parameters': params,
      'issued_by': userId,
      'deviceId': deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    final payloadJson = jsonEncode(payload);
    final builder = MqttClientPayloadBuilder();
    builder.addString(payloadJson);

    // Broadcast on both unified and device-specific topics — QoS 0 for speed
    _client!.publishMessage('pump/command', MqttQos.atMostOnce, builder.payload!);
    _client!.publishMessage('pump/$deviceId/command', MqttQos.atMostOnce, builder.payload!);
    _client!.publishMessage('pump/$userId/$deviceId/command', MqttQos.atMostOnce, builder.payload!);
    _client!.publishMessage('waterpump/esp32/control', MqttQos.atMostOnce, builder.payload!);

    debugPrint('[MQTT TX Command] $command to $deviceId (ID: $cmdId)');
  }

  void publishPing(String userId, String deviceId, String pingId, int timestampMs) {
    if (_client == null || !isConnected) return;

    final payload = {
      'ping_id': pingId,
      'pingId': pingId,
      'deviceId': deviceId,
      'device_id': deviceId,
      'issued_by': userId,
      'timestamp_ms': timestampMs,
      'timestamp': timestampMs ~/ 1000,
    };

    final payloadJson = jsonEncode(payload);
    final builder = MqttClientPayloadBuilder();
    builder.addString(payloadJson);

    // Publish high-speed ping
    _client!.publishMessage('pump/ping', MqttQos.atMostOnce, builder.payload!);
    _client!.publishMessage('pump/$deviceId/ping', MqttQos.atMostOnce, builder.payload!);
    _client!.publishMessage('pump/$userId/$deviceId/ping', MqttQos.atMostOnce, builder.payload!);
  }

  void _listenToMessages() {
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final recMess = msg.payload as MqttPublishMessage;
        final payloadStr = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        try {
          final data = jsonDecode(payloadStr) as Map<String, dynamic>;
          final topic = msg.topic;
          final isRetained = recMess.header?.retain ?? false;
          data['_isRetained'] = isRetained;

          if (topic.endsWith('/pong') || topic == 'pump/pong' || topic.endsWith('/ping/pong')) {
            _pongController.add(data);
          } else if (topic.endsWith('/status') || topic.endsWith('/heartbeat') || topic == 'pump/status' || topic == 'pump/heartbeat') {
            _statusController.add(data);
          } else if (topic.endsWith('/sensor') || topic.endsWith('/telemetry') || topic == 'pump/telemetry') {
            _sensorController.add(data);
          } else if (topic.endsWith('/ack') || topic == 'pump/command/ack') {
            _ackController.add(data);
          } else if (topic.endsWith('/alert') || topic == 'pump/alert') {
            _alertController.add(data);
          }
        } catch (e) {
          debugPrint('[MQTT] JSON parse error on $payloadStr: $e');
        }
      }
    });
  }

  void _onConnected() {
    isConnected = true;
    connectionNotifier.value = true;
    _reconnectTimer?.cancel();
    debugPrint('[MQTT] Connected to broker ($currentBroker) successfully.');
  }

  void _onDisconnected() {
    isConnected = false;
    connectionNotifier.value = false;
    debugPrint('[MQTT] Disconnected from broker. Scheduling reconnect in 2s...');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!isConnected && !_isConnecting) {
        connect(
          host: _lastHost,
          port: _lastPort,
          username: _lastUser,
          password: _lastPass,
        );
      }
    });
  }

  void dispose() {
    _reconnectTimer?.cancel();
    if (_client != null) {
      _client!.onDisconnected = null;
      _client!.disconnect();
    }
    _statusController.close();
    _sensorController.close();
    _ackController.close();
    _alertController.close();
    _pongController.close();
  }
}

final mqttService = MqttService();
