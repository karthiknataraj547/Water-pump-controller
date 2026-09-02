#include "power_manager.h"
#include <ESP8266WiFi.h>

PowerManager powerMgr;

PowerManager::PowerManager() {}

void PowerManager::begin() {
  // Disable Wi-Fi modem sleep when actively streaming ESP-NOW
  wifi_set_sleep_type(NONE_SLEEP_T);
}

void PowerManager::enterDeepSleep(uint32_t sleepSeconds) {
  Serial.printf("[PowerManager] Entering deep sleep for %u seconds...\n", sleepSeconds);
  ESP.deepSleep(sleepSeconds * 1000000ULL, WAKE_RF_DEFAULT);
}

void PowerManager::enterLightSleep(uint32_t sleepMs) {
  wifi_set_sleep_type(LIGHT_SLEEP_T);
  delay(sleepMs);
  wifi_set_sleep_type(NONE_SLEEP_T);
}
