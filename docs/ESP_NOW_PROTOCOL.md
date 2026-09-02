# ESP-NOW Communication Protocol Specification

This document defines the physical framing, binary packet structure, channel synchronization, and retry mechanisms between the ESP8266 Sub Node (Tank Sensor) and the ESP32 Main Node (Gateway).

---

## 1. Physical & Radio Constraints

* **Frequency Band**: 2.4 GHz ISM band.
* **Wi-Fi Channel Dependency**:
  - The ESP32 Gateway operates in dual mode (`WIFI_AP_STA`). When connected to a home router on Channel $N$ (e.g. Channel 6), the ESP32's hardware radio is fixed on Channel $N$.
  - Therefore, the ESP8266 Sub Node must transmit on Channel $N$.
  - **Dynamic Channel Locking**: The ESP8266 implements a channel scanning routine at startup. It iterates through Channels 1 to 13, transmitting a pairing handshake packet until it receives an ESP-NOW ACK from the ESP32 on the active channel. It then locks onto that channel.

---

## 2. Binary Packet Structure

All transmissions use packed binary structures with fixed alignment and a standard 16-bit CRC checksum (CRC-16-CCITT) to guarantee data integrity across RF interference.

### 2.1 Packet Type Identifier
```c
typedef enum {
  PKT_PAIRING_REQUEST  = 0x01,
  PKT_PAIRING_RESPONSE = 0x02,
  PKT_SENSOR_TELEMETRY = 0x03,
  PKT_CONFIG_UPDATE    = 0x04,
  PKT_ACK              = 0x05
} EspNowPacketType;
```

---

### 2.2 Sensor Telemetry Packet (`PKT_SENSOR_TELEMETRY`)
Total Size: **44 bytes**

```c
typedef struct __attribute__((packed)) {
  uint8_t  packet_type;        // 0x03 (PKT_SENSOR_TELEMETRY)
  uint8_t  protocol_version;   // 0x01
  char     sub_node_id[12];    // e.g. "tank_001\0"
  uint32_t seq_num;            // Monotonically increasing counter
  float    water_level_pct;    // 0.0 to 100.0 %
  float    water_level_cm;     // 0.0 to 500.0 cm
  float    flow_rate_lpm;      // 0.0 to 150.0 Liters/min
  float    total_water_liters; // Cumulative lifetime liters
  uint16_t tds_ppm;            // 0 to 2000 ppm
  float    temperature_c;      // -10.0 to 80.0 °C
  float    battery_voltage;    // 2.8V to 4.35V
  uint8_t  battery_pct;        // 0 to 100%
  uint8_t  sensor_flags;       // Bitfield: [0: Level, 1: Flow, 2: TDS, 3: Temp]
  uint16_t crc16;              // CRC-16-CCITT across previous 42 bytes
} EspNowSensorPacket;
```

---

### 2.3 Pairing Handshake Request (`PKT_PAIRING_REQUEST`)
```c
typedef struct __attribute__((packed)) {
  uint8_t packet_type;         // 0x01
  uint8_t protocol_version;    // 0x01
  char    sub_node_id[12];     // "tank_001"
  uint8_t mac_address[6];      // ESP8266 MAC Address
  uint8_t requested_channel;   // Channel currently tested
  uint16_t crc16;
} EspNowPairingRequest;
```

---

### 2.4 Pairing Handshake Response (`PKT_PAIRING_RESPONSE`)
```c
typedef struct __attribute__((packed)) {
  uint8_t packet_type;         // 0x02
  uint8_t protocol_version;    // 0x01
  char    gateway_id[16];      // "esp32_pump_94B97E"
  uint8_t locked_channel;      // Confirmed Gateway Channel
  uint16_t telemetry_interval; // Reporting interval in milliseconds (e.g. 5000)
  uint16_t crc16;
} EspNowPairingResponse;
```

---

## 3. Reliability & Fault Recovery

1. **Sequence Number Tracking**: The ESP32 Gateway tracks `last_seq_num` per node ID to detect lost packets and calculate RF Packet Delivery Ratio (PDR).
2. **Offline Detection Watchdog**: If no valid telemetry packet is decoded for 45 seconds, the Gateway flags the Sub Node as `OFFLINE`, activates an LED fault code, and triggers an autonomous pump safety interlock if auto-mode is active.
3. **CRC Validation**: Any packet with a CRC mismatch is silently discarded to protect local automation routines from erratic sensor glitches.
