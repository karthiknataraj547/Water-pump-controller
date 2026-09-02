#ifndef AUTOMATION_ENGINE_H
#define AUTOMATION_ENGINE_H

#include <Arduino.h>
#include <ArduinoJson.h>

enum SystemControlMode {
  MODE_MANUAL,
  MODE_AUTO
};

class AutomationEngine {
public:
  AutomationEngine();
  void begin();
  void loop();

  void setMode(SystemControlMode mode);
  SystemControlMode getMode() const { return currentMode; }
  String getModeString() const;

  void setAutoStartLevel(float pct);
  void setAutoStopLevel(float pct);

  void updateConfigFromJson(JsonObject config);

private:
  SystemControlMode currentMode;
  float autoStartLevelPct;
  float autoStopLevelPct;

  unsigned long lastEvalTime;
};

extern AutomationEngine autoEngine;

#endif // AUTOMATION_ENGINE_H
