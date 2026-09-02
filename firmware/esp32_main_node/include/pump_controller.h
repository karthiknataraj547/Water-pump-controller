#ifndef PUMP_CONTROLLER_H
#define PUMP_CONTROLLER_H

#include <Arduino.h>

enum PumpPhysicalState {
  PUMP_STOPPED,
  PUMP_RUNNING,
  PUMP_EMERGENCY_LOCKED
};

class PumpController {
public:
  PumpController();
  void begin();
  void loop();

  bool startPump(const String &source = "MANUAL");
  void stopPump(const String &source = "MANUAL");
  void emergencyStop(const String &source = "EMERGENCY_BUTTON");
  void clearEmergencyLock();

  bool isRunning() const { return currentState == PUMP_RUNNING; }
  bool isEmergencyLocked() const { return currentState == PUMP_EMERGENCY_LOCKED; }
  uint32_t getRunningDurationSeconds() const;
  String getStateString() const;

private:
  void checkPhysicalButtons();

  PumpPhysicalState currentState;
  unsigned long pumpStartTime;
  unsigned long lastStateChangeTime;
  unsigned long lastButtonCheckTime;

  bool lastManualBtnState;
  bool lastEmergencyBtnState;
};

extern PumpController pumpCtrl;

#endif // PUMP_CONTROLLER_H
