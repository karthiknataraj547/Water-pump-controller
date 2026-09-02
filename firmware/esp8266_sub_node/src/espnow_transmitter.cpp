#include "espnow_transmitter.h"
#include "config.h"

EspNowTransmitter espnowTx;

EspNowTransmitter::EspNowTransmitter()
  : paired(false), activeChannel(1), sequenceNumber(0),
    lastTelemetryTime(0), lastPairingAttempt(0) {
  // Default broadcast MAC for initial pairing discovery
  memset(gatewayMac, 0xFF, 6);
}

bool EspNowTransmitter::begin() {
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();

  if (esp_now_init() != 0) {
    Serial.println("[ESP-NOW] Error initializing ESP-NOW on ESP8266");
    return false;
  }

  esp_now_set_self_role(ESP_NOW_ROLE_COMBO);
  esp_now_register_send_cb(EspNowTransmitter::onDataSent);
  esp_now_register_recv_cb(EspNowTransmitter::onDataRecv);

  // Register broadcast peer
  uint8_t broadcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  esp_now_add_peer(broadcast, ESP_NOW_ROLE_COMBO, 1, NULL, 0);

  Serial.println("[ESP-NOW] Transmitter initialized. Starting pairing scan...");
  return true;
}

void EspNowTransmitter::startPairingScan() {
  // Hop through channels 1 to 13 to locate Gateway's active Wi-Fi channel
  activeChannel = (activeChannel % 13) + 1;
  wifi_set_channel(activeChannel);

  EspNowPairingRequest req;
  req.packet_type = PKT_PAIRING_REQUEST;
  req.protocol_version = 0x01;
  strncpy(req.sub_node_id, DEFAULT_NODE_ID, sizeof(req.sub_node_id) - 1);
  WiFi.macAddress(req.mac_address);
  req.requested_channel = activeChannel;
  req.crc16 = calculateCRC16((const uint8_t*)&req, sizeof(EspNowPairingRequest) - sizeof(uint16_t));

  uint8_t broadcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  esp_now_send(broadcast, (uint8_t*)&req, sizeof(req));

  Serial.printf("[ESP-NOW] Broadcasted pairing probe on Channel %d...\n", activeChannel);
}

bool EspNowTransmitter::sendSensorTelemetry(const SensorReadings &readings) {
  if (!paired) return false;

  sequenceNumber++;
  EspNowSensorPacket pkt;
  pkt.packet_type = PKT_SENSOR_TELEMETRY;
  pkt.protocol_version = 0x01;
  strncpy(pkt.sub_node_id, DEFAULT_NODE_ID, sizeof(pkt.sub_node_id) - 1);
  pkt.seq_num = sequenceNumber;
  pkt.water_level_pct = readings.waterLevelPct;
  pkt.water_level_cm = readings.waterLevelCm;
  pkt.flow_rate_lpm = readings.flowRateLpm;
  pkt.total_water_liters = readings.totalWaterLiters;
  pkt.tds_ppm = readings.tdsPpm;
  pkt.temperature_c = readings.temperatureC;
  pkt.battery_voltage = readings.batteryVoltage;
  pkt.battery_pct = readings.batteryPct;
  pkt.sensor_flags = readings.statusFlags;
  pkt.crc16 = calculateCRC16((const uint8_t*)&pkt, sizeof(EspNowSensorPacket) - sizeof(uint16_t));

  int res = esp_now_send(gatewayMac, (uint8_t*)&pkt, sizeof(pkt));
  return (res == 0);
}

void EspNowTransmitter::loop() {
  unsigned long now = millis();

  // If not paired yet, scan channels every 1.5 seconds
  if (!paired && (now - lastPairingAttempt > 1500)) {
    lastPairingAttempt = now;
    startPairingScan();
  }

  // Periodic telemetry transmission
  if (paired && (now - lastTelemetryTime > TELEMETRY_INTERVAL_MS)) {
    lastTelemetryTime = now;
    sensorMgr.update();
    sendSensorTelemetry(sensorMgr.getReadings());
  }
}

void EspNowTransmitter::onDataSent(uint8_t *mac_addr, uint8_t sendStatus) {
  if (sendStatus == 0) {
    digitalWrite(PIN_LED_STATUS, LOW); // Flash LED on success
    delay(10);
    digitalWrite(PIN_LED_STATUS, HIGH);
  } else {
    Serial.println("[ESP-NOW] Packet delivery failed.");
  }
}

void EspNowTransmitter::onDataRecv(uint8_t *mac_addr, uint8_t *data, uint8_t len) {
  if (len < 2) return;

  uint8_t packetType = data[0];
  if (packetType == PKT_PAIRING_RESPONSE && len == sizeof(EspNowPairingResponse)) {
    const EspNowPairingResponse *resp = (const EspNowPairingResponse*)data;

    // Check CRC
    uint16_t expectedCrc = calculateCRC16((const uint8_t*)resp, sizeof(EspNowPairingResponse) - sizeof(uint16_t));
    if (resp->crc16 == expectedCrc) {
      memcpy(espnowTx.gatewayMac, mac_addr, 6);
      espnowTx.activeChannel = resp->locked_channel;
      espnowTx.paired = true;

      // Register Gateway as dedicated peer
      esp_now_add_peer(espnowTx.gatewayMac, ESP_NOW_ROLE_COMBO, espnowTx.activeChannel, NULL, 0);

      Serial.printf("[ESP-NOW] 🎉 PAIRED with Gateway '%s' on Channel %d!\n",
                    resp->gateway_id, espnowTx.activeChannel);
    }
  }
}
