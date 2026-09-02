#ifndef SENSOR_MANAGER_H
#define SENSOR_MANAGER_H

#include <Arduino.h>
#include <OneWire.h>
#include <DallasTemperature.h>

struct SensorReadings {
  float waterLevelPct;
  float waterLevelCm;
  float flowRateLpm;
  float totalWaterLiters;
  uint16_t tdsPpm;
  float temperatureC;
  float batteryVoltage;
  uint8_t batteryPct;
  uint8_t statusFlags;
};

class SensorManager {
public:
  SensorManager();
  void begin();
  void update();

  SensorReadings getReadings() const { return readings; }
  static void IRAM_ATTR flowPulseISR();

private:
  float readUltrasonicLevelCm();
  float calculateLevelPct(float levelCm);
  void calculateFlowRate();
  float readTemperatureC();
  uint16_t readTdsPpm(float tempC);
  void readBattery();

  SensorReadings readings;
  OneWire oneWire;
  DallasTemperature tempSensor;

  static volatile uint32_t pulseCount;
  unsigned long lastFlowCalcTime;
  float cumulativeLiters;
};

extern SensorManager sensorMgr;

#endif // SENSOR_MANAGER_H
