# Enterprise IoT Water Pump Monitoring & Control Platform

[![Download Android APK](https://img.shields.io/badge/Download-Android%20APK%20(v2.0)-00C853?style=for-the-badge&logo=android&logoColor=white)](releases/HydroPulse_WaterPumpController.apk)
[![Flutter](https://img.shields.io/badge/Flutter-3.19+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-18+-339933?logo=node.js&logoColor=white)](https://nodejs.org)
[![ESP32](https://img.shields.io/badge/ESP32-FreeRTOS-E7352C?logo=espressif&logoColor=white)](https://www.espressif.com)
[![ESP8266](https://img.shields.io/badge/ESP8266-ESP--NOW-E7352C?logo=espressif&logoColor=white)](https://www.espressif.com)
[![MQTT](https://img.shields.io/badge/MQTT-Mosquitto-660066?logo=eclipsemosquitto&logoColor=white)](https://mosquitto.org)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com)

A complete, production-grade IoT water pump monitoring and control ecosystem designed for agricultural, residential, and commercial water automation.

---

## 📱 Mobile App Download & Installation

### Option 1: Direct APK Download
You can directly download and install the Android Application on your mobile phone:
* **[📥 Download HydroPulse Android APK (v2.0.0)](releases/HydroPulse_WaterPumpController.apk)**
* File size: ~55 MB (Production Release with ARM64 / ARMv7 support)

### 📲 How to Install on Android:
1. Download the `.apk` file directly on your Android device (or transfer it from your PC).
2. Tap on the downloaded file **`HydroPulse_WaterPumpController.apk`**.
3. If prompted with *"Install unknown apps"*, tap **Settings** and toggle **Allow from this source**.
4. Tap **Install** and launch the **HydroPulse** app.
5. Grant Bluetooth and Location permissions when requested for the BLE Gateway Provisioning Wizard.

---

## 🌟 System Architecture

```text
 ┌─────────────────────────────────────────────────────────────┐
 │                FLUTTER MOBILE APP (Android & iOS)           │
 │   • Animated Wave Tank  • Real-Time Stopwatch  • BLE Wizard │
 └─────────────────────────────┬───────────────────────────────┘
                               │ MQTT & REST API
                               ▼
 ┌─────────────────────────────────────────────────────────────┐
 │                     CLOUD BACKEND (Docker)                  │
 │   • Node.js/TypeScript  • Mosquitto MQTT  • Postgres  • Redis│
 └─────────────────────────────┬───────────────────────────────┘
                               │ MQTT (TLS/TCP)
                               ▼
 ┌─────────────────────────────────────────────────────────────┐
 │                 ESP32 MAIN NODE / GATEWAY                   │
 │   • Wi-Fi + BLE  • Relay Control  • Local Safety Engine     │
 └─────────────────────────────┬───────────────────────────────┘
                               │ ESP-NOW (2.4 GHz)
                               ▼
 ┌─────────────────────────────────────────────────────────────┐
 │               ESP8266 SUB NODE / TANK SENSORS               │
 │   • Ultrasonic Level  • Pulse Flow  • Analog TDS  • DS18B20 │
 └─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Key Features

* **Real-Time Interactive Dashboard**: Custom animated fluid wave visualizer for water level %, live motor RPM/status, flow rate (L/min), cumulative volume, water purity (TDS ppm), and temperature.
* **BLE Device Provisioning**: Native Bluetooth Low Energy onboarding wizard that scans, pairs, and securely sends Wi-Fi credentials to new ESP32 Gateways.
* **Dual-Layer Automation**: Cloud-managed visual IF-THEN rules synchronized to the ESP32 Gateway so local safety automation operates 100% autonomously during internet outages.
* **Hardware Fail-Safes**: Dry run protection, pipe burst detection, maximum continuous run cutoff, and anti-cycling relay debounce.
* **Analytics & Historical Charts**: Interactive breakdown of daily, weekly, and monthly pump runtime, electricity consumption, and water pumped.
* **Full Stack & Dockerized**: Complete backend API, PostgreSQL schema with Prisma, Redis state cache, Mosquitto MQTT broker, firmware codebases, and simulation tools.

---

## 📂 Project Structure

- `backend/`: TypeScript REST API, WebSocket/MQTT ingestion service, Prisma ORM schema & migrations.
- `firmware/esp32_main_node/`: FreeRTOS C++ firmware for the Gateway, BLE provisioning, MQTT client, Relay safety controller, and ESP-NOW master.
- `firmware/esp8266_sub_node/`: ESP8266 firmware reading Ultrasonic, Flow, TDS, and DS18B20 sensors, transmitting CRC16 binary packets over ESP-NOW.
- `mobile_app/`: Flutter application for Android and iOS using Riverpod, GoRouter, and custom UI components.
- `tools/`: Hardware simulators and test harnesses for end-to-end integration verification without physical boards.
- `docs/`: Comprehensive technical documentation.

---

## 🛠️ Quick Start

### 1. Start Backend & MQTT Infrastructure
```bash
docker compose up -d --build
```

### 2. Run MQTT Hardware Simulator
```bash
cd tools
pip install paho-mqtt
python mqtt_simulator.py
```

### 3. Launch Flutter Mobile App
```bash
cd mobile_app
flutter pub get
flutter run
```

---

## 📖 Documentation Index
- [Architecture Details](file:///d:/water%20pump/docs/ARCHITECTURE.md)
- [REST API Reference](file:///d:/water%20pump/docs/API_DOCUMENTATION.md)
- [MQTT Protocol Guide](file:///d:/water%20pump/docs/MQTT_PROTOCOL.md)
- [BLE Provisioning Specification](file:///d:/water%20pump/docs/BLE_PROVISIONING.md)
- [ESP-NOW Protocol Specification](file:///d:/water%20pump/docs/ESP_NOW_PROTOCOL.md)
- [Hardware Wiring & Pinouts](file:///d:/water%20pump/docs/HARDWARE_SETUP.md)
- [Deployment Guide](file:///d:/water%20pump/docs/DEPLOYMENT.md)
- [Security Model](file:///d:/water%20pump/docs/SECURITY.md)
