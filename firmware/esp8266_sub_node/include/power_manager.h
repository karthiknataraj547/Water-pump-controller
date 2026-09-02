#ifndef POWER_MANAGER_H
#define POWER_MANAGER_H

#include <Arduino.h>

class PowerManager {
public:
  PowerManager();
  void begin();
  void enterDeepSleep(uint32_t sleepSeconds);
  void enterLightSleep(uint32_t sleepMs);
};

extern PowerManager powerMgr;

#endif // POWER_MANAGER_H
