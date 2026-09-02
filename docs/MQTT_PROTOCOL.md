# MQTT Protocol Specification

This document details the MQTT topic hierarchy, JSON schemas, QoS levels, and message flows between the ESP32 Gateway, Cloud Backend, and Flutter Mobile Application.

---

## 1. Topic Hierarchy Overview

All topics follow the structured pattern:
```text
pump/{userId}/{deviceId}/{action}
```

Where:
- `{userId}`: Unique identifier of the device owner (e.g., `usr_98a7f1c4`).
- `{deviceId}`: Unique identifier of the ESP32 Main Node (e.g., `esp32_pump_94B97E`).
- `{action}`: Sub-topic category (`status`, `sensor`, `command`, `ack`, `config`, `alert`).

---

## 2. Topic Details & JSON Payloads

### 2.1 Gateway Status Telemetry
* **Topic**: `pump/{userId}/{deviceId}/status`
* **Direction**: ESP32 $\to$ Cloud
* **QoS**: 1
* **Retain**: `true`
* **Frequency**: Every 30 seconds, or immediately upon state transition.
* **Payload Example**:
```json
{
  "device_id": "esp32_pump_94B97E",
  "user_id": "usr_98a7f1c4",
  "firmware_version": "1.0.0",
  "uptime_seconds": 84210,
  "wifi_rssi": -62,
  "state": "CONNECTED",
  "pump_state": "OFF",
  "mode": "AUTO",
  "running_duration_seconds": 0,
  "last_command_id": "cmd_a81f349d",
  "safety_status": "NORMAL",
  "sub_node_connected": true,
  "sub_node_last_seen_seconds": 3,
  "free_heap_bytes": 174200,
  "timestamp": 1724938200
}
```

---

### 2.2 Tank Sensor Telemetry
* **Topic**: `pump/{userId}/{deviceId}/sensor`
* **Direction**: ESP32 $\to$ Cloud (Aggregated from ESP8266 ESP-NOW)
* **QoS**: 1
* **Retain**: `false`
* **Frequency**: Every 3 to 10 seconds (or immediately on significant delta).
* **Payload Example**:
```json
{
  "device_id": "esp32_pump_94B97E",
  "sub_node_id": "tank_node_001",
  "seq_num": 1402,
  "water_level_pct": 76.5,
  "water_level_cm": 153.0,
  "flow_rate_lpm": 18.2,
  "total_water_liters": 3840.5,
  "tds_ppm": 165,
  "temperature_c": 27.4,
  "battery_voltage": 4.05,
  "battery_pct": 92,
  "sensor_flags": {
    "level_sensor_ok": true,
    "flow_sensor_ok": true,
    "tds_sensor_ok": true,
    "temp_sensor_ok": true
  },
  "timestamp": 1724938205
}
```

---

### 2.3 Downlink Commands
* **Topic**: `pump/{userId}/{deviceId}/command`
* **Direction**: Mobile App / Cloud $\to$ ESP32
* **QoS**: 1
* **Retain**: `false`
* **Payload Example**:
```json
{
  "command_id": "cmd_b52d9a10-21a4-4f40-8b61",
  "command": "PUMP_ON",
  "parameters": {
    "override_safety": false,
    "max_duration_minutes": 30
  },
  "issued_by": "usr_98a7f1c4",
  "timestamp": 1724938210
}
```

Supported Commands:
- `PUMP_ON`: Start pump motor.
- `PUMP_OFF`: Stop pump motor.
- `EMERGENCY_STOP`: Instant hardware relay cutoff and safety lockout.
- `SET_MODE`: Switch between `MANUAL` and `AUTO`.
- `REBOOT`: Gracefully reboot ESP32 Gateway.
- `CLEAR_SAFETY_LOCK`: Reset safety lockouts after inspection.

---

### 2.4 Command Acknowledgement (ACK)
* **Topic**: `pump/{userId}/{deviceId}/ack`
* **Direction**: ESP32 $\to$ Cloud
* **QoS**: 1
* **Payload Example**:
```json
{
  "command_id": "cmd_b52d9a10-21a4-4f40-8b61",
  "device_id": "esp32_pump_94B97E",
  "status": "SUCCESS",
  "message": "Pump relay closed successfully. Current state: ON.",
  "execution_time_ms": 42,
  "timestamp": 1724938211
}
```

---

### 2.5 Configuration Synchronization
* **Topic**: `pump/{userId}/{deviceId}/config`
* **Direction**: Bi-directional (Cloud $\longleftrightarrow$ ESP32)
* **QoS**: 1
* **Retain**: `true`
* **Payload Example**:
```json
{
  "device_id": "esp32_pump_94B97E",
  "auto_start_level_pct": 30.0,
  "auto_stop_level_pct": 90.0,
  "max_continuous_run_minutes": 45,
  "dry_run_timeout_seconds": 60,
  "min_flow_rate_lpm": 2.0,
  "tank_height_cm": 200.0,
  "tank_capacity_liters": 5000,
  "telemetry_interval_seconds": 5,
  "timestamp": 1724938215
}
```

---

### 2.6 Emergency Alerts
* **Topic**: `pump/{userId}/{deviceId}/alert`
* **Direction**: ESP32 $\to$ Cloud
* **QoS**: 1
* **Payload Example**:
```json
{
  "alert_id": "alt_71e04a",
  "device_id": "esp32_pump_94B97E",
  "severity": "CRITICAL",
  "type": "DRY_RUN_DETECTED",
  "description": "Pump running for 60s but flow sensor reads 0.0 LPM. Motor shut down automatically to prevent burn-out.",
  "timestamp": 1724938220
}
```
