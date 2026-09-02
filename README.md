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

```text
├── frontend/                     # Flutter Mobile App (Android & iOS)
│   ├── lib/core/update/          # In-App Automatic Update Checker Engine
│   ├── lib/features/dashboard/   # 3D Water System & Live Motor Dashboard
│   ├── lib/features/provisioning/# BLE Device Onboarding Wizard
│   └── lib/shared/widgets/       # 3D Tank Shaders & Custom Controls
├── backend/                      # Cloud Backend & Ingestion Services
│   ├── src/modules/mqtt/         # Mosquitto MQTT Handler & Presence Sweeper
│   ├── src/modules/devices/      # Device Registry & Telemetry APIs
│   └── prisma/schema.prisma      # PostgreSQL Schema with Prisma ORM
├── website/                      # Product Showcase & Web Simulator
│   ├── index.html                # Responsive Landing Page & APK Download
│   ├── style.css                 # Glassmorphic Cyber-Hydro Design System
│   └── app.js                    # Interactive 3D Tank Simulator
├── firmware/
│   ├── esp32_main_node/          # PlatformIO Dual-Core FreeRTOS Main Gateway
│   ├── esp8266_sub_node/         # ESP8266 Sub Node (Ultrasonic, Flow, TDS)
│   └── arduino_ide/              # Arduino IDE Single-File Gateway Sketch
├── releases/                     # Production Mobile Application APK Releases
│   └── HydroPulse_WaterPumpController.apk
├── version.json                  # In-App Update Manifest for OTA Checks
├── tools/                        # Python MQTT Telemetry & Hardware Simulators
└── docs/                         # Specifications, Wiring & Architecture Guides
```

---

## 🛠️ Quick Start

### 1. Launch Showcase Website Locally
Open `website/index.html` directly in your browser or serve via:
```bash
npx serve website
```

### 2. Start Cloud Backend & Mosquitto MQTT Broker
```bash
docker compose up -d --build
```

### 3. Launch Flutter Mobile Application
```bash
cd frontend
flutter pub get
flutter run
```

### 4. Run Hardware MQTT Simulation
```bash
cd tools
pip install paho-mqtt
python mqtt_simulator.py
```

---

## 📖 Documentation Index
- [Architecture Details](docs/ARCHITECTURE.md)
- [REST API Reference](docs/API_DOCUMENTATION.md)
- [MQTT Protocol Guide](docs/MQTT_PROTOCOL.md)
- [BLE Provisioning Specification](docs/BLE_PROVISIONING.md)
- [ESP-NOW Protocol Specification](docs/ESP_NOW_PROTOCOL.md)
- [Hardware Wiring & Pinouts](docs/HARDWARE_SETUP.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Security Model](docs/SECURITY.md)
