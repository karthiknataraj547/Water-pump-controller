#ifndef ESPNOW_TRANSMITTER_H
#define ESPNOW_TRANSMITTER_H

#include <ESP8266WiFi.h>
#include <espnow.h>
#include "protocol.h"
#include "sensor_manager.h"

class EspNowTransmitter {
public:
  EspNowTransmitter();
  bool begin();
  void loop();

  bool sendSensorTelemetry(const SensorReadings &readings);
  bool isPaired() const { return paired; }
  void startPairingScan();

  static void onDataSent(uint8_t *mac_addr, uint8_t sendStatus);
  static void onDataRecv(uint8_t *mac_addr, uint8_t *data, uint8_t len);

private:
  uint8_t gatewayMac[6];
  bool paired;
  uint8_t activeChannel;
  uint32_t sequenceNumber;
  unsigned long lastTelemetryTime;
  unsigned long lastPairingAttempt;
};

extern EspNowTransmitter espnowTx;

#endif // ESPNOW_TRANSMITTER_H
