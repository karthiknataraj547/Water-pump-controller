#include "pump_controller.h"
#include "config.h"
#include "safety_manager.h"
#include "mqtt_manager.h"

PumpController pumpCtrl;

PumpController::PumpController()
  : currentState(PUMP_STOPPED), pumpStartTime(0), lastStateChangeTime(0),
    lastButtonCheckTime(0), lastManualBtnState(HIGH), lastEmergencyBtnState(HIGH) {}

void PumpController::begin() {
  pinMode(PIN_RELAY_PUMP, OUTPUT);
  digitalWrite(PIN_RELAY_PUMP, LOW); // Relay normally OPEN

  pinMode(PIN_LED_PUMP, OUTPUT);
  digitalWrite(PIN_LED_PUMP, LOW);

  pinMode(PIN_BUZZER, OUTPUT);
  digitalWrite(PIN_BUZZER, LOW);

  pinMode(PIN_EMERGENCY_STOP, INPUT_PULLUP);
  pinMode(PIN_MANUAL_BUTTON, INPUT_PULLUP);

  Serial.println("[PumpController] Relay & button I/O initialized.");
}

bool PumpController::startPump(const String &source) {
  if (currentState == PUMP_EMERGENCY_LOCKED) {
    Serial.printf("[PumpController] Start request rejected: System is EMERGENCY LOCKED.\n");
    return false;
  }

  // Anti-cycling protection: minimum 10 seconds between off -> on
  if (millis() - lastStateChangeTime < 10000 && lastStateChangeTime > 0) {
    Serial.printf("[PumpController] Start request rejected: Anti-cycling rest period active.\n");
    return false;
  }

  // Interlock verification by Safety Manager
  if (!safetyMgr.isSafeToStart()) {
    Serial.printf("[PumpController] Start request rejected by Safety Manager!\n");
    return false;
  }

  digitalWrite(PIN_RELAY_PUMP, HIGH); // Energize relay
  digitalWrite(PIN_LED_PUMP, HIGH);

  currentState = PUMP_RUNNING;
  pumpStartTime = millis();
  lastStateChangeTime = millis();

  Serial.printf("[PumpController] PUMP STARTED! Triggered by: %s\n", source.c_str());
  mqttMgr.publishStatus("ON", "AUTO", 0, "NORMAL");
  return true;
}

void PumpController::stopPump(const String &source) {
  if (currentState == PUMP_STOPPED) return;

  digitalWrite(PIN_RELAY_PUMP, LOW); // De-energize relay
  digitalWrite(PIN_LED_PUMP, LOW);

  uint32_t durationSec = getRunningDurationSeconds();
  currentState = PUMP_STOPPED;
  lastStateChangeTime = millis();
  pumpStartTime = 0;

  Serial.printf("[PumpController] PUMP STOPPED! Duration: %u sec. Source: %s\n", durationSec, source.c_str());
  mqttMgr.publishStatus("OFF", "AUTO", 0, "NORMAL");
}

void PumpController::emergencyStop(const String &source) {
  digitalWrite(PIN_RELAY_PUMP, LOW);
  digitalWrite(PIN_LED_PUMP, LOW);

  // Beep alarm buzzer
  digitalWrite(PIN_BUZZER, HIGH);
  delay(200);
  digitalWrite(PIN_BUZZER, LOW);

  currentState = PUMP_EMERGENCY_LOCKED;
  lastStateChangeTime = millis();
  pumpStartTime = 0;

  Serial.printf("[PumpController] 🚨 EMERGENCY STOP ACTIVATED! Source: %s\n", source.c_str());
  mqttMgr.publishAlert("EMERGENCY", "EMERGENCY_STOP", "Emergency stop activated by " + source);
  mqttMgr.publishStatus("EMERGENCY_STOP", "MANUAL", 0, "CRITICAL");
}

void PumpController::clearEmergencyLock() {
  if (currentState == PUMP_EMERGENCY_LOCKED) {
    currentState = PUMP_STOPPED;
    lastStateChangeTime = millis();
    Serial.println("[PumpController] Emergency lock CLEARED.");
    mqttMgr.publishStatus("OFF", "AUTO", 0, "NORMAL");
  }
}

uint32_t PumpController::getRunningDurationSeconds() const {
  if (currentState != PUMP_RUNNING || pumpStartTime == 0) return 0;
  return (millis() - pumpStartTime) / 1000;
}

String PumpController::getStateString() const {
  switch (currentState) {
    case PUMP_RUNNING: return "ON";
    case PUMP_STOPPED: return "OFF";
    case PUMP_EMERGENCY_LOCKED: return "EMERGENCY_STOP";
    default: return "OFF";
  }
}

void PumpController::loop() {
  checkPhysicalButtons();
}

void PumpController::checkPhysicalButtons() {
  if (millis() - lastButtonCheckTime < 50) return; // 50ms button debounce
  lastButtonCheckTime = millis();

  // Read hardware emergency button (Active LOW)
  bool emergencyBtn = digitalRead(PIN_EMERGENCY_STOP);
  if (emergencyBtn == LOW && lastEmergencyBtnState == HIGH) {
    emergencyStop("PHYSICAL_PANEL_BUTTON");
  }
  lastEmergencyBtnState = emergencyBtn;

  // Read manual toggle button (Active LOW)
  bool manualBtn = digitalRead(PIN_MANUAL_BUTTON);
  if (manualBtn == LOW && lastManualBtnState == HIGH) {
    if (isRunning()) {
      stopPump("PHYSICAL_TOGGLE_BUTTON");
    } else {
      startPump("PHYSICAL_TOGGLE_BUTTON");
    }
  }
  lastManualBtnState = manualBtn;
}
