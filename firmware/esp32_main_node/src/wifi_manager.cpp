#include "wifi_manager.h"
#include "config.h"

WifiManager wifiMgr;

WifiManager::WifiManager() : lastReconnectAttempt(0), reconnectIntervalMs(5000), retryCount(0) {}

void WifiManager::begin() {
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char devIdBuf[32];
  snprintf(devIdBuf, sizeof(devIdBuf), "%s%02X%02X%02X", DEFAULT_DEVICE_PREFIX, mac[3], mac[4], mac[5]);
  deviceId = String(devIdBuf);

  // Set dual AP+STA mode so ESP-NOW works seamlessly while STA connects to router
  WiFi.mode(WIFI_AP_STA);
  WiFi.setAutoReconnect(true);

  prefs.begin(NVS_NAMESPACE, false);
  storedSSID = prefs.getString("wifi_ssid", "");
  storedPass = prefs.getString("wifi_pass", "");
  prefs.end();

  Serial.printf("[WiFi] Initialized. Device ID: %s, Stored SSID: %s\n", deviceId.c_str(), storedSSID.c_str());
}

bool WifiManager::connectStored() {
  if (storedSSID.length() == 0) {
    Serial.println("[WiFi] No stored credentials. Ready for BLE provisioning.");
    return false;
  }
  return connectNew(storedSSID, storedPass);
}

bool WifiManager::connectNew(const String &ssid, const String &password) {
  storedSSID = ssid;
  storedPass = password;

  Serial.printf("[WiFi] Connecting to SSID '%s'...\n", ssid.c_str());
  WiFi.begin(ssid.c_str(), password.c_str());

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 12000) {
    delay(250);
    digitalWrite(PIN_LED_NETWORK, !digitalRead(PIN_LED_NETWORK));
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("[WiFi] Connected! IP: %s, Channel: %d, RSSI: %d dBm\n",
                  WiFi.localIP().toString().c_str(), WiFi.channel(), WiFi.RSSI());
    digitalWrite(PIN_LED_NETWORK, HIGH);

    // Disable Wi-Fi power-save mode to eliminate 50-200ms radio wake latency
    WiFi.setSleep(false);
    Serial.println("[WiFi] Power-save mode DISABLED for low-latency MQTT.");

    // Save valid credentials to NVS
    prefs.begin(NVS_NAMESPACE, false);
    prefs.putString("wifi_ssid", storedSSID);
    prefs.putString("wifi_pass", storedPass);
    prefs.end();

    retryCount = 0;
    reconnectIntervalMs = 5000;
    return true;
  } else {
    Serial.println("[WiFi] Connection failed.");
    digitalWrite(PIN_LED_NETWORK, LOW);
    return false;
  }
}

void WifiManager::disconnect() {
  WiFi.disconnect();
}

bool WifiManager::isConnected() {
  return (WiFi.status() == WL_CONNECTED);
}

void WifiManager::loop() {
  if (!isConnected() && storedSSID.length() > 0) {
    unsigned long now = millis();
    if (now - lastReconnectAttempt > reconnectIntervalMs) {
      lastReconnectAttempt = now;
      retryCount++;
      // Exponential backoff up to 60 seconds
      reconnectIntervalMs = min((uint32_t)60000, reconnectIntervalMs * 2);

      Serial.printf("[WiFi] Reconnect attempt #%d to '%s' (next in %u ms)...\n",
                    retryCount, storedSSID.c_str(), reconnectIntervalMs);
      WiFi.begin(storedSSID.c_str(), storedPass.c_str());
    }
  }
}

String WifiManager::getSSID() { return storedSSID; }
String WifiManager::getIP() { return WiFi.localIP().toString(); }
int8_t WifiManager::getRSSI() { return WiFi.RSSI(); }
uint8_t WifiManager::getChannel() { return WiFi.channel(); }
String WifiManager::getMacAddress() { return WiFi.macAddress(); }
String WifiManager::getDeviceId() { return deviceId; }

void WifiManager::clearCredentials() {
  prefs.begin(NVS_NAMESPACE, false);
  prefs.remove("wifi_ssid");
  prefs.remove("wifi_pass");
  prefs.end();
  storedSSID = "";
  storedPass = "";
  WiFi.disconnect();
}
