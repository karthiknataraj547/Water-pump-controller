# HydroPulse Firmware Guide: ESP32 Gateway & ESP8266 Sensor Node

This directory contains the production-grade firmware for both hardware nodes in the HydroPulse IoT Water Pump System.

---

## 📂 Firmware File Locations

### Option A: Arduino IDE Sketches (Single File, Ready to Upload)
* **ESP32 Main Node / Gateway**: [`firmware/arduino_ide/ESP32_Main_Gateway/ESP32_Main_Gateway.ino`](file:///d:/water%20pump/firmware/arduino_ide/ESP32_Main_Gateway/ESP32_Main_Gateway.ino)
* **ESP8266 Sub Node / Tank Sensor**: [`firmware/arduino_ide/ESP8266_Tank_Sensor/ESP8266_Tank_Sensor.ino`](file:///d:/water%20pump/firmware/arduino_ide/ESP8266_Tank_Sensor/ESP8266_Tank_Sensor.ino)

### Option B: PlatformIO Projects (Modular Dual-Core FreeRTOS)
* **ESP32 Main Node**: [`firmware/esp32_main_node/`](file:///d:/water%20pump/firmware/esp32_main_node/)
* **ESP8266 Sub Node**: [`firmware/esp8266_sub_node/`](file:///d:/water%20pump/firmware/esp8266_sub_node/)

---

## ⚡ 1. ESP32 Main Node / Gateway Setup

### Required Libraries (Install via Arduino IDE Library Manager)
1. **`NimBLE-Arduino`** by `h2zero` (v1.4.1 or higher)
2. **`PubSubClient`** by `Nick O'Leary` (v2.8 or higher)
3. **`ArduinoJson`** by `Benoit Blanchon` (v7.0.4 or higher)

### ESP32 Pin Connections
| Component | ESP32 GPIO | Description |
| :--- | :--- | :--- |
| **Factory Hard Reset** | `GPIO 0` | **Hold for 3 seconds** (Built-in BOOT button) to wipe NVS & reset BLE pairing |
| **Pump Relay Control** | `GPIO 23` | Active HIGH digital output to Relay module |
| **Emergency Cutoff Switch** | `GPIO 18` | Active LOW with internal pull-up |
| **Manual Push Button** | `GPIO 19` | Active LOW with internal pull-up |
| **Blue Network LED** | `GPIO 2` | Flashes during BLE/Wi-Fi connection, solid when connected |
| **Green Pump Running LED** | `GPIO 4` | Solid ON when pump relay is active |
| **Buzzer** | `GPIO 5` | Audible alarm for emergency, dry-run, or reset confirmation |

### Hard Reset Functionality:
* **How to Trigger**: Press and hold the **BOOT button (GPIO 0)** on your ESP32 board for **3 seconds**.
* **What Happens**:
  1. The ESP32 beeps the buzzer and rapidly flashes the LEDs.
  2. Wipes all stored Wi-Fi credentials from Non-Volatile Flash NVS (`Preferences`).
  3. Reboots the ESP32 directly into **BLE Provisioning Mode** so you can immediately pair it with a new Wi-Fi network from your phone!
1. When powered ON, the ESP32 starts **Bluetooth Low Energy (BLE)** advertising as **`PumpController-XXXXXX`**.
2. When you open the Flutter Mobile App, go to **Add New Pump Gateway** (`+` button), it discovers your ESP32.
3. You enter your Wi-Fi SSID and Password and tap **Transmit Credentials & Pair**.
4. The mobile app writes the SSID and Password directly into the ESP32's BLE GATT characteristics (`0x19B10001` and `0x19B10002`).
5. The ESP32 saves the credentials to Non-Volatile Flash (`Preferences`), connects to your Wi-Fi router, and notifies the mobile app: `{"state": "SUCCESS", "ip_address": "192.168.1.xxx"}`.
6. The ESP32 connects to the MQTT cloud broker and receives ESP-NOW sensor packets from the ESP8266 Sub Node.

---

## 🌊 2. ESP8266 Sub Node / Sensor Node Setup

### Required Libraries (Install via Arduino IDE Library Manager)
1. **`OneWire`** by `Paul Stoffregen` (v2.3.8 or higher)
2. **`DallasTemperature`** by `Miles Burton` (v3.11.0 or higher)

### ESP8266 (NodeMCU / Wemos D1 Mini) Pin Connections
| Sensor / Component | ESP8266 Pin | GPIO | Description |
| :--- | :--- | :--- | :--- |
| **Ultrasonic TRIG** | `D1` | `GPIO 5` | Trigger pin for HC-SR04 / JSN-SR04T |
| **Ultrasonic ECHO** | `D2` | `GPIO 4` | Echo pin for HC-SR04 |
| **YF-S201 Flow Sensor** | `D5` | `GPIO 14` | Pulse output with hardware interrupt |
| **DS18B20 Temp Probe** | `D6` | `GPIO 12` | OneWire data bus (with 4.7kΩ pull-up to 3.3V) |
| **Analog TDS Sensor** | `A0` | `ADC0` | 0 - 3.3V analog input |
| **Status LED** | `D4` | `GPIO 2` | Blinks on every telemetry transmission |

### How It Works:
1. Reads tank water level percentage, flow rate (L/min), temperature (°C), and TDS purity every 3 seconds.
2. Encapsulates sensor metrics into a binary packet with a 16-bit CRC checksum.
3. Transmits the packet directly to the ESP32 Gateway via **ESP-NOW** (no Wi-Fi router or internet needed between the two nodes).

---

## 🚀 3. How to Flash with Arduino IDE

1. **Install Board Packages in Arduino IDE**:
   - For ESP32: Add URL `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json` in **Preferences $\to$ Additional Board Manager URLs**.
   - For ESP8266: Add URL `https://arduino.esp8266.com/stable/package_esp8266com_index.json`.
2. **Open the Sketch**:
   - Open [`ESP32_Main_Gateway.ino`](file:///d:/water%20pump/firmware/arduino_ide/ESP32_Main_Gateway/ESP32_Main_Gateway.ino) for ESP32.
   - Open [`ESP8266_Tank_Sensor.ino`](file:///d:/water%20pump/firmware/arduino_ide/ESP8266_Tank_Sensor/ESP8266_Tank_Sensor.ino) for ESP8266.
3. **Select Board & Settings**:
   - **ESP32 Main Node**:
     - Board: **Tools $\to$ Board $\to$ ESP32 Arduino $\to$ ESP32 Dev Module**
     - Partition Scheme: **Tools $\to$ Partition Scheme $\to$ "Huge APP (3MB No OTA/1MB SPIFFS)"** *(Essential for BLE + Wi-Fi)*
     - Upload Speed: **921600** (or 115200)
   - **ESP8266 Sub Node**:
     - Board: **Tools $\to$ Board $\to$ ESP8266 Boards $\to$ NodeMCU 1.0 (ESP-12E Module)**
     - Flash Size: **4MB (FS:2MB OTA:~1019KB)**
4. Click **Upload** (➡️).
5. Open the **Serial Monitor** at **115200 baud** to see real-time debug output.
