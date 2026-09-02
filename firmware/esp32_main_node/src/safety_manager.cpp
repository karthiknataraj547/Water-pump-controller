#include "safety_manager.h"
#include "pump_controller.h"
#include "espnow_manager.h"
#include "mqtt_manager.h"
#include "config.h"

SafetyManager safetyMgr;

SafetyManager::SafetyManager() : zeroFlowStartTime(0), dryRunDetected(false) {}

void SafetyManager::begin() {
  Serial.println("[SafetyManager] Initialized.");
}

bool SafetyManager::isSafeToStart() {
  // 1. Check if tank sensor is online
  if (!espnowMgr.isSensorOnline()) {
    Serial.println("[SafetyManager] Unsafe: Tank sensor is OFFLINE.");
    return false;
  }

  // 2. Check if tank is already full
  float level = espnowMgr.getSensorState().waterLevelPct;
  if (level >= 95.0f) {
    Serial.printf("[SafetyManager] Unsafe: Tank is already full (%.1f%%).\n", level);
    return false;
  }

  return true;
}

String SafetyManager::getSafetyStatus() const {
  if (pumpCtrl.isEmergencyLocked()) return "CRITICAL_LOCKED";
  if (!espnowMgr.isSensorOnline()) return "WARNING_SENSOR_OFFLINE";
  if (dryRunDetected) return "WARNING_DRY_RUN";
  return "NORMAL";
}

void SafetyManager::loop() {
  if (!pumpCtrl.isRunning()) {
    zeroFlowStartTime = 0;
    return;
  }

  checkMaxRuntime();
  checkTankOverflow();
  checkDryRun();
  checkSensorHealth();
}

void SafetyManager::checkMaxRuntime() {
  if (pumpCtrl.getRunningDurationSeconds() >= MAX_RUN_TIME_LIMIT_SEC) {
    Serial.printf("[SafetyManager] ⚠️ MAX RUNTIME EXCEEDED (%u sec). Automatically stopping pump.\n", MAX_RUN_TIME_LIMIT_SEC);
    pumpCtrl.stopPump("SAFETY_MAX_RUNTIME_TRIP");
    mqttMgr.publishAlert("WARNING", "MAX_RUNTIME_EXCEEDED", "Pump stopped automatically after reaching max runtime limit of 45 minutes.");
  }
}

void SafetyManager::checkTankOverflow() {
  if (espnowMgr.isSensorOnline()) {
    float level = espnowMgr.getSensorState().waterLevelPct;
    if (level >= 95.0f) {
      Serial.printf("[SafetyManager] ⚠️ TANK FULL (%.1f%%). Automatically stopping pump.\n", level);
      pumpCtrl.stopPump("SAFETY_TANK_FULL_TRIP");
      mqttMgr.publishAlert("INFO", "TANK_FULL", "Pump stopped automatically as tank reached 95% full.");
    }
  }
}

void SafetyManager::checkDryRun() {
  if (!espnowMgr.isSensorOnline()) return;

  float flow = espnowMgr.getSensorState().flowRateLpm;
  if (flow < 1.0f) { // Less than 1 LPM while pump is running
    if (zeroFlowStartTime == 0) {
      zeroFlowStartTime = millis();
    } else if (millis() - zeroFlowStartTime > (DRY_RUN_TIMEOUT_SEC * 1000)) {
      Serial.println("[SafetyManager] 🚨 DRY RUN DETECTED! Zero flow for 60s while pump is active. Emergency trip!");
      dryRunDetected = true;
      pumpCtrl.emergencyStop("SAFETY_DRY_RUN_TRIP");
      mqttMgr.publishAlert("CRITICAL", "DRY_RUN_DETECTED", "Pump motor tripped! Zero water flow detected for 60 seconds (Dry Run).");
    }
  } else {
    zeroFlowStartTime = 0;
    dryRunDetected = false;
  }
}

void SafetyManager::checkSensorHealth() {
  if (!espnowMgr.isSensorOnline()) {
    Serial.println("[SafetyManager] ⚠️ Tank sensor lost while pump running. Stopping pump for safety.");
    pumpCtrl.stopPump("SAFETY_SENSOR_LOST");
  }
}
