#ifndef MQTT_MANAGER_H
#define MQTT_MANAGER_H

#include <PubSubClient.h>
#include <WiFiClient.h>
#include <ArduinoJson.h>

class MqttManager {
public:
  MqttManager();
  void begin();
  void loop();
  bool isConnected();

  void publishStatus(const String &pumpState, const String &mode, uint32_t runDurationSec, const String &safetyStatus);
  void publishSensorData(const String &subNodeId, uint32_t seqNum, float levelPct, float levelCm, float flowLpm, float totalLiters, uint16_t tds, float temp, float batVolt, uint8_t batPct);
  void publishAck(const String &commandId, const String &status, const String &message, uint32_t execTimeMs);
  void publishPong(const String &pingId, uint32_t clientTimestampMs);
  void publishAlert(const String &severity, const String &type, const String &description);

  void setServer(const String &host, uint16_t port);
  void setCredentials(const String &user, const String &pass);
  void setUserId(const String &userId);

private:
  void reconnect();
  static void onMessageReceived(char* topic, byte* payload, unsigned int length);

  WiFiClient wifiClient;
  PubSubClient client;
  String brokerHost;
  uint16_t brokerPort;
  String mqttUser;
  String mqttPass;
  String userId;
  unsigned long lastReconnectAttempt;
  unsigned long lastStatusPublish;
};

extern MqttManager mqttMgr;

#endif // MQTT_MANAGER_H
