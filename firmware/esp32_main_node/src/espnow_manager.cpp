#include "espnow_manager.h"
#include "mqtt_manager.h"
#include "wifi_manager.h"
#include "config.h"

EspNowManager espnowMgr;

EspNowManager::EspNowManager() : packetsReceived(0), packetsDropped(0) {
  memset(&sensorState, 0, sizeof(sensorState));
  sensorState.isOnline = false;
}

bool EspNowManager::begin() {
  if (esp_now_init() != ESP_OK) {
    Serial.println("[ESP-NOW] Error initializing ESP-NOW");
    return false;
  }

  esp_now_register_recv_cb(EspNowManager::onDataReceive);
  Serial.println("[ESP-NOW] Initialized successfully. Ready to receive sensor packets.");
  return true;
}

void EspNowManager::loop() {
  // Watchdog: detect if sub node has gone offline
  if (sensorState.isOnline && (millis() - sensorState.lastPacketTime > SENSOR_TIMEOUT_MS)) {
    sensorState.isOnline = false;
    Serial.println("[ESP-NOW] WARNING: Tank sensor sub-node timed out (OFFLINE)!");
    mqttMgr.publishAlert("WARNING", "SENSOR_OFFLINE", "Sub-node sensor packet timeout (45s without telemetry).");
  }
}

void EspNowManager::onDataReceive(const uint8_t *mac_addr, const uint8_t *data, int data_len) {
  if (data_len < 2) return;

  uint8_t packetType = data[0];

  if (packetType == PKT_SENSOR_TELEMETRY && data_len == sizeof(EspNowSensorPacket)) {
    const EspNowSensorPacket *pkt = (const EspNowSensorPacket*)data;

    // CRC16 Check
    uint16_t expectedCrc = calculateCRC16((const uint8_t*)pkt, sizeof(EspNowSensorPacket) - sizeof(uint16_t));
    if (pkt->crc16 != expectedCrc) {
      Serial.printf("[ESP-NOW] CRC mismatch! Expected: 0x%04X, Got: 0x%04X. Packet discarded.\n", expectedCrc, pkt->crc16);
      espnowMgr.packetsDropped++;
      return;
    }

    espnowMgr.handleSensorPacket(pkt);
  } else if (packetType == PKT_PAIRING_REQUEST && data_len == sizeof(EspNowPairingRequest)) {
    const EspNowPairingRequest *pkt = (const EspNowPairingRequest*)data;
    espnowMgr.handlePairingRequest(mac_addr, pkt);
  }
}

void EspNowManager::handleSensorPacket(const EspNowSensorPacket *pkt) {
  packetsReceived++;
  strncpy(sensorState.subNodeId, pkt->sub_node_id, sizeof(sensorState.subNodeId) - 1);
  sensorState.lastSeqNum = pkt->seq_num;
  sensorState.waterLevelPct = pkt->water_level_pct;
  sensorState.waterLevelCm = pkt->water_level_cm;
  sensorState.flowRateLpm = pkt->flow_rate_lpm;
  sensorState.totalWaterLiters = pkt->total_water_liters;
  sensorState.tdsPpm = pkt->tds_ppm;
  sensorState.temperatureC = pkt->temperature_c;
  sensorState.batteryVoltage = pkt->battery_voltage;
  sensorState.batteryPct = pkt->battery_pct;
  sensorState.lastPacketTime = millis();
  sensorState.isOnline = true;

  Serial.printf("[ESP-NOW] Sensor [%s] Seq:%u Level:%.1f%% Flow:%.1f LPM TDS:%u Temp:%.1fC Bat:%u%%\n",
                pkt->sub_node_id, pkt->seq_num, pkt->water_level_pct, pkt->flow_rate_lpm,
                pkt->tds_ppm, pkt->temperature_c, pkt->battery_pct);

  // Stream telemetry to Cloud MQTT
  mqttMgr.publishSensorData(
    String(pkt->sub_node_id),
    pkt->seq_num,
    pkt->water_level_pct,
    pkt->water_level_cm,
    pkt->flow_rate_lpm,
    pkt->total_water_liters,
    pkt->tds_ppm,
    pkt->temperature_c,
    pkt->battery_voltage,
    pkt->battery_pct
  );
}

void EspNowManager::handlePairingRequest(const uint8_t *senderMac, const EspNowPairingRequest *pkt) {
  Serial.printf("[ESP-NOW] Pairing request from node '%s' on channel %d\n", pkt->sub_node_id, pkt->requested_channel);

  // Register peer in ESP-NOW table
  esp_now_peer_info_t peerInfo;
  memset(&peerInfo, 0, sizeof(peerInfo));
  memcpy(peerInfo.peer_addr, senderMac, 6);
  peerInfo.channel = wifiMgr.getChannel();
  peerInfo.encrypt = false;

  if (!esp_now_is_peer_exist(senderMac)) {
    esp_now_add_peer(&peerInfo);
  }

  // Send Pairing Response
  EspNowPairingResponse resp;
  resp.packet_type = PKT_PAIRING_RESPONSE;
  resp.protocol_version = 0x01;
  strncpy(resp.gateway_id, wifiMgr.getDeviceId().c_str(), sizeof(resp.gateway_id) - 1);
  resp.locked_channel = wifiMgr.getChannel();
  resp.telemetry_interval = 150; // Ultra-fast 150ms stream (< 300ms)
  resp.crc16 = calculateCRC16((const uint8_t*)&resp, sizeof(EspNowPairingResponse) - sizeof(uint16_t));

  esp_now_send(senderMac, (uint8_t*)&resp, sizeof(resp));
  Serial.printf("[ESP-NOW] Sent pairing response to node. Locked on channel %d\n", resp.locked_channel);
}
