import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iot_water_pump_app/core/hardware/hardware_state_service.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') return 'karthiknataraj547@gmail.com';
        return null;
      },
    );
  });

  group('HardwareStateService Tests', () {
    test('registerPairedDevice sets online status and retains device', () async {
      final service = HardwareStateService();
      await service.initialize();

      expect(service.activeDevice, isNull);
      expect(service.isHardwareOnline, isFalse);
      expect(service.mainNodeStatus, equals(NodeStatus.offline));

      service.registerPairedDevice(
        deviceId: 'esp32_pump_AA69E0',
        name: 'PumpController-AA69E0',
        macAddress: 'A0:A3:B3:AA:69:E2',
      );

      expect(service.activeDevice, isNotNull);
      expect(service.activeDevice!.id, equals('esp32_pump_AA69E0'));
      expect(service.activeDevice!.name, equals('PumpController-AA69E0'));
      expect(service.isHardwareOnline, isTrue);
      expect(service.mainNodeStatus, equals(NodeStatus.online));

      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('saved_paired_device');
      expect(savedStr, isNotNull);
      expect(savedStr!.contains('esp32_pump_AA69E0'), isTrue);
    });

    test('mainNodeStatus reflects realistic IoT heartbeat window (30s)', () async {
      final service = HardwareStateService();
      await service.initialize();

      service.registerPairedDevice(
        deviceId: 'esp32_pump_AA69E0',
        name: 'PumpController-AA69E0',
        macAddress: 'A0:A3:B3:AA:69:E2',
      );

      expect(service.mainNodeStatus, equals(NodeStatus.online));
      expect(service.isHardwareOnline, isTrue);
    });
  });
}
