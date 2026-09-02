#include <Arduino.h>
#include <esp_wifi.h>
#include "config.h"
#include "protocol.h"
#include "wifi_manager.h"
#include "ble_provisioning.h"
#include "mqtt_manager.h"
#include "espnow_manager.h"
#include "pump_controller.h"
#include "automation_engine.h"
#include "safety_manager.h"

// FreeRTOS Task Handles
TaskHandle_t TaskNetworkHandle = NULL;
TaskHandle_t TaskControlHandle = NULL;

unsigned long lastPeriodicReport = 0;

// Network Task running on Core 0 (Wi-Fi, MQTT, BLE)
void TaskNetwork(void *pvParameters) {
  Serial.printf("[TaskNetwork] Running on Core %d\n", xPortGetCoreID());
  for (;;) {
    wifiMgr.loop();
    mqttMgr.loop();

    // Periodic MQTT status telemetry report
    if (millis() - lastPeriodicReport > STATUS_REPORT_INTERVAL) {
      lastPeriodicReport = millis();
      mqttMgr.publishStatus(
        pumpCtrl.getStateString(),
        autoEngine.getModeString(),
        pumpCtrl.getRunningDurationSeconds(),
        safetyMgr.getSafetyStatus()
      );
    }

    vTaskDelay(pdMS_TO_TICKS(MQTT_LOOP_INTERVAL_MS));
  }
}

// Control & Safety Task running on Core 1 (Relay, Safety Interlocks, Automation)
void TaskControl(void *pvParameters) {
  Serial.printf("[TaskControl] Running on Core %d\n", xPortGetCoreID());
  for (;;) {
    espnowMgr.loop();
    pumpCtrl.loop();
    safetyMgr.loop();
    autoEngine.loop();

    vTaskDelay(pdMS_TO_TICKS(MQTT_LOOP_INTERVAL_MS));
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n=======================================================");
  Serial.println("  IoT Water Pump Controller & Gateway - ESP32 Node");
  Serial.printf("  Firmware Version: %s\n", FIRMWARE_VERSION);
  Serial.println("=======================================================\n");

  // 1. Initialize Hardware Pins & Controllers
  pumpCtrl.begin();
  safetyMgr.begin();
  autoEngine.begin();

  // 2. Initialize Wi-Fi & ESP-NOW
  wifiMgr.begin();
  espnowMgr.begin();

  // 3. Check for stored credentials or start BLE Provisioning
  bool wifiOk = wifiMgr.connectStored();
  if (!wifiOk) {
    String bleName = String(BLE_DEVICE_PREFIX) + wifiMgr.getDeviceId().substring(11);
    bleProv.begin(bleName);
  }

  // 4. Initialize MQTT Client
  mqttMgr.begin();

  // 4b. Disable Wi-Fi power-save globally for fastest MQTT
  esp_wifi_set_ps(WIFI_PS_NONE);

  // 5. Create FreeRTOS Dual-Core Tasks
  xTaskCreatePinnedToCore(
    TaskNetwork,
    "TaskNetwork",
    8192,
    NULL,
    1,
    &TaskNetworkHandle,
    0 // Core 0
  );

  xTaskCreatePinnedToCore(
    TaskControl,
    "TaskControl",
    8192,
    NULL,
    2,
    &TaskControlHandle,
    1 // Core 1
  );

  Serial.println("[Setup] Dual-Core FreeRTOS tasks started. System READY.");
}

void loop() {
  // Main loop left idle; all execution handled cleanly by FreeRTOS tasks
  vTaskDelay(pdMS_TO_TICKS(1000));
}
