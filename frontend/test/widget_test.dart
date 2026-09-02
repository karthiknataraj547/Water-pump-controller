import 'package:flutter_test/flutter_test.dart';
import 'package:iot_water_pump_app/core/utils/formatters.dart';

void main() {
  group('Formatters Unit Tests', () {
    test('formatDurationSeconds formats minutes and seconds correctly', () {
      expect(Formatters.formatDurationSeconds(75), '01:15');
      expect(Formatters.formatDurationSeconds(3665), '01:01:05');
    });

    test('formatVolume handles liters and cubic meters', () {
      expect(Formatters.formatVolume(450.5), '450.5 L');
      expect(Formatters.formatVolume(2500.0), '2.50 m³');
    });

    test('getTdsClassification categorizes water purity correctly', () {
      expect(Formatters.getTdsClassification(45), 'Ultra Pure');
      expect(Formatters.getTdsClassification(120), 'Excellent (Drinking)');
      expect(Formatters.getTdsClassification(250), 'Good Quality');
      expect(Formatters.getTdsClassification(450), 'Fair Quality');
      expect(Formatters.getTdsClassification(650), 'Poor / High Mineral');
    });
  });
}
