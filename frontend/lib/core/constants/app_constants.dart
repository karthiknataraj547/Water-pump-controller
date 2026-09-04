class AppConstants {
  static const String appName = 'HydroPulse IoT';
  static const String appVersion = '2.0.7';

  // API & MQTT Backend (Centralized HydroPulse Cloud Sync)
  static const String cloudApiBaseUrl = 'https://water-pump-controller.vercel.app/api/v1';
  static const String apiBaseUrl = 'https://water-pump-controller.vercel.app/api/v1';
  static String activeApiBaseUrl = 'https://water-pump-controller.vercel.app/api/v1';

  static const String mqttBrokerHost = 'broker.emqx.io';
  static const int mqttBrokerPort = 1883;
  static const int mqttWsPort = 9001;

  // BLE Service & Characteristic UUIDs
  static const String bleServiceUuid = '19B10000-E8F2-537E-4F6C-D104768A1214';
  static const String bleCharSsid = '19B10001-E8F2-537E-4F6C-D104768A1214';
  static const String bleCharPass = '19B10002-E8F2-537E-4F6C-D104768A1214';
  static const String bleCharToken = '19B10003-E8F2-537E-4F6C-D104768A1214';
  static const String bleCharStatus = '19B10004-E8F2-537E-4F6C-D104768A1214';
  static const String bleCharInfo = '19B10005-E8F2-537E-4F6C-D104768A1214';

  // Storage Keys
  static const String keyAccessToken = 'jwt_access_token';
  static const String keyRefreshToken = 'jwt_refresh_token';
  static const String keySelectedDeviceId = 'selected_device_id';
  static const String keyThemeMode = 'app_theme_mode';
  static const String keyUserEmail = 'user_account_email';
  static const String keyUserName = 'user_account_name';
  static const String keyCustomApiBaseUrl = 'custom_api_base_url';
}
