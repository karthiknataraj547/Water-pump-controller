# Bluetooth Low Energy (BLE) Provisioning Protocol

This document describes the BLE GATT architecture, advertising packets, and handshake sequence for onboarding new ESP32 Gateways from the Flutter mobile application.

---

## 1. BLE Advertising Specification

* **Device Name Format**: `PumpController-XXXX` (where `XXXX` is the last 4 characters of the ESP32 MAC address in uppercase hexadecimal, e.g. `PumpController-94BE`).
* **Advertised Service UUID**: `19B10000-E8F2-537E-4F6C-D104768A1214`
* **Advertising Mode**: General Discoverable, Fast Advertising (intervals of 100ms) for the first 3 minutes after boot in setup mode.

---

## 2. GATT Service & Characteristics

### Primary Service UUID
`19B10000-E8F2-537E-4F6C-D104768A1214`

### Characteristics Table
| Characteristic | UUID | Properties | Purpose | Format |
| :--- | :--- | :--- | :--- | :--- |
| **WIFI_SSID** | `19B10001-E8F2-537E-4F6C-D104768A1214` | WRITE | Target Wi-Fi Network Name | UTF-8 String (max 32 bytes) |
| **WIFI_PASS** | `19B10002-E8F2-537E-4F6C-D104768A1214` | WRITE | Target Wi-Fi Password | UTF-8 String (max 64 bytes) |
| **AUTH_TOKEN** | `19B10003-E8F2-537E-4F6C-D104768A1214` | WRITE | Device Claim Token from Cloud | UUID/JWT String (max 128 bytes) |
| **PROV_STATUS** | `19B10004-E8F2-537E-4F6C-D104768A1214` | READ, NOTIFY | Real-time Provisioning Progress | JSON String |
| **DEVICE_INFO** | `19B10005-E8F2-537E-4F6C-D104768A1214` | READ | MAC, Firmware Version, Node ID | JSON String |

---

## 3. Provisioning Sequence Flow

```text
  Flutter App                                                ESP32 Gateway
       │                                                           │
       ├────────── Scan for "PumpController-XXXX" ────────────────►│
       │                                                           │
       ├────────── Establish BLE GATT Connection ─────────────────►│
       │                                                           │
       │◄───────── Read DEVICE_INFO (MAC, FW Version) ─────────────┤
       │                                                           │
       ├────────── Subscribe to PROV_STATUS Notifications ────────►│
       │                                                           │
       ├────────── Write WIFI_SSID ("MyHome_WiFi_2G") ────────────►│
       │                                                           │
       ├────────── Write WIFI_PASS ("Secr3tP@ssw0rd") ─────────────►│
       │                                                           │
       ├────────── Write AUTH_TOKEN ("tok_91a0c84f1b") ────────────►│
       │                                                           │
       │                                                           │ (ESP32 attempts Wi-Fi)
       │◄───────── PROV_STATUS: {"state":"CONNECTING_WIFI"} ───────┤
       │                                                           │ (Wi-Fi Connected! IP: 192.168.1.102)
       │◄───────── PROV_STATUS: {"state":"WIFI_CONNECTED"} ────────┤
       │                                                           │ (Connecting to MQTT broker)
       │◄───────── PROV_STATUS: {"state":"CONNECTING_MQTT"} ───────┤
       │                                                           │ (MQTT Connected & Claim verified)
       │◄───────── PROV_STATUS: {"state":"SUCCESS"} ───────────────┤
       │                                                           │
       ├────────── Disconnect BLE & Switch to MQTT Mode ──────────►│
```

---

## 4. Status Notification JSON Schema

```json
{
  "state": "CONNECTING_WIFI | WIFI_CONNECTED | CONNECTING_MQTT | SUCCESS | ERROR",
  "ip_address": "192.168.1.102",
  "mac_address": "24:6F:28:94:B9:7E",
  "device_id": "esp32_pump_94B97E",
  "error_code": null,
  "error_message": null
}
```

Error Codes:
- `ERR_WIFI_AUTH_FAILED`: Invalid SSID or Wi-Fi Password.
- `ERR_WIFI_NOT_FOUND`: Target SSID not found in 2.4 GHz spectrum.
- `ERR_MQTT_FAILED`: Unable to reach or authenticate with MQTT broker.
- `ERR_TOKEN_INVALID`: Claim token rejected by backend server.
