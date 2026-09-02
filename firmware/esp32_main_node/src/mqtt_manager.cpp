#include "mqtt_manager.h"
#include "wifi_manager.h"
#include "config.h"
#include "pump_controller.h"
#include "automation_engine.h"

MqttManager mqttMgr;

MqttManager::MqttManager()
  : client(wifiClient), brokerHost(DEFAULT_MQTT_BROKER), brokerPort(DEFAULT_MQTT_PORT),
    userId("usr_demo_001"), lastReconnectAttempt(0), lastStatusPublish(0) {}

void MqttManager::begin() {
  client.setServer(brokerHost.c_str(), brokerPort);
  client.setCallback(MqttManager::onMessageReceived);
  client.setBufferSize(2048);
}

void MqttManager::setServer(const String &host, uint16_t port) {
  brokerHost = host;
  brokerPort = port;
  client.setServer(brokerHost.c_str(), brokerPort);
}

void MqttManager::setCredentials(const String &user, const String &pass) {
  mqttUser = user;
  mqttPass = pass;
}

void MqttManager::setUserId(const String &uid) {
  userId = uid;
}

bool MqttManager::isConnected() {
  return client.connected();
}

void MqttManager::reconnect() {
  if (!wifiMgr.isConnected()) return;

  unsigned long now = millis();
  if (now - lastReconnectAttempt > 5000) {
    lastReconnectAttempt = now;
    String devId = wifiMgr.getDeviceId();
    String lwtTopic = "pump/" + userId + "/" + devId + "/status";

    StaticJsonDocument<256> lwtDoc;
    lwtDoc["device_id"] = devId;
    lwtDoc["state"] = "OFFLINE";
    lwtDoc["pump_state"] = "OFF";
    lwtDoc["timestamp"] = millis() / 1000;
    String lwtPayload;
    serializeJson(lwtDoc, lwtPayload);

    Serial.printf("[MQTT] Connecting to broker %s:%d as '%s'...\n", brokerHost.c_str(), brokerPort, devId.c_str());

    bool success = false;
    if (mqttUser.length() > 0) {
      success = client.connect(devId.c_str(), mqttUser.c_str(), mqttPass.c_str(),
                               lwtTopic.c_str(), 0, true, lwtPayload.c_str());
    } else {
      success = client.connect(devId.c_str(), lwtTopic.c_str(), 0, true, lwtPayload.c_str());
    }

    if (success) {
      Serial.println("[MQTT] Connected successfully!");

      // Subscribe to command, config, and ping topics
      String cmdTopic = "pump/" + userId + "/" + devId + "/command";
      String cfgTopic = "pump/" + userId + "/" + devId + "/config";
      String pingTopic = "pump/" + userId + "/" + devId + "/ping";
      String devPingTopic = "pump/" + devId + "/ping";
      client.subscribe(cmdTopic.c_str(), 0);
      client.subscribe(cfgTopic.c_str(), 0);
      client.subscribe(pingTopic.c_str(), 0);
      client.subscribe(devPingTopic.c_str(), 0);
      client.subscribe("pump/ping", 0);

      Serial.printf("[MQTT] Subscribed to %s, %s, and %s\n", cmdTopic.c_str(), cfgTopic.c_str(), pingTopic.c_str());
    } else {
      Serial.printf("[MQTT] Connection failed, rc=%d. Will retry in 5s.\n", client.state());
    }
  }
}

void MqttManager::loop() {
  if (!client.connected()) {
    reconnect();
  } else {
    client.loop();
  }
}

void MqttManager::publishStatus(const String &pumpState, const String &mode, uint32_t runDurationSec, const String &safetyStatus) {
  if (!client.connected()) return;

  String devId = wifiMgr.getDeviceId();
  String topic = "pump/" + userId + "/" + devId + "/status";

  StaticJsonDocument<512> doc;
  doc["device_id"] = devId;
  doc["user_id"] = userId;
  doc["firmware_version"] = FIRMWARE_VERSION;
  doc["uptime_seconds"] = millis() / 1000;
  doc["wifi_rssi"] = wifiMgr.getRSSI();
  doc["state"] = "ONLINE";
  doc["pump_state"] = pumpState;
  doc["mode"] = mode;
  doc["running_duration_seconds"] = runDurationSec;
  doc["safety_status"] = safetyStatus;
  doc["free_heap_bytes"] = ESP.getFreeHeap();
  doc["timestamp"] = millis() / 1000;

  String payload;
  serializeJson(doc, payload);
  client.publish(topic.c_str(), payload.c_str(), true);
}

