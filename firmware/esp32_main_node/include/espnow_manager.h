#ifndef ESPNOW_MANAGER_H
#define ESPNOW_MANAGER_H

#include <esp_now.h>
#include <WiFi.h>
#include "protocol.h"

struct TankSensorState {
  char subNodeId[12];
  uint32_t lastSeqNum;
  float waterLevelPct;
  float waterLevelCm;
  float flowRateLpm;
  float totalWaterLiters;
  uint16_t tdsPpm;
  float temperatureC;
  float batteryVoltage;
  uint8_t batteryPct;
  unsigned long lastPacketTime;
  bool isOnline;
};

class EspNowManager {
public:
  EspNowManager();
  bool begin();
  void loop();

  TankSensorState& getSensorState() { return sensorState; }
  bool isSensorOnline() const { return sensorState.isOnline; }

  static void onDataReceive(const uint8_t *mac_addr, const uint8_t *data, int data_len);

private:
  void handleSensorPacket(const EspNowSensorPacket *pkt);
  void handlePairingRequest(const uint8_t *senderMac, const EspNowPairingRequest *pkt);

  TankSensorState sensorState;
  uint32_t packetsReceived;
  uint32_t packetsDropped;
};

extern EspNowManager espnowMgr;

#endif // ESPNOW_MANAGER_H
