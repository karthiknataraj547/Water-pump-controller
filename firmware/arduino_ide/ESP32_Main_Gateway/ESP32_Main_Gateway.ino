/*
 * ==============================================================================
 * HydroPulse IoT Water Pump Controller & Gateway - ESP32 Main Node Firmware
 * ==============================================================================
 * Architecture: ESP32 FreeRTOS Dual-Core System
 * Core 0: TaskNetwork (Wi-Fi, MQTT with LWT, HTTP Backend API, Status Heartbeat)
 * Core 1: TaskControl (Relay Soft-Start, Manual Switching, Safety Interlocks, Reset)
 *
 * Hardware Peripherals:
 *   - Relay Module (Active HIGH)               -> GPIO 23
 *   - Manual Push Button (Active LOW)          -> GPIO 19
 *   - Emergency Stop Switch (Active LOW)       -> GPIO 18
 *   - Factory Hard Reset Button (BOOT / GPIO 0)-> GPIO 0  (Hold 1.2s at boot / 1.5s runtime)
 *   - Blue Network Status LED                  -> GPIO 2
 *   - Green Pump Running LED                   -> GPIO 4
 *   - Alert Buzzer                             -> GPIO 5
 *
 * Communications:
 *   - BLE GATT Provisioning (UUIDs aligned with Flutter Mobile App)
 *   - Wi-Fi Station with persistent auto-reconnect & max RF transmit power
 *   - Global Cloud MQTT Broker with Last Will & Testament (LWT) on 'pump/status'
 *   - ESP-NOW Central Hub receiving telemetry from ESP8266 Sub Node (CRC16 check)
 *   - Backend HTTP API Telemetry Posting (REST failover / sync)
 *
 * Required Libraries (Install via Arduino Library Manager):
 *   1. "PubSubClient" by Nick O'Leary (v2.8+)
 *   2. "ArduinoJson" by Benoit Blanchon (v6.x or v7.x)
 *   (BLE and ESP-NOW are built into the ESP32 board package automatically)
 * ==============================================================================
 */

#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_idf_version.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <HTTPClient.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// Built-in ESP32 BLE Stack
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ==============================================================================
// 1. HARDWARE PIN DEFINITIONS & CONSTANTS
// ==============================================================================
#define PIN_RELAY_PUMP         23   // Main Pump Relay Pin (GPIO 23)
#define RELAY_ACTIVE_LOW       false// Set to 'true' for Active-LOW relay modules, 'false' for Active-HIGH
#define PIN_MANUAL_BUTTON      19   // Manual toggle push button (Active LOW with pullup)
#define PIN_EMERGENCY_STOP     18   // Emergency cutoff switch (Active LOW with pullup)
#define PIN_HARD_RESET         0    // Factory Hard Reset button (BOOT Button / GPIO 0)
#define PIN_LED_NETWORK        2    // Blue network LED (Blinks when offline, solid when connected)
#define PIN_LED_PUMP           4    // Green pump running LED
#define PIN_BUZZER             5    // Piezo alert buzzer

#define FIRMWARE_VERSION       "2.0.9"
#define DEFAULT_DEVICE_PREFIX  "esp32_pump_"
#define BLE_DEVICE_PREFIX      "PumpController-"
#define NVS_NAMESPACE          "pump_config"

// Networking & Cloud Defaults
#define DEFAULT_MQTT_BROKER    "broker.emqx.io"
#define DEFAULT_MQTT_PORT      1883
#define STATUS_REPORT_INTERVAL 1000     // 1 second dedicated Main Node heartbeat
#define SUB_NODE_TIMEOUT_MS    2000     // 2s timeout for 150ms ESP8266 Sub Node streaming (fast failover)
#define MAX_RUN_TIME_LIMIT_MS  1800000  // 30 minutes continuous max runtime safety limit
#define BACKEND_API_URL        "http://localhost:4000/api/v1/telemetry" // Configurable API endpoint

// BLE Provisioning UUIDs (Matching Flutter App)
#define SERVICE_UUID_PROV      "19B10000-E8F2-537E-4F6C-D104768A1214"
#define CHAR_UUID_WIFI_SSID    "19B10001-E8F2-537E-4F6C-D104768A1214"
#define CHAR_UUID_WIFI_PASS    "19B10002-E8F2-537E-4F6C-D104768A1214"
#define CHAR_UUID_AUTH_TOKEN   "19B10003-E8F2-537E-4F6C-D104768A1214"
#define CHAR_UUID_PROV_STATUS  "19B10004-E8F2-537E-4F6C-D104768A1214"
#define CHAR_UUID_DEVICE_INFO  "19B10005-E8F2-537E-4F6C-D104768A1214"

// ==============================================================================
// 2. BINARY TELEMETRY PACKET (ESP-NOW PROTOCOL)
// ==============================================================================
#pragma pack(push, 1)
struct SensorTelemetryPacket {
  uint16_t header;        // 0xAA55
  char     nodeId[16];    // e.g. "tank_node_001"
  uint32_t sequence;      // Incrementing counter
  float    waterLevelPct; // 0.0 - 100.0%
  float    waterVolumeL;  // Liters
  float    flowRateLpm;   // Liters / minute
  float    waterTempC;    // Degrees C
  float    tdsPpm;        // Total Dissolved Solids
  float    batteryVoltage;// Volts (3.7V - 4.2V)
  uint8_t  nodeStatus;    // 0: OK, 1: Low Battery, 2: Sensor Error
  uint16_t checksum;      // CRC16-CCITT
};
#pragma pack(pop)

// ==============================================================================
// 3. GLOBAL OBJECTS & RUNTIME STATE
// ==============================================================================
Preferences prefs;
WiFiClient espClient;
PubSubClient mqttClient(espClient);

BLEServer*         pBleServer = nullptr;
BLECharacteristic* pStatusChar = nullptr;
bool               bleClientConnected = false;
bool               bleProvisioningActive = false;

String deviceId = "";
String storedSSID = "";
String storedPass = "";
String storedBackendUrl = BACKEND_API_URL;
String incomingSsid = "";
String incomingPass = "";
String incomingToken = "";