void MqttManager::publishPong(const String &pingId, uint32_t clientTimestampMs) {
  if (!client.connected()) return;

  String devId = wifiMgr.getDeviceId();
  String topic = "pump/" + userId + "/" + devId + "/pong";

  StaticJsonDocument<384> doc;
  doc["ping_id"] = pingId;
  doc["device_id"] = devId;
  doc["user_id"] = userId;
  doc["state"] = "ONLINE";
  doc["pump_state"] = pumpCtrl.getStateString();
  doc["mode"] = autoEngine.getModeString();
  doc["uptime_ms"] = millis();
  doc["client_timestamp_ms"] = clientTimestampMs;
  doc["free_heap"] = ESP.getFreeHeap();
  doc["wifi_rssi"] = wifiMgr.getRSSI();
  doc["timestamp"] = millis() / 1000;

  String payload;
  serializeJson(doc, payload);
  client.publish(topic.c_str(), payload.c_str(), false);
  client.publish("pump/pong", payload.c_str(), false);
}

void MqttManager::publishSensorData(const String &subNodeId, uint32_t seqNum, float levelPct, float levelCm, float flowLpm, float totalLiters, uint16_t tds, float temp, float batVolt, uint8_t batPct) {
  if (!client.connected()) return;

  String devId = wifiMgr.getDeviceId();
  String topic = "pump/" + userId + "/" + devId + "/sensor";

  StaticJsonDocument<512> doc;
  doc["device_id"] = devId;
  doc["sub_node_id"] = subNodeId;
  doc["seq_num"] = seqNum;
  doc["water_level_pct"] = levelPct;
  doc["water_level_cm"] = levelCm;
  doc["flow_rate_lpm"] = flowLpm;
  doc["total_water_liters"] = totalLiters;
  doc["tds_ppm"] = tds;
  doc["temperature_c"] = temp;
  doc["battery_voltage"] = batVolt;
  doc["battery_pct"] = batPct;
  doc["timestamp"] = millis() / 1000;

  String payload;
  serializeJson(doc, payload);
  client.publish(topic.c_str(), payload.c_str(), false);
}

void MqttManager::publishAck(const String &commandId, const String &status, const String &message, uint32_t execTimeMs) {
  if (!client.connected()) return;

  String devId = wifiMgr.getDeviceId();
  String topic = "pump/" + userId + "/" + devId + "/ack";

  StaticJsonDocument<256> doc;
  doc["command_id"] = commandId;
  doc["device_id"] = devId;
  doc["status"] = status;
  doc["message"] = message;
  doc["execution_time_ms"] = execTimeMs;
  doc["timestamp"] = millis() / 1000;

  String payload;
  serializeJson(doc, payload);
  client.publish(topic.c_str(), payload.c_str(), false);
}

void MqttManager::publishAlert(const String &severity, const String &type, const String &description) {
  if (!client.connected()) return;

  String devId = wifiMgr.getDeviceId();
  String topic = "pump/" + userId + "/" + devId + "/alert";

  StaticJsonDocument<384> doc;
  doc["device_id"] = devId;
  doc["severity"] = severity;
  doc["type"] = type;
  doc["description"] = description;
  doc["timestamp"] = millis() / 1000;

  String payload;
  serializeJson(doc, payload);
  client.publish(topic.c_str(), payload.c_str(), false);
}

