#include "automation_engine.h"
#include "pump_controller.h"
#include "espnow_manager.h"
#include "config.h"
#include <Preferences.h>

AutomationEngine autoEngine;

AutomationEngine::AutomationEngine()
  : currentMode(MODE_AUTO), autoStartLevelPct(30.0f), autoStopLevelPct(90.0f), lastEvalTime(0) {}

void AutomationEngine::begin() {
  Preferences prefs;
  prefs.begin(NVS_NAMESPACE, true);
  autoStartLevelPct = prefs.getFloat("auto_start", 30.0f);
  autoStopLevelPct = prefs.getFloat("auto_stop", 90.0f);
  uint8_t modeVal = prefs.getUChar("mode", 1);
  currentMode = (modeVal == 0) ? MODE_MANUAL : MODE_AUTO;
  prefs.end();

  Serial.printf("[AutomationEngine] Initialized. Mode: %s, Start at: %.1f%%, Stop at: %.1f%%\n",
                getModeString().c_str(), autoStartLevelPct, autoStopLevelPct);
}

void AutomationEngine::setMode(SystemControlMode mode) {
  currentMode = mode;
  Preferences prefs;
  prefs.begin(NVS_NAMESPACE, false);
  prefs.putUChar("mode", mode == MODE_MANUAL ? 0 : 1);
  prefs.end();
  Serial.printf("[AutomationEngine] Control mode switched to: %s\n", getModeString().c_str());
}

String AutomationEngine::getModeString() const {
  return (currentMode == MODE_AUTO) ? "AUTO" : "MANUAL";
}

void AutomationEngine::setAutoStartLevel(float pct) {
  autoStartLevelPct = pct;
  Preferences prefs;
  prefs.begin(NVS_NAMESPACE, false);
  prefs.putFloat("auto_start", pct);
  prefs.end();
}

void AutomationEngine::setAutoStopLevel(float pct) {
  autoStopLevelPct = pct;
  Preferences prefs;
  prefs.begin(NVS_NAMESPACE, false);
  prefs.putFloat("auto_stop", pct);
  prefs.end();
}

void AutomationEngine::updateConfigFromJson(JsonObject config) {
  if (config.containsKey("auto_start_level_pct")) {
    setAutoStartLevel(config["auto_start_level_pct"].as<float>());
  } else if (config.containsKey("autoStartLevel")) {
    setAutoStartLevel(config["autoStartLevel"].as<float>());
  }
  if (config.containsKey("auto_stop_level_pct")) {
    setAutoStopLevel(config["auto_stop_level_pct"].as<float>());
  } else if (config.containsKey("autoStopLevel")) {
    setAutoStopLevel(config["autoStopLevel"].as<float>());
  }
  if (config.containsKey("mode")) {
    String m = config["mode"].as<String>();
    setMode(m == "MANUAL" ? MODE_MANUAL : MODE_AUTO);
  }
  Serial.println("[AutomationEngine] Config updated via MQTT/Cloud.");
}

void AutomationEngine::loop() {
  if (currentMode != MODE_AUTO) return;

  // SAFETY INTERLOCK: In AUTO mode, if sub-node is not connected with main node, motor must NOT work!
  if (!espnowMgr.isSensorOnline()) {
    if (pumpCtrl.isRunning()) {
      Serial.println("[AutomationEngine] 🔒 SAFETY INTERLOCK: Sub-node disconnected in AUTO mode. Halting motor immediately!");
      pumpCtrl.stopPump("SUB_NODE_DISCONNECTED_AUTO_CUTOFF");
    }
    return;
  }

  if (millis() - lastEvalTime < 500) return; // Responsive evaluation every 500ms
  lastEvalTime = millis();

  float level = espnowMgr.getSensorState().waterLevelPct;

  // AUTO START RULE: Water level drops below auto-start threshold
  if (!pumpCtrl.isRunning() && level <= autoStartLevelPct) {
    Serial.printf("[AutomationEngine] Auto Rule Triggered: Water Level (%.1f%%) <= Start Threshold (%.1f%%). Starting pump.\n",
                  level, autoStartLevelPct);
    pumpCtrl.startPump("LOCAL_AUTO_RULE_LOW_LEVEL");
  }

  // AUTO STOP RULE: Water level reaches or exceeds auto-stop threshold
  if (pumpCtrl.isRunning() && level >= autoStopLevelPct) {
    Serial.printf("[AutomationEngine] Auto Rule Triggered: Water Level (%.1f%%) >= Stop Threshold (%.1f%%). Stopping pump.\n",
                  level, autoStopLevelPct);
    pumpCtrl.stopPump("LOCAL_AUTO_RULE_FULL_TANK");
  }
}