// Operational Modes: AUTO (autonomous levels), MANUAL (app/button direct), SCHEDULE
String systemMode = "AUTO";
float autoStartLevel = 25.0f;
float autoStopLevel = 95.0f;
bool dryRunProtectionEnabled = true;

// State variables
bool pumpRunning = false;
bool emergencyStopped = false;
unsigned long pumpStartTime = 0;

// Non-blocking Command Queue & Status Notification Flags
volatile bool requestedPumpState = false;
volatile bool hasPendingPumpCommand = false;
String pendingCmdReason = "";
String pendingCmdId = "";
volatile bool notifyMqttStatusUpdate = false;

// Sub node telemetry cache (-1 sentinel = no sensor data yet)
float currentLevelPct = -1.0f;
float currentVolumeL = 0.0f;
float currentFlowRateLpm = 0.0f;
float currentTempC = 0.0f;
float currentTdsPpm = 0.0f;
float currentBatteryV = 0.0f;
uint32_t lastPacketSeq = 0;
unsigned long lastSensorPacketTime = 0;

// FreeRTOS Task Handles
TaskHandle_t TaskNetworkHandle = NULL;
TaskHandle_t TaskControlHandle = NULL;

// Cloud Broker Failover Pool (Prioritizing EMQX Cloud MQTT broker for low-latency synchronized communication)
const char* CLOUD_BROKERS[] = {"broker.emqx.io", "broker.hivemq.com", "test.mosquitto.org"};
int currentBrokerIdx = 0;
unsigned long lastMqttRetry = 0;

// Forward Declarations
void updateBleStatus(const String &state, const String &ip = "", const String &error = "");
bool connectWifi(const String &ssid, const String &pass);
void setPumpState(bool state, const String &reason);
void executeFactoryReset();
void sendHttpBackendTelemetry();
uint16_t calculateCRC16(const uint8_t *data, size_t len);

// ==============================================================================
// 4. CRC16-CCITT CHECKSUM CALCULATION
// ==============================================================================
uint16_t calculateCRC16(const uint8_t *data, size_t len) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < len; i++) {
    crc ^= (uint16_t)data[i] << 8;
    for (uint8_t j = 0; j < 8; j++) {
      if (crc & 0x8000) crc = (crc << 1) ^ 0x1021;
      else crc <<= 1;
    }
  }
  return crc;
}

// ==============================================================================
// 5. BLE PROVISIONING ENGINE
// ==============================================================================
class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    bleClientConnected = true;
    Serial.println("[BLE] Central smartphone connected!");
    updateBleStatus("CONNECTED_BLE");
  }

  void onDisconnect(BLEServer* pServer) {
    bleClientConnected = false;
    Serial.println("[BLE] Central smartphone disconnected.");
    if (bleProvisioningActive) {
      BLEDevice::startAdvertising();
    }
  }
};

volatile bool pendingWifiProvisioning = false;

class SsidCharCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String val = pChar->getValue().c_str();
    if (val.length() > 0) {
      incomingSsid = val;
      Serial.printf("\n[BLE RX] >>> Wi-Fi SSID received: '%s'\n", incomingSsid.c_str());
    }
  }
};

class PassCharCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String val = pChar->getValue().c_str();
    incomingPass = val;
    Serial.printf("[BLE RX] >>> Wi-Fi Password received (%d characters).\n", incomingPass.length());
  }
};

class TokenCharCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String val = pChar->getValue().c_str();
    if (val.length() > 0) {
      incomingToken = val;
      Serial.printf("[BLE RX] >>> Auth/Claim Token received: '%s'\n", incomingToken.c_str());
      
      // Trigger asynchronous connection in TaskNetwork
      if (incomingSsid.length() > 0) {
        updateBleStatus("CONNECTING_WIFI");
        pendingWifiProvisioning = true;
      }
    }
  }
};

void updateBleStatus(const String &state, const String &ip, const String &error) {
  if (!pStatusChar) return;
  StaticJsonDocument<256> doc;
  doc["state"] = state;
  doc["ip_address"] = ip;
  doc["mac_address"] = WiFi.macAddress();
  doc["device_id"] = deviceId;
  if (error.length() > 0) doc["error_message"] = error;

  String json;
  serializeJson(doc, json);
  pStatusChar->setValue(json.c_str());
  pStatusChar->notify();
  Serial.printf("[BLE Notify] %s\n", json.c_str());
}

