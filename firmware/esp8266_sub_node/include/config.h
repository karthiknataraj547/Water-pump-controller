#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// ==========================================
// HARDWARE PIN DEFINITIONS (ESP8266 Node)
// ==========================================
#define PIN_ULTRASONIC_TRIG    5    // D1 (GPIO5)
#define PIN_ULTRASONIC_ECHO    4    // D2 (GPIO4)
#define PIN_FLOW_SENSOR        14   // D5 (GPIO14) - Hardware Interrupt
#define PIN_ONEWIRE_TEMP       12   // D6 (GPIO12) - DS18B20 Data Bus
#define PIN_ADC_INPUT          A0   // A0 - Analog TDS Probe or Battery Voltage
#define PIN_PAIR_BUTTON        0    // D3 (GPIO0) - Pairing & Calibration Button
#define PIN_LED_STATUS         2    // D4 (GPIO2 / On-board LED)

// ==========================================
// TANK GEOMETRY & SENSOR CALIBRATION
// ==========================================
#define TANK_HEIGHT_CM         200.0f  // Total height from bottom to sensor
#define TANK_MIN_DISTANCE_CM   20.0f   // Distance from sensor when 100% full (blind zone)
#define FLOW_CALIBRATION_FACTOR 7.5f   // Pulses per second per L/min (YF-S201)

#define DEFAULT_NODE_ID        "tank_node_001"
#define TELEMETRY_INTERVAL_MS  3000    // Send telemetry packet every 3 seconds

#endif // CONFIG_H