void MqttManager::onMessageReceived(char* topic, byte* payload, unsigned int length) {
  String message;
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }

  Serial.printf("[MQTT] Message on topic %s: %s\n", topic, message.c_str());

  StaticJsonDocument<512> doc;
  DeserializationError error = deserializeJson(doc, message);
  if (error) {
    Serial.printf("[MQTT] JSON parse error: %s\n", error.c_str());
    return;
  }

  String topicStr = String(topic);

  // Fast Hardware Ping-Pong Handshake
  if (topicStr.endsWith("/ping") || topicStr == "pump/ping") {
    String pingId = doc["ping_id"] | doc["pingId"] | "ping_req";
    uint32_t clientTs = doc["timestamp_ms"] | doc["timestamp"] | 0;
    mqttMgr.publishPong(pingId, clientTs);
    return;
  }

  if (topicStr.endsWith("/command") || topicStr == "pump/command") {
    String cmdId = doc["command_id"] | doc["commandId"] | "";
    String cmd = doc["command"] | doc["action"] | "";
    unsigned long startT = millis();

    if (cmd == "PING") {
      mqttMgr.publishPong(cmdId, doc["timestamp_ms"] | 0);
    } else if (cmd == "PUMP_ON" || cmd == "START_PUMP") {
      bool ok = pumpCtrl.startPump("REMOTE_MQTT");
      uint32_t execMs = millis() - startT;
      mqttMgr.publishAck(cmdId, ok ? "SUCCESS" : "FAILED", ok ? "Pump started." : "Pump start aborted by safety rules.", execMs);
      mqttMgr.publishStatus(pumpCtrl.isRunning() ? "ON" : "OFF", autoEngine.getModeString(), pumpCtrl.getRunDurationSec(), "NORMAL");
    } else if (cmd == "PUMP_OFF" || cmd == "STOP_PUMP") {
      pumpCtrl.stopPump("REMOTE_MQTT");
      uint32_t execMs = millis() - startT;
      mqttMgr.publishAck(cmdId, "SUCCESS", "Pump stopped.", execMs);
      mqttMgr.publishStatus(pumpCtrl.isRunning() ? "ON" : "OFF", autoEngine.getModeString(), pumpCtrl.getRunDurationSec(), "NORMAL");
    } else if (cmd == "EMERGENCY_STOP") {
      pumpCtrl.emergencyStop("REMOTE_EMERGENCY_STOP");
      uint32_t execMs = millis() - startT;
      mqttMgr.publishAck(cmdId, "SUCCESS", "Emergency stop triggered.", execMs);
      mqttMgr.publishStatus(pumpCtrl.isRunning() ? "ON" : "OFF", autoEngine.getModeString(), pumpCtrl.getRunDurationSec(), "EMERGENCY_STOP");
    } else if (cmd == "SET_MODE") {
      String mode = doc["parameters"]["mode"] | "AUTO";
      autoEngine.setMode(mode == "MANUAL" ? MODE_MANUAL : MODE_AUTO);
      uint32_t execMs = millis() - startT;
      mqttMgr.publishAck(cmdId, "SUCCESS", "Mode updated to " + mode, execMs);
      mqttMgr.publishStatus(pumpCtrl.isRunning() ? "ON" : "OFF", autoEngine.getModeString(), pumpCtrl.getRunDurationSec(), "NORMAL");
    } else if (cmd == "SET_RULES" || cmd == "SET_CONFIG") {
      JsonObject p = doc["parameters"].as<JsonObject>();
      if (p.containsKey("autoStartLevel")) autoEngine.setAutoStartLevel(p["autoStartLevel"].as<float>());
      if (p.containsKey("auto_start_level_pct")) autoEngine.setAutoStartLevel(p["auto_start_level_pct"].as<float>());
      if (p.containsKey("autoStopLevel")) autoEngine.setAutoStopLevel(p["autoStopLevel"].as<float>());
      if (p.containsKey("auto_stop_level_pct")) autoEngine.setAutoStopLevel(p["auto_stop_level_pct"].as<float>());
      uint32_t execMs = millis() - startT;
      mqttMgr.publishAck(cmdId, "SUCCESS", "Rules updated.", execMs);
    } else if (cmd == "GET_STATUS" || cmd == "REFRESH") {
      mqttMgr.publishStatus(pumpCtrl.isRunning() ? "ON" : "OFF", autoEngine.getModeString(), pumpCtrl.getRunDurationSec(), "NORMAL");
      uint32_t execMs = millis() - startT;
      mqttMgr.publishAck(cmdId, "SUCCESS", "Status reported.", execMs);
    } else if (cmd == "RESTART_DEVICE") {
      mqttMgr.publishAck(cmdId, "SUCCESS", "Restarting ESP32 Gateway in 1s...", 10);
      delay(1000);
      ESP.restart();
    }
  } else if (topicStr.endsWith("/config")) {
    autoEngine.updateConfigFromJson(doc.as<JsonObject>());
  }
}