void startBleProvisioning() {
  if (bleProvisioningActive) return;

  String advName = String(BLE_DEVICE_PREFIX) + deviceId.substring(11);
  BLEDevice::init(advName.c_str());
  BLEDevice::setPower(ESP_PWR_LVL_P9);

  pBleServer = BLEDevice::createServer();
  pBleServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pBleServer->createService(SERVICE_UUID_PROV);

  // SSID Characteristic (Write)
  BLECharacteristic *pSsid = pService->createCharacteristic(
    CHAR_UUID_WIFI_SSID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pSsid->setCallbacks(new SsidCharCallbacks());

  // Password Characteristic (Write)
  BLECharacteristic *pPass = pService->createCharacteristic(
    CHAR_UUID_WIFI_PASS,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pPass->setCallbacks(new PassCharCallbacks());

  // Auth Token Characteristic (Write)
  BLECharacteristic *pToken = pService->createCharacteristic(
    CHAR_UUID_AUTH_TOKEN,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pToken->setCallbacks(new TokenCharCallbacks());

  // Status Notification Characteristic (Read | Notify)
  pStatusChar = pService->createCharacteristic(
    CHAR_UUID_PROV_STATUS,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pStatusChar->addDescriptor(new BLE2902());

  // Device Info Characteristic (Read)
  BLECharacteristic *pInfo = pService->createCharacteristic(
    CHAR_UUID_DEVICE_INFO,
    BLECharacteristic::PROPERTY_READ
  );
  StaticJsonDocument<256> infoDoc;
  infoDoc["device_id"] = deviceId;
  infoDoc["mac"] = WiFi.macAddress();
  infoDoc["fw_version"] = FIRMWARE_VERSION;
  String infoStr;
  serializeJson(infoDoc, infoStr);
  pInfo->setValue(infoStr.c_str());

  pService->start();

  BLEAdvertising *pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(SERVICE_UUID_PROV);
  pAdv->setScanResponse(true);
  pAdv->setMinPreferred(0x06);
  pAdv->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  bleProvisioningActive = true;
  Serial.printf("[BLE] Provisioning Server active as '%s'\n", advName.c_str());
}

void stopBleProvisioning() {
  if (!bleProvisioningActive) return;
  Serial.println("[BLE] Wi-Fi is connected. Deactivating BLE server to save power and RF bandwidth.");
  BLEDevice::getAdvertising()->stop();
  BLEDevice::deinit(false);
  pStatusChar = nullptr;
  pBleServer = nullptr;
  bleProvisioningActive = false;
  Serial.println("[BLE] BLE Stack cleanly stopped.");
}

// ==============================================================================
// 6. WI-FI & RF RADIO MANAGER
// ==============================================================================
bool connectWifi(const String &ssid, const String &pass) {
  Serial.printf("[WiFi] Connecting to SSID: '%s'...\n", ssid.c_str());

  WiFi.persistent(true);
  WiFi.setAutoReconnect(true);
  WiFi.setTxPower(WIFI_POWER_19_5dBm); // Maximum RF transmit power for wall penetration
  WiFi.disconnect(false);
  delay(100);

  WiFi.begin(ssid.c_str(), pass.c_str());

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(250);
    digitalWrite(PIN_LED_NETWORK, !digitalRead(PIN_LED_NETWORK));
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("[WiFi] Connected! IP: %s | RSSI: %d dBm | Channel: %d\n", 
                  WiFi.localIP().toString().c_str(), WiFi.RSSI(), WiFi.channel());
    digitalWrite(PIN_LED_NETWORK, HIGH);

    // Disable modem power saving on radio after connection
    WiFi.setSleep(false);
    esp_wifi_set_ps(WIFI_PS_NONE);

    // Save to Flash NVS
    prefs.begin(NVS_NAMESPACE, false);
    prefs.putString("wifi_ssid", ssid);
    prefs.putString("wifi_pass", pass);
    prefs.end();
    storedSSID = ssid;
    storedPass = pass;

    return true;
  } else {
    Serial.println("[WiFi] Connection failed or timed out.");
    digitalWrite(PIN_LED_NETWORK, LOW);
    return false;
  }
}

// ==============================================================================
// 7. PUMP CONTROL, RELAY SOFT-SWITCHING & SAFETY INTERLOCKS
// ==============================================================================
void setPumpState(bool state, const String &reason) {
  if (state && emergencyStopped) {
    Serial.println("[Safety Interlock] Blocked: Emergency stop active! Reset emergency switch to run.");
    return;
  }
  // SAFETY INTERLOCK: In AUTO mode, if sub-node is not connected with main node, motor must NOT work!
  bool subAlive = (lastSensorPacketTime > 0 && (millis() - lastSensorPacketTime) < SUB_NODE_TIMEOUT_MS);
  if (state && systemMode == "AUTO" && !subAlive) {
    Serial.println("[Safety Interlock] 🔒 BLOCKED: Sub-node (tank sensor) is disconnected! In AUTO mode the motor must not work.");
    return;
  }
  if (pumpRunning == state) return; // Prevent redundant relay cycling

  pumpRunning = state;

  // Soft-switching transient isolation delay:
  // Step 1: Light up the status LED
  digitalWrite(PIN_LED_PUMP, state ? HIGH : LOW);
  delay(15);

  // Step 2: Energize or de-energize relay coil (Active-LOW or Active-HIGH support)
  bool relayPinLevel = RELAY_ACTIVE_LOW ? (!state) : state;
  digitalWrite(PIN_RELAY_PUMP, relayPinLevel ? HIGH : LOW);
  delay(30);

  if (state) {
    pumpStartTime = millis();
  }

  Serial.printf("[Pump Relay] State changed to %s (Pin %d = %s). Reason: %s\n",
                state ? "ON" : "OFF", PIN_RELAY_PUMP, relayPinLevel ? "HIGH" : "LOW", reason.c_str());

  // Request asynchronous status broadcast in TaskNetwork loop
  notifyMqttStatusUpdate = true;
}

// ==============================================================================
// 8. FACTORY HARD RESET HANDLER (4-WAY TRIGGER)
// ==============================================================================
void executeFactoryReset() {
  Serial.println("\n*******************************************************");
  Serial.println("[FACTORY RESET] EXECUTING COMPLETE HARDWARE WIPE...");
  Serial.println("[FACTORY RESET] Erasing NVS Flash & SDK Wi-Fi Credentials...");
  Serial.println("*******************************************************\n");

  // Audible & visual confirmation (6 beeps and flashes)
  for (int i = 0; i < 6; i++) {
    digitalWrite(PIN_LED_NETWORK, HIGH);
    digitalWrite(PIN_LED_PUMP, HIGH);
    digitalWrite(PIN_BUZZER, HIGH);
    delay(70);
    digitalWrite(PIN_LED_NETWORK, LOW);
    digitalWrite(PIN_LED_PUMP, LOW);
    digitalWrite(PIN_BUZZER, LOW);
    delay(70);
  }

  // 1. Wipe our custom NVS namespace
  prefs.begin(NVS_NAMESPACE, false);
  prefs.clear();
  prefs.end();

  // 2. Erase ESP-IDF internal SDK Wi-Fi non-volatile flash storage
  WiFi.disconnect(true, true);
  WiFi.setAutoReconnect(false);

  storedSSID = "";
  storedPass = "";

  Serial.println("[FACTORY RESET] Wipe complete! Rebooting ESP32 into BLE Pairing Mode...\n");
  delay(400);
  ESP.restart();
}

// ==============================================================================
// 9. MQTT & BACKEND HTTP API CLIENT
// ==============================================================================
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) message += (char)payload[i];
  Serial.printf("[MQTT RX] Topic: '%s' | Payload: %s\n", topic, message.c_str());

  StaticJsonDocument<512> doc;
  if (deserializeJson(doc, message) == DeserializationError::Ok) {
    const char* action = doc["action"] | doc["command"] | "";
    const char* cmdId = doc["commandId"] | doc["command_id"] | "cmd_local";

    Serial.printf("[MQTT Command RX] Action parsed: '%s' | CmdId: '%s'\n", action, cmdId);

    if (strcasecmp(action, "START_PUMP") == 0 || strcasecmp(action, "PUMP_ON") == 0 || strcasecmp(action, "START") == 0 || strcasecmp(action, "ON") == 0) {
      bool subAlive = (lastSensorPacketTime > 0 && (millis() - lastSensorPacketTime) < SUB_NODE_TIMEOUT_MS);
      if (systemMode == "AUTO" && !subAlive) {
        Serial.println("[MQTT] 🔒 Start command rejected: Sub-node disconnected in AUTO mode.");
        notifyMqttStatusUpdate = true;
        return;
      }
      requestedPumpState = true;
      pendingCmdReason = "MQTT Remote Start";
      pendingCmdId = String(cmdId);
      hasPendingPumpCommand = true;
    } else if (strcasecmp(action, "STOP_PUMP") == 0 || strcasecmp(action, "PUMP_OFF") == 0 || strcasecmp(action, "STOP") == 0 || strcasecmp(action, "OFF") == 0) {
      requestedPumpState = false;
      pendingCmdReason = "MQTT Remote Stop";
      pendingCmdId = String(cmdId);
      hasPendingPumpCommand = true;
    } else if (strcasecmp(action, "SET_MODE") == 0) {
      const char* m = doc["mode"] | doc["parameters"]["mode"] | "AUTO";
      systemMode = String(m);
      systemMode.toUpperCase();
      Serial.printf("[SYSTEM] Mode changed to: %s\n", systemMode.c_str());
      prefs.begin(NVS_NAMESPACE, false);
      prefs.putString("sys_mode", systemMode);
      prefs.end();
      notifyMqttStatusUpdate = true;
    } else if (strcasecmp(action, "SET_RULES") == 0) {
      if (doc.containsKey("autoStartLevel")) autoStartLevel = doc["autoStartLevel"];
      if (doc.containsKey("autoStopLevel")) autoStopLevel = doc["autoStopLevel"];
      if (doc.containsKey("dryRunProtection")) dryRunProtectionEnabled = doc["dryRunProtection"];
      prefs.begin(NVS_NAMESPACE, false);
      prefs.putFloat("auto_start", autoStartLevel);
      prefs.putFloat("auto_stop", autoStopLevel);
      prefs.putBool("dry_run", dryRunProtectionEnabled);
      prefs.end();
      Serial.printf("[SYSTEM] Automation Rules Updated: Start at %.1f%%, Stop at %.1f%%\n", autoStartLevel, autoStopLevel);
      notifyMqttStatusUpdate = true;
    } else if (strcasecmp(action, "TOGGLE_PUMP") == 0 || strcasecmp(action, "TOGGLE") == 0) {
      bool subAlive = (lastSensorPacketTime > 0 && (millis() - lastSensorPacketTime) < SUB_NODE_TIMEOUT_MS);
      if (!pumpRunning && systemMode == "AUTO" && !subAlive) {
        Serial.println("[MQTT] 🔒 Toggle start rejected: Sub-node disconnected in AUTO mode.");
        notifyMqttStatusUpdate = true;
        return;
      }
      requestedPumpState = !pumpRunning;
      pendingCmdReason = "MQTT Toggle";
      pendingCmdId = String(cmdId);
      hasPendingPumpCommand = true;
    } else if (strcasecmp(action, "EMERGENCY_STOP") == 0) {
      emergencyStopped = true;
      requestedPumpState = false;
      pendingCmdReason = "MQTT Emergency Stop";
      pendingCmdId = String(cmdId);
      hasPendingPumpCommand = true;
    } else if (strcasecmp(action, "CLEAR_EMERGENCY") == 0) {
      emergencyStopped = false;
      Serial.println("[Safety] Emergency Stop state cleared remotely via MQTT.");
      notifyMqttStatusUpdate = true;
    } else if (strcasecmp(action, "PING") == 0 || strstr(topic, "/ping") != NULL || strcmp(topic, "pump/ping") == 0) {
      StaticJsonDocument<384> pongDoc;
      pongDoc["ping_id"] = doc["ping_id"] | doc["pingId"] | "ping_req";
      pongDoc["deviceId"] = deviceId;
      pongDoc["device_id"] = deviceId;
      pongDoc["status"] = "ONLINE";
      pongDoc["state"] = "ONLINE";
      pongDoc["pumpState"] = pumpRunning ? "RUNNING" : "STOPPED";
      pongDoc["mode"] = systemMode;
      pongDoc["subNodeOnline"] = (lastSensorPacketTime > 0 && (millis() - lastSensorPacketTime) < SUB_NODE_TIMEOUT_MS);
      pongDoc["uptime_ms"] = millis();
      pongDoc["client_timestamp_ms"] = doc["timestamp_ms"] | doc["timestamp"] | 0;
      pongDoc["free_heap"] = ESP.getFreeHeap();
      pongDoc["rssi"] = WiFi.RSSI();
      pongDoc["timestamp"] = millis() / 1000;
      String pongOut;
      serializeJson(pongDoc, pongOut);
      mqttClient.publish("pump/pong", pongOut.c_str(), false);
      mqttClient.publish(("pump/" + deviceId + "/pong").c_str(), pongOut.c_str(), false);
      notifyMqttStatusUpdate = true;
    } else if (strcasecmp(action, "GET_STATUS") == 0 || strcasecmp(action, "STATUS") == 0) {
      Serial.println("[MQTT] Immediate Status request received from App. Dispatching live state...");
      notifyMqttStatusUpdate = true;
    } else if (strcasecmp(action, "FACTORY_RESET") == 0 || strcasecmp(action, "HARD_RESET") == 0 || strcasecmp(action, "RESET") == 0 || strcasecmp(action, "REMOVE") == 0) {
      Serial.println("[MQTT] Reset / Remove command received from Mobile App. Executing hardware wipe...");
      executeFactoryReset();
    }
  }
}

void sendHttpBackendTelemetry() {
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  http.begin(storedBackendUrl);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(2000);

  StaticJsonDocument<384> doc;
  doc["deviceId"] = deviceId;
  doc["waterLevel"] = (lastSensorPacketTime > 0 && (millis() - lastSensorPacketTime) < SUB_NODE_TIMEOUT_MS) ? currentLevelPct : -1;
  doc["waterVolume"] = currentVolumeL;
  doc["flowRate"] = currentFlowRateLpm;
  doc["temperature"] = currentTempC;
  doc["tds"] = currentTdsPpm;
  doc["battery"] = currentBatteryV;
  doc["pumpState"] = pumpRunning ? "RUNNING" : "STOPPED";
  doc["mode"] = systemMode;
  doc["rssi"] = WiFi.RSSI();

  String payload;
  serializeJson(doc, payload);

  int httpCode = http.POST(payload);
  if (httpCode > 0) {
    Serial.printf("[HTTP API] Telemetry sent (Code: %d)\n", httpCode);
  }
  http.end();
}

// ==============================================================================
// 10. ESP-NOW CENTRAL HUB (INTERRUPT-SAFE & NON-BLOCKING)
// ==============================================================================
volatile bool newSensorPacketAvailable = false;
SensorTelemetryPacket cachedSensorPacket;
portMUX_TYPE sensorMux = portMUX_INITIALIZER_UNLOCKED;

#if defined(ESP_IDF_VERSION) && ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 0, 0)
void onEspNowDataRecv(const esp_now_recv_info_t *info, const uint8_t *incomingData, int len) {
#else
void onEspNowDataRecv(const uint8_t *mac_addr, const uint8_t *incomingData, int len) {
#endif
  if (len == sizeof(SensorTelemetryPacket)) {
    SensorTelemetryPacket packet;
    memcpy(&packet, incomingData, sizeof(packet));

    if (packet.header == 0xAA55) {
      uint16_t calcCrc = calculateCRC16((uint8_t*)&packet, sizeof(packet) - sizeof(uint16_t));
      if (calcCrc == packet.checksum) {
        portENTER_CRITICAL_ISR(&sensorMux);
        cachedSensorPacket = packet;
        currentLevelPct = packet.waterLevelPct;
        currentVolumeL = packet.waterVolumeL;
        currentFlowRateLpm = packet.flowRateLpm;
        currentTempC = packet.waterTempC;
        currentTdsPpm = packet.tdsPpm;
        currentBatteryV = packet.batteryVoltage;
        lastPacketSeq = packet.sequence;
        lastSensorPacketTime = millis();
        newSensorPacketAvailable = true;
        portEXIT_CRITICAL_ISR(&sensorMux);
      }
    }
  }
}

// ==============================================================================
// 11. FREERTOS CORE 0: TASK NETWORK (Wi-Fi, MQTT, LWT, Heartbeat)
// ==============================================================================
void TaskNetwork(void *pvParameters) {
  unsigned long lastReport = 0;
  unsigned long lastLedToggle = 0;
  bool ledBlinkState = false;

  for (;;) {
    // 0. Handle Asynchronous BLE Wi-Fi Provisioning Request
    if (pendingWifiProvisioning) {
      pendingWifiProvisioning = false;
      Serial.printf("\n[WiFi Manager] Processing BLE Wi-Fi credentials for SSID: '%s'...\n", incomingSsid.c_str());
      
      bool ok = connectWifi(incomingSsid, incomingPass);
      if (ok) {
        Serial.println("[BLE] Connection SUCCESS! Notifying mobile application...");
        updateBleStatus("SUCCESS", WiFi.localIP().toString());
        vTaskDelay(pdMS_TO_TICKS(1200)); // Allow BLE packet to transmit over air
        stopBleProvisioning();
      } else {
        Serial.println("[BLE] Connection FAILED. Notifying mobile application...");
        updateBleStatus("ERROR", "", "Failed to connect to Wi-Fi. Check SSID and Password.");
      }
    }

    if (WiFi.status() != WL_CONNECTED) {
      // Blink Network LED when Wi-Fi is disconnected (500ms interval)
      if (millis() - lastLedToggle > 500) {
        lastLedToggle = millis();
        ledBlinkState = !ledBlinkState;
        digitalWrite(PIN_LED_NETWORK, ledBlinkState ? HIGH : LOW);
      }
      // Reconnect using stored credentials
      if (storedSSID.length() > 0 && millis() - lastMqttRetry > 10000) {
        lastMqttRetry = millis();
        Serial.println("[WiFi] Reconnecting to Wi-Fi...");
        WiFi.reconnect();
      }
      vTaskDelay(pdMS_TO_TICKS(50));
      continue;
    }

    // Wi-Fi Connected: Solid blue network LED
    digitalWrite(PIN_LED_NETWORK, HIGH);

    // MQTT Connection Management
    if (!mqttClient.connected()) {
      if (millis() - lastMqttRetry > 3500) {
        lastMqttRetry = millis();
        const char* targetBroker = DEFAULT_MQTT_BROKER;
        mqttClient.setServer(targetBroker, DEFAULT_MQTT_PORT);

        String clientId = deviceId + "_" + String(random(1000, 9999));
        String lwtPayload = "{\"deviceId\":\"" + deviceId + "\",\"status\":\"OFFLINE\",\"subNodeOnline\":false,\"waterLevel\":-1}";

        Serial.printf("[MQTT] Connecting to EMQX Cloud '%s:1883' with LWT...\n", targetBroker);
        if (mqttClient.connect(clientId.c_str(), ("pump/" + deviceId + "/status").c_str(), 1, true, lwtPayload.c_str())) {
          Serial.printf("[MQTT] Connected to EMQX Broker: %s!\n", targetBroker);

          // Subscriptions - commands, wildcards, and fast ping topics
          String cmdTopic = "pump/" + deviceId + "/command";
          String pingTopic = "pump/" + deviceId + "/ping";
          mqttClient.subscribe("pump/command");
          mqttClient.subscribe(cmdTopic.c_str());
          mqttClient.subscribe("pump/ping");
          mqttClient.subscribe(pingTopic.c_str());
          mqttClient.subscribe("waterpump/esp32/control");
          mqttClient.subscribe("pump/+/+/command");
          mqttClient.subscribe("pump/+/+/ping");

          // Send immediate live ONLINE status
          StaticJsonDocument<256> initDoc;
          initDoc["deviceId"] = deviceId;
          initDoc["status"] = "ONLINE";
          initDoc["pumpState"] = pumpRunning ? "RUNNING" : "STOPPED";
          initDoc["mode"] = systemMode;
          initDoc["emergencyStopped"] = emergencyStopped;
          bool subAlive = (lastSensorPacketTime > 0 && (millis() - lastSensorPacketTime) < SUB_NODE_TIMEOUT_MS);
          initDoc["subNodeOnline"] = subAlive;
          initDoc["waterLevel"] = subAlive ? currentLevelPct : -1;
          initDoc["waterVolume"] = subAlive ? currentVolumeL : 0;
          initDoc["flowRate"] = subAlive ? currentFlowRateLpm : 0;
          initDoc["tds"] = subAlive ? currentTdsPpm : 0;
          initDoc["ip"] = WiFi.localIP().toString();
          initDoc["rssi"] = WiFi.RSSI();
          String initOut;
          serializeJson(initDoc, initOut);
          mqttClient.publish("pump/status", initOut.c_str(), false);
          mqttClient.publish(("pump/" + deviceId + "/status").c_str(), initOut.c_str(), false);
          Serial.printf("[MQTT] Broadcasted live ONLINE status for %s\n", deviceId.c_str());
        } else {
          Serial.printf("[MQTT] EMQX connect failed (State: %d). Retrying in 3.5s...\n", mqttClient.state());
        }
      }
    } else {
      mqttClient.loop();

      // 1. Asynchronous Telemetry Dispatch from Sub Node (High-frequency ~100ms, non-blocking)
      static unsigned long lastTelMqttSend = 0;
      if (newSensorPacketAvailable && (millis() - lastTelMqttSend >= 100)) {
        lastTelMqttSend = millis();
        newSensorPacketAvailable = false;

        SensorTelemetryPacket p;
        portENTER_CRITICAL(&sensorMux);
        p = cachedSensorPacket;
        portEXIT_CRITICAL(&sensorMux);

        StaticJsonDocument<384> telDoc;
        telDoc["deviceId"] = deviceId;
        telDoc["nodeType"] = "SUB_NODE";
        telDoc["subNodeId"] = p.nodeId;
        telDoc["sequence"] = p.sequence;
        telDoc["waterLevel"] = p.waterLevelPct;
        telDoc["waterVolume"] = p.waterVolumeL;
        telDoc["flowRate"] = p.flowRateLpm;
        telDoc["temperature"] = p.waterTempC;
        telDoc["tds"] = p.tdsPpm;
        telDoc["battery"] = p.batteryVoltage;
        telDoc["pumpState"] = pumpRunning ? "RUNNING" : "STOPPED";
        telDoc["mode"] = systemMode;
        telDoc["timestamp"] = millis();

        String telJson;
        serializeJson(telDoc, telJson);
        mqttClient.publish("pump/telemetry", telJson.c_str(), false);
        mqttClient.publish(("pump/" + deviceId + "/telemetry").c_str(), telJson.c_str(), false);
        mqttClient.publish(("devices/" + deviceId + "/telemetry").c_str(), telJson.c_str(), false);
      }

      // 2. Asynchronous Status and ACK Dispatch
      if (notifyMqttStatusUpdate) {
        notifyMqttStatusUpdate = false;
        StaticJsonDocument<256> doc;
        doc["deviceId"] = deviceId;
        doc["nodeType"] = "MAIN_NODE";
        doc["status"] = "ONLINE";
        doc["pumpState"] = pumpRunning ? "RUNNING" : "STOPPED";
        doc["mode"] = systemMode;
        doc["emergencyStopped"] = emergencyStopped;
        bool subAlive = (lastSensorPacketTime > 0 && (millis() - lastSensorPacketTime) < SUB_NODE_TIMEOUT_MS);
        doc["subNodeOnline"] = subAlive;
        doc["waterLevel"] = subAlive ? currentLevelPct : -1;
        doc["waterVolume"] = subAlive ? currentVolumeL : -1;
        doc["ip"] = WiFi.localIP().toString();
        doc["rssi"] = WiFi.RSSI();
        doc["timestamp"] = millis();
        String out;
        serializeJson(doc, out);
        mqttClient.publish("pump/status", out.c_str(), false);
        mqttClient.publish("pump/heartbeat", out.c_str(), false);
        mqttClient.publish(("pump/" + deviceId + "/status").c_str(), out.c_str(), false);

        if (pendingCmdId.length() > 0) {
          StaticJsonDocument<256> ack;
          ack["commandId"] = pendingCmdId;
          ack["command"] = pendingCmdReason;
          ack["status"] = "SUCCESS";
          ack["pumpStatus"] = pumpRunning ? "ON" : "OFF";
          ack["pumpState"] = pumpRunning ? "RUNNING" : "STOPPED";
          ack["mode"] = systemMode;
          ack["emergencyStopped"] = emergencyStopped;
          ack["timestamp"] = millis();
          String ackStr;
          serializeJson(ack, ackStr);
          mqttClient.publish("pump/command/ack", ackStr.c_str());
          mqttClient.publish(("pump/" + deviceId + "/command/ack").c_str(), ackStr.c_str());
          pendingCmdId = "";
        }
      }

      // 3. Dedicated Main Node Heartbeat & Live Telemetry (every 1.0 second)
      if (millis() - lastReport > STATUS_REPORT_INTERVAL) {
        lastReport = millis();
        StaticJsonDocument<384> doc;
        doc["deviceId"] = deviceId;
        doc["nodeType"] = "MAIN_NODE";
        doc["status"] = "ONLINE";
        doc["pumpState"] = pumpRunning ? "RUNNING" : "STOPPED";
        doc["mode"] = systemMode;
        doc["emergencyStopped"] = emergencyStopped;
        bool subAlive = (lastSensorPacketTime > 0 && (millis() - lastSensorPacketTime) < SUB_NODE_TIMEOUT_MS);
        doc["subNodeOnline"] = subAlive;
        doc["waterLevel"] = subAlive ? currentLevelPct : -1;
        doc["waterVolume"] = subAlive ? currentVolumeL : -1;
        doc["flowRate"] = currentFlowRateLpm;
        doc["temperature"] = currentTempC;
        doc["tds"] = currentTdsPpm;
        doc["battery"] = currentBatteryV;
        doc["ip"] = WiFi.localIP().toString();
        doc["rssi"] = WiFi.RSSI();
        doc["timestamp"] = millis();
        String out;
        serializeJson(doc, out);
        mqttClient.publish("pump/status", out.c_str(), false);
        mqttClient.publish("pump/heartbeat", out.c_str(), false);
        mqttClient.publish("pump/telemetry", out.c_str(), false);
        mqttClient.publish(("devices/" + deviceId + "/heartbeat").c_str(), out.c_str(), false);
        mqttClient.publish(("pump/" + deviceId + "/status").c_str(), out.c_str(), false);
        mqttClient.publish(("pump/" + deviceId + "/telemetry").c_str(), out.c_str(), false);
      }
    }

    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

// ==============================================================================
// 12. FREERTOS CORE 1: TASK CONTROL (Manual Button, Relay, Reset, Safety Engine)
// ==============================================================================
void TaskControl(void *pvParameters) {
  int bootBtnCounter = 0;
  int emergencyCounter = 0;
  int manualBtnCounter = 0;
  bool manualBtnLatched = false;

  for (;;) {
    // 0. Execute Pending Remote Pump Command from MQTT or App
    if (hasPendingPumpCommand) {
      hasPendingPumpCommand = false;
      setPumpState(requestedPumpState, pendingCmdReason);
    }
    // 1. Hard Reset Button Handler (BOOT / GPIO 0 - Hold 1.5s with bounce immunity)
    if (digitalRead(PIN_HARD_RESET) == LOW) {
      bootBtnCounter++;
      if (bootBtnCounter == 1) {
        Serial.println("[RESET BTN] BOOT button pressed. Hold for 1.5s to Factory Reset...");
      } else if (bootBtnCounter % 6 == 0) {
        Serial.printf("[RESET BTN] Holding BOOT button... (%d ms / 1500 ms)\n", bootBtnCounter * 50);
      }
      if (bootBtnCounter >= 30) { // 30 * 50ms = 1500ms
        executeFactoryReset();
      }
    } else {
      if (bootBtnCounter > 0) bootBtnCounter -= 2; // Smooth decay prevents contact bounce resets
      if (bootBtnCounter < 0) bootBtnCounter = 0;
    }

    // 2. Serial Monitor Reset Command Listener
    if (Serial.available()) {
      String cmd = Serial.readStringUntil('\n');
      cmd.trim();
      if (cmd.equalsIgnoreCase("reset") || cmd.equalsIgnoreCase("factory")) {
        executeFactoryReset();
      } else if (cmd.equalsIgnoreCase("pump on") || cmd.equalsIgnoreCase("on")) {
        setPumpState(true, "Serial Command");
      } else if (cmd.equalsIgnoreCase("pump off") || cmd.equalsIgnoreCase("off")) {
        setPumpState(false, "Serial Command");
      } else if (cmd.equalsIgnoreCase("auto")) {
        systemMode = "AUTO";
        Serial.println("[SYSTEM] Mode changed to AUTO");
      } else if (cmd.equalsIgnoreCase("manual")) {
        systemMode = "MANUAL";
        Serial.println("[SYSTEM] Mode changed to MANUAL");
      }
    }

    // 3. Hardware Emergency Stop Switch (Requires sustained 250ms LOW to prevent false trips from inductive relay noise)
    if (digitalRead(PIN_EMERGENCY_STOP) == LOW) {
      emergencyCounter++;
      if (emergencyCounter >= 5) { // 5 * 50ms = 250ms continuous LOW
        if (!emergencyStopped) {
          emergencyStopped = true;
          setPumpState(false, "Hardware Emergency Button Pressed");
        }
      }
    } else {
      emergencyCounter = 0;
    }

    // 4. Manual Switching Push Button (Debounced toggle - requires sustained 150ms press)
    if (digitalRead(PIN_MANUAL_BUTTON) == LOW) {
      manualBtnCounter++;
      if (manualBtnCounter >= 3 && !manualBtnLatched) {
        manualBtnLatched = true;
        setPumpState(!pumpRunning, "Manual Physical Toggle Button");
      }
    } else {
      manualBtnCounter = 0;
      manualBtnLatched = false;
    }

    // 5. Autonomous Automation & Safety Engine
    bool subAlive = (lastSensorPacketTime > 0 && (millis() - lastSensorPacketTime) < SUB_NODE_TIMEOUT_MS);
    if (systemMode == "AUTO") {
      if (!subAlive) {
        // SAFETY INTERLOCK: In AUTO mode, if sub-node is not connected with main node, motor must NOT work!
        if (pumpRunning) {
          setPumpState(false, "Sub-Node Disconnected Safety Cutoff (Auto Mode Locked)");
        }
      } else if (currentLevelPct >= 0.0f) {
        // High Level Cutoff
        if (pumpRunning && currentLevelPct >= autoStopLevel) {
          setPumpState(false, "Tank High Level Cutoff (" + String(currentLevelPct, 1) + "%)");
        }
        // Low Level Auto Refill
        if (!pumpRunning && currentLevelPct <= autoStartLevel && !emergencyStopped) {
          setPumpState(true, "Tank Low Level Auto Refill (" + String(currentLevelPct, 1) + "%)");
        }
      }
    }

    // 6. Max Continuous Runtime Safety Cutoff (30 minutes)
    if (pumpRunning && (millis() - pumpStartTime > MAX_RUN_TIME_LIMIT_MS)) {
      setPumpState(false, "Continuous Max Run Time Limit Reached (30 Mins)");
    }

    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

// ==============================================================================
// 13. SYSTEM INITIALIZATION & MAIN SETUP
// ==============================================================================
void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0); // Disable brownout detector to prevent reboot on power sag

  Serial.begin(115200);
  delay(500);
  Serial.println("\n=======================================================");
  Serial.println("   HydroPulse ESP32 Gateway Node Booting (v2.0.0)");
  Serial.println("=======================================================");

  // Pin Configurations
  pinMode(PIN_RELAY_PUMP, OUTPUT);
  pinMode(PIN_LED_NETWORK, OUTPUT);
  pinMode(PIN_LED_PUMP, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_EMERGENCY_STOP, INPUT_PULLUP);
  pinMode(PIN_MANUAL_BUTTON, INPUT_PULLUP);
  pinMode(PIN_HARD_RESET, INPUT_PULLUP);

  // Initialize all outputs to safe OFF state
  digitalWrite(PIN_RELAY_PUMP, RELAY_ACTIVE_LOW ? HIGH : LOW);
  digitalWrite(PIN_LED_PUMP, LOW);
  digitalWrite(PIN_BUZZER, LOW);

  // Diagnostic: Print hardware reset reason
  esp_reset_reason_t rst_reason = esp_reset_reason();
  const char* rst_str = "NORMAL BOOT";
  switch (rst_reason) {
    case ESP_RST_POWERON:   rst_str = "POWER ON (Cold Boot)"; break;
    case ESP_RST_SW:        rst_str = "SOFTWARE RESTART"; break;
    case ESP_RST_PANIC:     rst_str = "EXCEPTION / CRASH"; break;
    case ESP_RST_BROWNOUT:  rst_str = "BROWNOUT (Voltage dipped below 2.5V from motor surge!)"; break;
    default: break;
  }
  Serial.printf("[SYSTEM] Reset Reason: %s (Code: %d)\n", rst_str, rst_reason);

  // Load Saved Configuration from NVS
  prefs.begin(NVS_NAMESPACE, false);
  systemMode = prefs.getString("sys_mode", "AUTO");
  autoStartLevel = prefs.getFloat("auto_start", 25.0f);
  autoStopLevel = prefs.getFloat("auto_stop", 95.0f);
  dryRunProtectionEnabled = prefs.getBool("dry_run", true);
  prefs.end();

  Serial.printf("[SYSTEM] Mode: %s | Auto-Start: %.0f%% | Auto-Stop: %.0f%%\n",
                systemMode.c_str(), autoStartLevel, autoStopLevel);

  // Instant Power-On Reset Check (Hold BOOT button at power-on for 1.2s)
  if (digitalRead(PIN_HARD_RESET) == LOW) {
    Serial.println("[BOOT] BOOT button pressed at power-on! Hold 1.2s for Factory Reset...");
    unsigned long bootPressStart = millis();
    while (digitalRead(PIN_HARD_RESET) == LOW) {
      delay(40);
      if (millis() - bootPressStart >= 1200) {
        executeFactoryReset();
      }
    }
    Serial.println("[BOOT] BOOT button released. Proceeding with standard boot.");
  }

  // 1. Wi-Fi & ESP-NOW Setup
  WiFi.mode(WIFI_AP_STA);
  WiFi.setSleep(false); // Disable modem sleep to prevent radio drops
  esp_wifi_set_ps(WIFI_PS_NONE);

  // Generate Unique Device ID from Hardware MAC Address
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char devIdBuf[32];
  snprintf(devIdBuf, sizeof(devIdBuf), "%s%02X%02X%02X", DEFAULT_DEVICE_PREFIX, mac[3], mac[4], mac[5]);
  deviceId = String(devIdBuf);

  Serial.printf("[SYSTEM] Device ID: %s | Hardware MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
                deviceId.c_str(), mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

  if (esp_now_init() == ESP_OK) {
    Serial.println("[ESP-NOW] Subsystem initialized successfully!");
    esp_now_register_recv_cb(onEspNowDataRecv);

    // Register Broadcast Peer for ESP8266 Sub Node
    esp_now_peer_info_t peerInfo = {};
    memset(&peerInfo, 0, sizeof(peerInfo));
    for (int i = 0; i < 6; i++) peerInfo.peer_addr[i] = 0xFF;
    peerInfo.channel = 0; // Receive on any channel
    peerInfo.encrypt = false;
    if (esp_now_add_peer(&peerInfo) == ESP_OK) {
      Serial.println("[ESP-NOW] Broadcast peer registered (Listening for ESP8266 Sub Nodes).");
    }
  } else {
    Serial.println("[ESP-NOW] ERROR: Init Failed!");
  }

  Serial.printf("[WiFi] Initial Radio Channel: %d\n", WiFi.channel());

  // 2. Read Stored Wi-Fi from Flash NVS
  prefs.begin(NVS_NAMESPACE, false);
  storedSSID = prefs.getString("wifi_ssid", "");
  storedPass = prefs.getString("wifi_pass", "");
  prefs.end();

  bool wifiAutoConnected = false;
  if (storedSSID.length() > 0) {
    Serial.printf("[NVS] Found saved Wi-Fi: '%s'. Auto-connecting...\n", storedSSID.c_str());
    wifiAutoConnected = connectWifi(storedSSID, storedPass);
    Serial.printf("[WiFi] Post-Connect Radio Channel: %d\n", WiFi.channel());
  }

  // 3. Start BLE Provisioning only if Wi-Fi is not connected
  if (!wifiAutoConnected) {
    Serial.println("[BLE] Wi-Fi not connected. Starting BLE Provisioning server for app pairing...");
    startBleProvisioning();
  } else {
    Serial.println("[BLE] Saved Wi-Fi connected directly. BLE Provisioning bypassed.");
  }

  // 4. MQTT Client Setup
  mqttClient.setServer(DEFAULT_MQTT_BROKER, DEFAULT_MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(512);
  mqttClient.setKeepAlive(30);

  // 5. Spawn FreeRTOS Dual-Core Tasks
  xTaskCreatePinnedToCore(TaskNetwork, "NetTask", 8192, NULL, 1, &TaskNetworkHandle, 0); // Core 0
  xTaskCreatePinnedToCore(TaskControl, "CtrlTask", 8192, NULL, 2, &TaskControlHandle, 1); // Core 1

  Serial.println("=======================================================");
  Serial.println(">> SYSTEM READY!");
  Serial.println(">> PUMP RELAY: GPIO 23 | MANUAL BUTTON: GPIO 19 | EMERGENCY: GPIO 18");
  Serial.println(">> FACTORY RESET: Hold BOOT (GPIO 0) for 1.5s or type 'reset' in Serial.");
  Serial.println("=======================================================\n");
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
