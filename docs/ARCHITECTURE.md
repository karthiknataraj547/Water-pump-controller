# IoT Water Pump Monitoring and Control System: Architecture Specification

## 1. System Overview

The IoT Water Pump Monitoring and Control System is a distributed, multi-tier industrial-grade IoT platform designed for high reliability, autonomous safety fail-safes, and real-time remote monitoring and control.

```text
 ┌──────────────────────────────────────────────────────────────────┐
 │                    FLUTTER MOBILE APP (Android/iOS)              │
 │ • Real-Time Dashboards  • Manual/Auto Control  • BLE Provisioning│
 └────────────────────────────┬─────────────────────────▲───────────┘
                              │                         │
                   BLE (GATT Provisioning)         MQTT / HTTPS
                              │                         │
                              ▼                         ▼
 ┌──────────────────────────────────────────────────────────────────┐
 │                        CLOUD INFRASTRUCTURE                      │
 │ • Mosquitto Broker  • Node.js/TypeScript API  • PostgreSQL/Redis │
 └────────────────────────────▲─────────────────────────────────────┘
                              │
                         MQTT (TLS/TCP)
                              │
                              ▼
 ┌──────────────────────────────────────────────────────────────────┐
 │                    ESP32 MAIN NODE / GATEWAY                     │
 │ • Wi-Fi STA  • BLE GATT  • MQTT Client  • ESP-NOW Master         │
 │ • Relay Driver  • Autonomous Local Safety Controller             │
 └────────────────────────────▲─────────────────────────────────────┘
                              │
                         ESP-NOW (2.4 GHz)
                              │
                              ▼
 ┌──────────────────────────────────────────────────────────────────┐
 │                    ESP8266 SUB NODE / SENSOR NODE                │
 │ • Ultrasonic Level  • Flow Pulse  • Analog TDS  • DS18B20 Temp   │
 └──────────────────────────────────────────────────────────────────┘
```

---

## 2. Key Subsystems & Layers

### 2.1 Sensor Sub Node (ESP8266)
- **Role**: Located directly at the water reservoir or overhead tank.
- **Hardware Peripherals**:
  - Ultrasonic sensor (HC-SR04 / JSN-SR04T waterproof) or hydrostatic pressure sensor.
  - Hall-effect pulse flow sensor (YF-S201).
  - TDS water quality probe with analog conditioning.
  - Dallas DS18B20 digital temperature probe.
- **Wireless Link**: Transmits low-overhead binary packets to the ESP32 Gateway via ESP-NOW. Never connects to the Internet or Wi-Fi AP directly, conserving power and operating even when Wi-Fi is offline.

### 2.2 Main Node & Gateway (ESP32)
- **Role**: Located near the motor starter panel / pump relay.
- **Dual-Core Execution**:
  - **Core 0**: Networking subsystem (Wi-Fi STA manager, BLE provisioning server, MQTT client, ESP-NOW master packet router).
  - **Core 1**: Safety, pump relay actuation, anti-cycling debounce, sensor health watchdog, and local autonomous rules engine.
- **Autonomous Local Control**: If Internet or MQTT connectivity is lost, Core 1 continues reading ESP-NOW sensor packets and enforces local safety rules (e.g., auto-start at < 30%, auto-stop at > 90%, max run limit of 30 minutes, dry run shutoff).

### 2.3 Cloud & Backend Services
- **MQTT Broker**: Eclipse Mosquitto handling low-latency telemetry streaming and downlink command dispatching.
- **Backend API**: Modular TypeScript / Node.js service using Prisma ORM for relational queries, Redis for real-time device state caching, and JWT auth with token rotation.
- **Telemetry Ingestion Worker**: Subscribes to device telemetry, writes time-series metrics, evaluates alerts/anomalies, and publishes command execution confirmations with UUID tracking.

### 2.4 Flutter Mobile Application
- **State Management**: Riverpod for reactive dependency injection and clean state separation.
- **Navigation**: GoRouter with authentication guards and deep links.
- **Provisioning**: Native Bluetooth Low Energy (BLE) scanning, RSSI signal estimation, secure credential handshake, and progress tracking.
- **Real-Time UI**: Live animated water wave tank visualizer, interactive gauges, real-time pump stopwatch, and analytics charts.

---

## 3. Communication Protocols Summary

| Protocol | Source $\to$ Destination | Purpose |
| :--- | :--- | :--- |
| **BLE (GATT)** | Mobile App $\to$ ESP32 | First-time Wi-Fi setup, device claim token, initial configuration |
| **ESP-NOW** | ESP8266 $\to$ ESP32 | Sub-millisecond binary telemetry (Level, Flow, TDS, Temp, Battery) |
| **MQTT** | ESP32 $\longleftrightarrow$ Cloud Broker | Bidirectional telemetry, status heartbeats, commands, and ACK |
| **HTTPS / REST** | Mobile App $\longleftrightarrow$ Cloud API | User auth, historical data, device management, rule configuration |
| **WebSockets** | Cloud Broker $\longleftrightarrow$ Mobile App | Real-time live dashboard sync |

---

## 4. Hardware Fail-Safe Principles

1. **Hardware Interlocks**: Relay output features a normally-open circuit with hardware pull-down resistors to prevent relay chatter during MCU boot or reset.
2. **Watchdog Timers**: Both ESP32 and ESP8266 enable hardware Task Watchdog Timers (TWDT) to automatically recover from lockups or corrupted heap states.
3. **Sensor Stale Data Protection**: If the ESP32 does not receive an ESP-NOW packet from the ESP8266 for more than 45 seconds, it flags `SENSOR_OFFLINE`, aborts automated pump runs, and issues a critical alert.
4. **Max Continuous Run Timer**: Hard limits enforce that the pump cannot run for longer than a configurable maximum runtime (e.g. 45 minutes) regardless of cloud commands, preventing burnouts from pipe bursts.
