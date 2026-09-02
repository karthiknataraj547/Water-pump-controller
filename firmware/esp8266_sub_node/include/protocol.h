#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <Arduino.h>

enum EspNowPacketType : uint8_t {
  PKT_PAIRING_REQUEST  = 0x01,
  PKT_PAIRING_RESPONSE = 0x02,
  PKT_SENSOR_TELEMETRY = 0x03,
  PKT_CONFIG_UPDATE    = 0x04,
  PKT_ACK              = 0x05
};

typedef struct __attribute__((packed)) {
  uint8_t  packet_type;        // 0x03
  uint8_t  protocol_version;   // 0x01
  char     sub_node_id[12];    // "tank_node_001\0"
  uint32_t seq_num;            // Monotonic sequence counter
  float    water_level_pct;    // 0.0 - 100.0 %
  float    water_level_cm;     // 0.0 - 500.0 cm
  float    flow_rate_lpm;      // Liters per minute
  float    total_water_liters; // Cumulative lifetime liters
  uint16_t tds_ppm;            // Total Dissolved Solids
  float    temperature_c;      // Celsius
  float    battery_voltage;    // 3.0V - 4.2V
  uint8_t  battery_pct;        // 0 - 100%
  uint8_t  sensor_flags;       // Bit 0: Level OK, 1: Flow OK, 2: TDS OK, 3: Temp OK
  uint16_t crc16;              // CRC-16-CCITT across payload
} EspNowSensorPacket;

typedef struct __attribute__((packed)) {
  uint8_t  packet_type;        // 0x01
  uint8_t  protocol_version;   // 0x01
  char     sub_node_id[12];
  uint8_t  mac_address[6];
  uint8_t  requested_channel;
  uint16_t crc16;
} EspNowPairingRequest;

typedef struct __attribute__((packed)) {
  uint8_t  packet_type;        // 0x02
  uint8_t  protocol_version;   // 0x01
  char     gateway_id[16];
  uint8_t  locked_channel;
  uint16_t telemetry_interval;
  uint16_t crc16;
} EspNowPairingResponse;

inline uint16_t calculateCRC16(const uint8_t *data, size_t length) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < length; i++) {
    crc ^= (uint16_t)data[i] << 8;
    for (uint8_t j = 0; j < 8; j++) {
      if (crc & 0x8000) {
        crc = (crc << 1) ^ 0x1021;
      } else {
        crc = crc << 1;
      }
    }
  }
  return crc;
}

#endif // PROTOCOL_H
