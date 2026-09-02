#ifndef SAFETY_MANAGER_H
#define SAFETY_MANAGER_H

#include <Arduino.h>

class SafetyManager {
public:
  SafetyManager();
  void begin();
  void loop();

  bool isSafeToStart();
  String getSafetyStatus() const;

private:
  void checkDryRun();
  void checkMaxRuntime();
  void checkTankOverflow();
  void checkSensorHealth();

  unsigned long zeroFlowStartTime;
  bool dryRunDetected;
};

extern SafetyManager safetyMgr;

#endif // SAFETY_MANAGER_H
