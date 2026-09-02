import 'package:intl/intl.dart';

class Formatters {
  static String formatDurationSeconds(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String formatVolume(double liters) {
    if (liters >= 1000) {
      return '${(liters / 1000).toStringAsFixed(2)} m³';
    }
    return '${liters.toStringAsFixed(1)} L';
  }

  static String formatDateTime(DateTime dateTime) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dateTime);
  }

  static String formatTimeOnly(DateTime dateTime) {
    return DateFormat('hh:mm a').format(dateTime);
  }

  static String getTdsClassification(int tdsPpm) {
    if (tdsPpm < 50) return 'Ultra Pure';
    if (tdsPpm <= 150) return 'Excellent (Drinking)';
    if (tdsPpm <= 300) return 'Good Quality';
    if (tdsPpm <= 500) return 'Fair Quality';
    return 'Poor / High Mineral';
  }
}
