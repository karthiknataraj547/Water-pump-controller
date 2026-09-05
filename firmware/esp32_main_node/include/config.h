#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// ==========================================
// HARDWARE PIN DEFINITIONS (ESP32 Gateway)
// ==========================================
#define PIN_RELAY_PUMP         23   // Relay control for main pump motor (Active HIGH)
#define PIN_EMERGENCY_STOP     18   // Hardware emergency cutoff switch (Active LOW)
#define PIN_MANUAL_BUTTON      19   // Manual toggle push button (Active LOW)
#define PIN_LED_NETWORK        2    // Blue network status LED
#define PIN_LED_PUMP           4    // Green pump running indicator LED
#define PIN_BUZZER             5    // Alarm/Alert Buzzer output

// ==========================================
// SYSTEM & TIMING CONFIGURATIONS
// ==========================================
#define FIRMWARE_VERSION       "2.0.9"
#define DEFAULT_DEVICE_PREFIX  "esp32_pump_"
#define BLE_DEVICE_PREFIX      "PumpController-"

#define DEFAULT_MQTT_PORT      1883
#define DEFAULT_MQTT_BROKER    "broker.emqx.io"  // Standard centralized EMQX Cloud MQTT broker

#define SENSOR_TIMEOUT_MS      2000   // 2s timeout for 150ms sub-node streaming (fast offline detection)
#define STATUS_REPORT_INTERVAL 1000   // 1000ms (1s) periodic MQTT status report (fast heartbeat)
#define MQTT_LOOP_INTERVAL_MS  10     // 10ms FreeRTOS MQTT loop for sub-100ms ping-pong response
#define PING_TIMEOUT_MS        3000   // 3s hardware ping response timeout
#define DRY_RUN_TIMEOUT_SEC    60     // 60s of pump ON with 0 flow = dry run trip

#define NVS_NAMESPACE          "pump_config"

#endif // CONFIG_H
