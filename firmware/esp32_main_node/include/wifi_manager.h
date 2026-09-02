#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <WiFi.h>
#include <Preferences.h>

enum SystemState {
  STATE_SETUP_MODE,
  STATE_CONNECTING_WIFI,
  STATE_CONNECTING_MQTT,
  STATE_CONNECTED,
  STATE_OFFLINE_MODE,
  STATE_ERROR
};

class WifiManager {
public:
  WifiManager();
  void begin();
  bool connectStored();
  bool connectNew(const String &ssid, const String &password);
  void disconnect();
  bool isConnected();
  void loop();
  
  String getSSID();
  String getIP();
  int8_t getRSSI();
  uint8_t getChannel();
  String getMacAddress();
  String getDeviceId();

  void clearCredentials();

private:
  Preferences prefs;
  String storedSSID;
  String storedPass;
  String deviceId;
  unsigned long lastReconnectAttempt;
  uint32_t reconnectIntervalMs;
  uint8_t retryCount;
};

extern WifiManager wifiMgr;

#endif // WIFI_MANAGER_H
