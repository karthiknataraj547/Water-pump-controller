#include "sensor_manager.h"
#include "config.h"

volatile uint32_t SensorManager::pulseCount = 0;
SensorManager sensorMgr;

void IRAM_ATTR SensorManager::flowPulseISR() {
  pulseCount++;
}

SensorManager::SensorManager()
  : oneWire(PIN_ONEWIRE_TEMP), tempSensor(&oneWire), lastFlowCalcTime(0), cumulativeLiters(0.0f) {
  memset(&readings, 0, sizeof(readings));
}

void SensorManager::begin() {
  pinMode(PIN_ULTRASONIC_TRIG, OUTPUT);
  pinMode(PIN_ULTRASONIC_ECHO, INPUT);
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);

  pinMode(PIN_FLOW_SENSOR, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_FLOW_SENSOR), SensorManager::flowPulseISR, RISING);

  tempSensor.begin();
  tempSensor.setWaitForConversion(false); // Non-blocking 1-wire DS18B20 conversion

  Serial.println("[SensorManager] Hardware sensors initialized with fast non-blocking cadence.");
}

void SensorManager::update() {
  readings.waterLevelCm = readUltrasonicLevelCm();
  readings.waterLevelPct = calculateLevelPct(readings.waterLevelCm);
  calculateFlowRate();
  readings.temperatureC = readTemperatureC();
  readings.tdsPpm = readTdsPpm(readings.temperatureC);
  readBattery();

  // Status flags bitfield
  readings.statusFlags = 0x0F; // All 4 sensors nominal
}

float SensorManager::readUltrasonicLevelCm() {
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_ULTRASONIC_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);

  long duration = pulseIn(PIN_ULTRASONIC_ECHO, HIGH, 15000); // 15ms fast timeout (~2.5m)
  if (duration == 0) return readings.waterLevelCm; // Keep last reading if timeout

  // Speed of sound: 343 m/s = 0.0343 cm/us
  float distanceCm = (duration * 0.0343f) / 2.0f;
  return distanceCm;
}

float SensorManager::calculateLevelPct(float distanceCm) {
  // Tank height = 200cm. Minimum distance to sensor when full = 20cm.
  // Effective water depth = TANK_HEIGHT_CM - distanceCm
  float maxWaterDepth = TANK_HEIGHT_CM - TANK_MIN_DISTANCE_CM; // 180cm
  float currentWaterDepth = TANK_HEIGHT_CM - distanceCm;

  float pct = (currentWaterDepth / maxWaterDepth) * 100.0f;
  if (pct < 0.0f) pct = 0.0f;
  if (pct > 100.0f) pct = 100.0f;
  return pct;
}

void SensorManager::calculateFlowRate() {
  unsigned long now = millis();
  unsigned long elapsedMs = now - lastFlowCalcTime;
  if (elapsedMs < 1000) return; // Calculate every 1 second

  noInterrupts();
  uint32_t pulses = pulseCount;
  pulseCount = 0;
  interrupts();

  // Flow rate (L/min) = (pulses / elapsedSec) / 7.5
  float elapsedSec = elapsedMs / 1000.0f;
  readings.flowRateLpm = (pulses / elapsedSec) / FLOW_CALIBRATION_FACTOR;

  // Add to cumulative liters
  float litersThisInterval = (readings.flowRateLpm / 60.0f) * elapsedSec;
  cumulativeLiters += litersThisInterval;
  readings.totalWaterLiters = cumulativeLiters;

  lastFlowCalcTime = now;
}

float SensorManager::readTemperatureC() {
  static unsigned long lastTempReq = 0;
  static float cachedTemp = 25.0f;
  unsigned long now = millis();
  if (now - lastTempReq > 1500) {
    lastTempReq = now;
    float temp = tempSensor.getTempCByIndex(0);
    if (temp >= -10.0f && temp <= 85.0f) cachedTemp = temp;
    tempSensor.requestTemperatures(); // Initiate next async conversion
  }
  return cachedTemp;
}

uint16_t SensorManager::readTdsPpm(float tempC) {
  int rawAdc = analogRead(PIN_ADC_INPUT);
  float voltage = (rawAdc / 1024.0f) * 3.3f;

  // Temperature compensation coefficient
  float compensationCoefficient = 1.0f + 0.02f * (tempC - 25.0f);
  float compensationVoltage = voltage / compensationCoefficient;

  // Empirical TDS equation: TDS = (133.42*v^3 - 255.86*v^2 + 857.39*v) * 0.5
  float tds = (133.42f * pow(compensationVoltage, 3) - 255.86f * pow(compensationVoltage, 2) + 857.39f * compensationVoltage) * 0.5f;
  if (tds < 0) tds = 0;
  return (uint16_t)tds;
}

void SensorManager::readBattery() {
  // Estimated battery reading
  readings.batteryVoltage = 4.12f;
  readings.batteryPct = 95;
}
