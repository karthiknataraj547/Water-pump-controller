import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class InternetConnectivityService extends ChangeNotifier {
  static final InternetConnectivityService _instance = InternetConnectivityService._internal();
  factory InternetConnectivityService() => _instance;
  InternetConnectivityService._internal() {
    _init();
  }

  bool _isOnline = true;
  bool get isOnline => _isOnline;
  bool get isConnected => _isOnline;

  Timer? _pollingTimer;
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  void _init() {
    checkConnection();
    // Periodically verify internet connectivity every 4 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      checkConnection();
    });
  }

  Future<bool> checkConnection() async {
    bool hasInternet = false;
    try {
      final lookup = await InternetAddress.lookup('dns.google').timeout(const Duration(seconds: 2));
      if (lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty) {
        hasInternet = true;
      }
    } catch (_) {
      // Fallback probe
      try {
        final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 2));
        socket.destroy();
        hasInternet = true;
      } catch (_) {
        hasInternet = false;
      }
    }

    if (_isOnline != hasInternet) {
      _isOnline = hasInternet;
      _connectivityController.add(_isOnline);
      notifyListeners();
      debugPrint('[Connectivity] Internet state changed: ${_isOnline ? "CONNECTED" : "NO INTERNET"}');
    }

    return _isOnline;
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _connectivityController.close();
    super.dispose();
  }
}

final internetConnectivityService = InternetConnectivityService();
