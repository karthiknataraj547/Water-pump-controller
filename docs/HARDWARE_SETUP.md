# Hardware Wiring & Setup Guide

This guide details the physical connections, pin mappings, power supply considerations, and sensor attachments for both the ESP32 Gateway and the ESP8266 Sub Node.

---

## 1. ESP32 Main Node (Gateway & Relay Controller)

### 1.1 Pinout Mapping

| Component | ESP32 Pin | Signal | Notes |
| :--- | :--- | :--- | :--- |
| **Pump Relay Module** | `GPIO 23` | Digital OUT | Connect to IN pin on Relay module (Active HIGH or LOW configurable) |
| **Emergency Stop Button** | `GPIO 18` | Digital IN | Internal Pull-Up, active LOW switch |
| **Status LED (Network)** | `GPIO 2` | Digital OUT | On-board LED or Blue LED (Blink = Connecting, Solid = Connected) |
| **Pump Status LED** | `GPIO 4` | Digital OUT | Green LED indicating active relay energization |
| **Manual Toggle Button** | `GPIO 19` | Digital IN | Internal Pull-Up, push button for manual on/off override |
| **Buzzer / Audio Alarm** | `GPIO 5` | Digital OUT | Beeps during emergency cutoff, dry run, or full tank alerts |

### 1.2 Power Supply Guidelines
- Supply: 5V DC (minimum 2.0A) via micro-USB or screw terminal to 5V/VIN pin.
- Use a dedicated optocoupler-isolated relay module to avoid high-voltage flyback or inductive spikes from the AC pump motor resetting the ESP32 MCU.
- Install an RC Snubber circuit across the relay contacts for AC inductive motor loads.

---

## 2. ESP8266 Sub Node (Tank Sensor Node)

### 2.1 Pinout Mapping

| Sensor | ESP8266 Pin | Signal | Notes |
| :--- | :--- | :--- | :--- |
| **Ultrasonic (HC-SR04/JSN)** | `D1 (GPIO 5)` | TRIG | Trigger pulse |
| **Ultrasonic (HC-SR04/JSN)** | `D2 (GPIO 4)` | ECHO | Echo return pulse (Use 1k/2k voltage divider if 5V sensor) |
| **Water Flow (YF-S201)** | `D5 (GPIO 14)` | PULSE | Hardware interrupt pin for pulse counting |
| **DS18B20 Temp Probe** | `D6 (GPIO 12)` | OneWire | Digital 1-Wire data bus with 4.7kΩ pull-up resistor to 3.3V |
| **Analog TDS Probe** | `A0 (ADC 0)` | Analog IN | 0.0V to 1.0V (or 0-3.3V with onboard divider) |
| **Battery Voltage Monitor** | `A0 (Switched)` | Analog IN | Via 100k/20k voltage divider to read Li-ion 3.7V - 4.2V |
| **Pairing / Calibration Btn**| `D3 (GPIO 0)` | Digital IN | Active LOW push button to force channel re-sync |

### 2.2 Sensor Installation Best Practices
1. **Ultrasonic Sensor**: Mount at the top center of the tank lid, pointed perpendicularly downward at the water surface, maintaining a minimum 20cm clearance (blind zone) from full capacity.
2. **Flow Sensor**: Mount horizontally in the pump outlet pipe, ensuring the arrow on the casing matches the flow direction.
3. **TDS Probe**: Immerse probe pins vertically in a mid-level chamber of the tank or inline pipe, avoiding air pockets.
4. **Waterproofing**: Enclose the ESP8266 and battery charging circuit in an IP65 rated junction box.
