import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_constants.dart';

enum ProvisioningStep {
  idle,
  scanning,
  connecting,
  connected,
  sendingCredentials,
  connectingWifi,
  connectingMqtt,
  success,
  failed
}

class BleProvisioningService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _statusSubscription;

  final _stepController = StreamController<ProvisioningStep>.broadcast();
  final _discoveredDevicesController = StreamController<List<DiscoveredDevice>>.broadcast();
  final List<DiscoveredDevice> _discoveredList = [];

  String? lastErrorMessage;

  Stream<ProvisioningStep> get stepStream => _stepController.stream;
  Stream<List<DiscoveredDevice>> get discoveredDevicesStream => _discoveredDevicesController.stream;
  Stream<BleStatus> get bleStatusStream => _ble.statusStream;
  BleStatus get currentBleStatus => _ble.status;

  Future<bool> requestPermissions() async {
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      return statuses.values.any((s) => s.isGranted || s.isLimited);
    } catch (e) {
      debugPrint('[BLE] Permission request error: $e');
      return true;
    }
  }

  Future<Map<String, dynamic>> checkPreFlightRequirements() async {
    bool permissionsGranted = false;
    try {
      final scan = await Permission.bluetoothScan.status;
      final connect = await Permission.bluetoothConnect.status;
      final location = await Permission.locationWhenInUse.status;
      permissionsGranted = (scan.isGranted || !scan.isRestricted) &&
          (connect.isGranted || !connect.isRestricted) &&
          (location.isGranted || !location.isRestricted);
    } catch (_) {
      permissionsGranted = true;
    }

    final status = _ble.status;
    final isBluetoothReady = status == BleStatus.ready;
    final isBluetoothPoweredOff = status == BleStatus.poweredOff;
    final isLocationDisabled = status == BleStatus.locationServicesDisabled;

    return {
      'isBluetoothReady': isBluetoothReady,
      'isBluetoothPoweredOff': isBluetoothPoweredOff,
      'isLocationDisabled': isLocationDisabled,
      'permissionsGranted': permissionsGranted,
      'status': status,
    };
  }

  Future<void> startScan() async {
    _discoveredList.clear();
    _discoveredDevicesController.add(_discoveredList);
    _stepController.add(ProvisioningStep.scanning);

    await requestPermissions();

    _scanSubscription?.cancel();
    try {
      _scanSubscription = _ble.scanForDevices(
        withServices: [],
        scanMode: ScanMode.lowLatency,
      ).listen((device) {
        if (device.name.startsWith('PumpController') ||
            device.name.toLowerCase().contains('pump') ||
            device.name.toLowerCase().contains('esp32') ||
            device.name.isNotEmpty) {
          final existingIndex = _discoveredList.indexWhere((d) => d.id == device.id);
          if (existingIndex >= 0) {
            _discoveredList[existingIndex] = device;
          } else {
            _discoveredList.add(device);
          }
          _discoveredDevicesController.add(List.from(_discoveredList));
        }
      }, onError: (e) {
        debugPrint('[BLE] Scan error: $e');
        _stepController.add(ProvisioningStep.failed);
      });
    } catch (e) {
      debugPrint('[BLE] Scan exception: $e');
      _stepController.add(ProvisioningStep.failed);
    }
  }

  void stopScan() {
    _scanSubscription?.cancel();
  }

  Future<void> _safeWrite(
    QualifiedCharacteristic char,
    List<int> value,
  ) async {
    try {
      await _ble.writeCharacteristicWithResponse(char, value: value);
    } catch (e) {
      debugPrint('[BLE] writeCharacteristicWithResponse failed, retrying without response: $e');
      try {
        await _ble.writeCharacteristicWithoutResponse(char, value: value);
      } catch (e2) {
        debugPrint('[BLE] writeCharacteristicWithoutResponse also failed: $e2');
        rethrow;
      }
    }
  }

  Timer? _provisioningWatchdog;

  Future<void> provisionDevice({
    required String deviceId,
    required String ssid,
    required String password,
    required String claimToken,
  }) async {
    stopScan();
    lastErrorMessage = null;
    _provisioningWatchdog?.cancel();
    _stepController.add(ProvisioningStep.connecting);

    // 25-Second Strict Hardware Timeout Watchdog
    _provisioningWatchdog = Timer(const Duration(seconds: 25), () {
      debugPrint('[BLE Provisioning] 25s timeout reached without hardware verification.');
      lastErrorMessage = 'Hardware timed out while connecting to Wi-Fi. Verify that your router is 2.4GHz and your password is correct.';
      _stepController.add(ProvisioningStep.failed);
    });

    _connectionSubscription?.cancel();
    _connectionSubscription = _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 15),
    ).listen((state) async {
      if (state.connectionState == DeviceConnectionState.connected) {
        _stepController.add(ProvisioningStep.connected);
        await _performHandshake(deviceId, ssid, password, claimToken);
      } else if (state.connectionState == DeviceConnectionState.disconnected) {
        debugPrint('[BLE] Device disconnected state received.');
      }
    }, onError: (e) {
      debugPrint('[BLE] Connection error: $e');
      _provisioningWatchdog?.cancel();
      lastErrorMessage = 'Bluetooth connection error: $e';
      _stepController.add(ProvisioningStep.failed);
    });
  }

  Future<void> _performHandshake(
    String deviceId,
    String ssid,
    String password,
    String claimToken,
  ) async {
    try {
      // 1. Discover Services and Negotiate MTU
      try {
        await _ble.discoverServices(deviceId);
      } catch (e) {
        debugPrint('[BLE] Service discovery note: $e');
      }

      try {
        await _ble.requestMtu(deviceId: deviceId, mtu: 256);
      } catch (e) {
        debugPrint('[BLE] MTU request note: $e');
      }

      final serviceUuid = Uuid.parse(AppConstants.bleServiceUuid);
      final statusChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: Uuid.parse(AppConstants.bleCharStatus),
        deviceId: deviceId,
      );

      // 2. Subscribe to REAL status notifications from ESP32 hardware
      try {
        _statusSubscription = _ble.subscribeToCharacteristic(statusChar).listen((data) {
          final statusJson = utf8.decode(data);
          debugPrint('[BLE Hardware Notification] $statusJson');
          try {
            final map = jsonDecode(statusJson) as Map<String, dynamic>;
            final state = map['state'];
            if (state == 'CONNECTING_WIFI') {
              _stepController.add(ProvisioningStep.connectingWifi);
            } else if (state == 'CONNECTING_MQTT') {
              _stepController.add(ProvisioningStep.connectingMqtt);
            } else if (state == 'SUCCESS') {
              _provisioningWatchdog?.cancel();
              _stepController.add(ProvisioningStep.success);
            } else if (state == 'ERROR' || state == 'FAILED_AUTH') {
              _provisioningWatchdog?.cancel();
              lastErrorMessage = map['error_message'] ?? 'Hardware failed to connect to Wi-Fi. Check SSID and Password.';
              _stepController.add(ProvisioningStep.failed);
            }
          } catch (_) {}
        }, onError: (err) {
          debugPrint('[BLE Status Stream] Notification note: $err');
        });
      } catch (e) {
        debugPrint('[BLE] Subscribe to status failed: $e');
      }

      _stepController.add(ProvisioningStep.sendingCredentials);
      await Future.delayed(const Duration(milliseconds: 200));

      // 3. Write SSID
      final ssidChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: Uuid.parse(AppConstants.bleCharSsid),
        deviceId: deviceId,
      );
      await _safeWrite(ssidChar, utf8.encode(ssid));
      await Future.delayed(const Duration(milliseconds: 150));

      // 4. Write Password
      final passChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: Uuid.parse(AppConstants.bleCharPass),
        deviceId: deviceId,
      );
      await _safeWrite(passChar, utf8.encode(password));
      await Future.delayed(const Duration(milliseconds: 150));

      // 5. Write Claim Token (signals ESP32 to begin asynchronous Wi-Fi connection)
      final tokenChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: Uuid.parse(AppConstants.bleCharToken),
        deviceId: deviceId,
      );
      await _safeWrite(tokenChar, utf8.encode(claimToken));

      debugPrint('[BLE] Wi-Fi Credentials transmitted to ESP32! Waiting for real hardware verification...');
      _stepController.add(ProvisioningStep.connectingWifi);
    } catch (e) {
      debugPrint('[BLE Handshake Error] $e');
      _provisioningWatchdog?.cancel();
      lastErrorMessage = 'GATT Write Error: $e\nEnsure ESP32 is powered and in BLE mode.';
      _stepController.add(ProvisioningStep.failed);
    }
  }

  void disconnect() {
    _provisioningWatchdog?.cancel();
    _statusSubscription?.cancel();
    _connectionSubscription?.cancel();
    _scanSubscription?.cancel();
    _stepController.add(ProvisioningStep.idle);
  }
}

final bleService = BleProvisioningService();
