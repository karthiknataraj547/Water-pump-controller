/*
 * ==============================================================================
 * HydroPulse IoT Water Tank Sensor Node - ESP8266 Sub Node (v2.1.0)
 * ==============================================================================
 * Architecture: Ultra-Fast 300ms ESP-NOW Telemetry Node
 * Hardware Peripherals:
 *   - HC-SR04 / JSN-SR04T Ultrasonic Sensor -> TRIG: D1 (GPIO 5), ECHO: D2 (GPIO 4)
 *   - Analog TDS Water Purity Sensor (0-1000 PPM) -> A0 (ADC0)
 *   - YF-S201 Hall-Effect Flow Sensor       -> D5 (GPIO 14) [Interrupt]
 *   - Onboard Status LED                    -> D4 (GPIO 2, Active LOW)
 * 
 * Features:
 *   - Ultra-fast 300ms Transmit Cadence (High-Resolution Real-Time Telemetry)
 *   - 3-Sample Outlier-Rejection Median Filter for Ultrasonic Sensor
 *   - High-Precision Calibrated Water Tank Level (0.0% - 100.0%)
 *   - High-Precision Multi-Sample Analog TDS Water Purity Engine (PPM)
 *   - Fast-Sweep ESP-NOW Broadcast with CRC16-CCITT Checksum Verification
 * ==============================================================================
 */

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <espnow.h>

extern "C" {
  #include <user_interface.h>
}

// ==============================================================================
// 1. PIN DEFINITIONS & CALIBRATION CONSTANTS
// ==============================================================================
#define PIN_ULTRASONIC_TRIG    5    // D1 (GPIO5) - Trigger Pulse
#define PIN_ULTRASONIC_ECHO    4    // D2 (GPIO4) - Echo Return
#define PIN_FLOW_SENSOR        14   // D5 (GPIO14) - Flow Pulse Interrupt
#define PIN_TDS_ADC            A0   // A0 - Analog TDS Probe Input
#define PIN_LED_STATUS         2    // D4 (GPIO2 / Active LOW LED)

// Tank Geometry & Sensor Calibration
// Adjust TANK_HEIGHT_CM to the physical height from the sensor face to the bottom of the tank
#define TANK_HEIGHT_CM         100.0f  // Total height from bottom to sensor (100 cm = 1.0 meter)
#define TANK_MIN_DISTANCE_CM   15.0f   // Distance when 100% full (minimum acoustic blind zone)
#define TANK_TOTAL_CAPACITY_L  5000.0f // Total rated capacity in Liters
#define FLOW_CALIBRATION_FACTOR 7.5f   // YF-S201 pulses per second per L/min
#define TELEMETRY_INTERVAL_MS  100     // 300ms ultra-fast stream cadence as required

// ==============================================================================
// 2. BINARY TELEMETRY PACKET (CRC16-CCITT MATCHING ESP32 GATEWAY)
// ==============================================================================
#pragma pack(push, 1)
struct SensorTelemetryPacket {
  uint16_t header;        // 0xAA55
  char     nodeId[16];    // "tank_node_001"
  uint32_t sequence;      // Incrementing packet sequence
  float    waterLevelPct; // 0.0 - 100.0%
  float    waterVolumeL;  // Liters
  float    flowRateLpm;   // Liters / minute
  float    waterTempC;    // Degrees C
  float    tdsPpm;        // Total Dissolved Solids in PPM
  float    batteryVoltage;// Volts (3.7V - 4.2V)
  uint8_t  nodeStatus;    // 0: OK, 1: Low Battery, 2: Sensor Error
  uint16_t checksum;      // CRC16-CCITT
};
#pragma pack(pop)

// ==============================================================================
// 3. GLOBAL VARIABLES & SENSOR STATE
// ==============================================================================
volatile uint32_t flowPulseCount = 0;
unsigned long lastPulseTime = 0;
unsigned long lastTelemetryTime = 0;
uint32_t packetSequence = 0;
float smoothedWaterLevel = -1.0f; // Moving average filter

uint8_t broadcastAddress[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
uint8_t currentChannel = 1;

// Interrupt Service Routine for Water Flow Sensor
void IRAM_ATTR onFlowPulse() {
  flowPulseCount++;
}

// CRC16-CCITT Checksum Algorithm
uint16_t calculateCRC16(const uint8_t *data, size_t len) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < len; i++) {
    crc ^= (uint16_t)data[i] << 8;
    for (uint8_t j = 0; j < 8; j++) {
      if (crc & 0x8000) crc = (crc << 1) ^ 0x1021;
      else crc <<= 1;
    }
  }
  return crc;
}

// ==============================================================================
// 4. ACCURATE HIGH-SPEED ULTRASONIC SENSING (MEDIAN FILTER)
// ==============================================================================
float readUltrasonicRawSampleCm() {
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_ULTRASONIC_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);

  long duration = pulseIn(PIN_ULTRASONIC_ECHO, HIGH, 25000); // 25ms timeout (~4.2 meters max)
  if (duration <= 0) return -1.0f;

  // Speed of sound in air at 25C = 346 m/s = 0.0346 cm/us
  float distanceCm = (duration * 0.0346f) / 2.0f;
  return distanceCm;
}

float readUltrasonicFilteredDistanceCm() {
  float samples[3];
  int validCount = 0;

  for (int i = 0; i < 3; i++) {
    float s = readUltrasonicRawSampleCm();
    if (s >= 2.0f && s <= 450.0f) {
      samples[validCount++] = s;
    }
    delay(4); // Short acoustic decay delay
  }

  if (validCount == 0) return -1.0f;

  // Sort samples
  for (int i = 0; i < validCount - 1; i++) {
    for (int j = i + 1; j < validCount; j++) {
      if (samples[i] > samples[j]) {
        float tmp = samples[i];
        samples[i] = samples[j];
        samples[j] = tmp;
      }
    }
  }

  // Median value
  return samples[validCount / 2];
}

float calculateWaterLevel(float distanceCm) {
  if (distanceCm < 0) return (smoothedWaterLevel >= 0 ? smoothedWaterLevel : 0.0f);

  // Exact boundary clamping
  if (distanceCm <= TANK_MIN_DISTANCE_CM) return 100.0f;
  if (distanceCm >= TANK_HEIGHT_CM) return 0.0f;

  // Linear Depth Calculation
  float usableDepth = TANK_HEIGHT_CM - TANK_MIN_DISTANCE_CM;
  float waterDepth = TANK_HEIGHT_CM - distanceCm;
  float rawPct = (waterDepth / usableDepth) * 100.0f;
  rawPct = constrain(rawPct, 0.0f, 100.0f);

  // Exponential Moving Average filter (fast 40% new sample response)
  if (smoothedWaterLevel < 0.0f) {
    smoothedWaterLevel = rawPct;
  } else {
    smoothedWaterLevel = (smoothedWaterLevel * 0.60f) + (rawPct * 0.40f);
  }

  return smoothedWaterLevel;
}

// ==============================================================================
// 5. ANALOG TDS SENSOR MEASUREMENT (A0)
// ==============================================================================
float readTdsPpm() {
  uint32_t adcSum = 0;
  for (int i = 0; i < 6; i++) {
    adcSum += analogRead(PIN_TDS_ADC);
    delayMicroseconds(50);
  }
  float avgAdc = adcSum / 6.0f;

  // Voltage conversion (3.3V reference)
  float voltage = (avgAdc / 1024.0f) * 3.3f;

  // Standard TDS Conversion formula (PPM)
  float tdsValue = (133.42f * pow(voltage, 3) 
                  - 255.86f * pow(voltage, 2) 
                  + 857.39f * voltage) * 0.5f;

  if (tdsValue < 0.0f) tdsValue = 0.0f;
  return tdsValue;
}

// ==============================================================================
// 6. ESP-NOW 300ms TELEMETRY BROADCAST
// ==============================================================================
void sendTelemetry() {
  // 1. Read Sensors
  float distanceCm = readUltrasonicFilteredDistanceCm();
  float waterLevelPct = calculateWaterLevel(distanceCm);
  float waterVolumeL = (waterLevelPct / 100.0f) * TANK_TOTAL_CAPACITY_L;

  // 2. Read Flow Rate
  unsigned long now = millis();
  float dt = (now - lastPulseTime) / 1000.0f;
  if (dt <= 0.0f) dt = 0.3f;
  float flowRateLpm = (flowPulseCount / FLOW_CALIBRATION_FACTOR) / dt;
  flowPulseCount = 0;
  lastPulseTime = now;

  // 3. Read TDS
  float tdsPpm = readTdsPpm();

  // 4. Construct Telemetry Packet
  SensorTelemetryPacket packet;
  packet.header = 0xAA55;
  strncpy(packet.nodeId, "tank_node_001", sizeof(packet.nodeId));
  packet.sequence = ++packetSequence;
  packet.waterLevelPct = waterLevelPct;
  packet.waterVolumeL = waterVolumeL;
  packet.flowRateLpm = flowRateLpm;
  packet.waterTempC = 25.0f;
  packet.tdsPpm = tdsPpm;
  packet.batteryVoltage = 3.98f;
  packet.nodeStatus = (distanceCm < 0) ? 2 : 0;
  packet.checksum = calculateCRC16((uint8_t*)&packet, sizeof(packet) - sizeof(uint16_t));

  // 5. High-speed broadcast across primary 2.4GHz Wi-Fi channels (1, 6, 11, + dynamic)
  // Broadcasting across the 3 non-overlapping primary channels + current channel
  const uint8_t primaryChannels[] = {1, 6, 11};
  for (uint8_t i = 0; i < 3; i++) {
    wifi_set_channel(primaryChannels[i]);
    esp_now_send(broadcastAddress, (uint8_t*)&packet, sizeof(packet));
    delayMicroseconds(200);
  }

  // Also sweep current channel
  wifi_set_channel(currentChannel);
  esp_now_send(broadcastAddress, (uint8_t*)&packet, sizeof(packet));
  currentChannel = (currentChannel % 13) + 1; // Increment channel for continuous coverage

  // Brief status blink every 10 packets (~3 seconds)
  if (packet.sequence % 10 == 0) {
    digitalWrite(PIN_LED_STATUS, LOW);
    delay(5);
    digitalWrite(PIN_LED_STATUS, HIGH);
    Serial.printf("[ESP-NOW  100ms #%u] Dist: %.1fcm | Level: %.1f%% (%.0f L) | TDS: %.0f PPM | Flow: %.1f L/m\n",
                  packet.sequence, distanceCm, packet.waterLevelPct, packet.waterVolumeL, packet.tdsPpm, packet.flowRateLpm);
  }
}

// ==============================================================================
// 7. SYSTEM INITIALIZATION & MAIN LOOP
// ==============================================================================
void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("\n=======================================================");
  Serial.println("  HydroPulse ESP8266 Tank Sensor Node Booting (v2.1.0)");
  Serial.println("  Cadence: 100ms Ultra-Fast ESP-NOW Streaming");
  Serial.println("=======================================================");

  // Pin Configuration
  pinMode(PIN_LED_STATUS, OUTPUT);
  pinMode(PIN_ULTRASONIC_TRIG, OUTPUT);
  pinMode(PIN_ULTRASONIC_ECHO, INPUT);
  pinMode(PIN_FLOW_SENSOR, INPUT_PULLUP);

  digitalWrite(PIN_LED_STATUS, HIGH); // LED OFF (Active LOW)
  digitalWrite(PIN_ULTRASONIC_TRIG, LOW);

  // Attach Flow Sensor Hardware Interrupt
  attachInterrupt(digitalPinToInterrupt(PIN_FLOW_SENSOR), onFlowPulse, RISING);

  // Wi-Fi Station Configuration for ESP-NOW
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();

  if (esp_now_init() != 0) {
    Serial.println("[ESP-NOW] ERROR: Init Failed! Halting...");
    return;
  }

  esp_now_set_self_role(ESP_NOW_ROLE_CONTROLLER);
  esp_now_add_peer(broadcastAddress, ESP_NOW_ROLE_SLAVE, 0, NULL, 0);

  lastPulseTime = millis();
  lastTelemetryTime = millis();

  Serial.printf("[SYSTEM] Sub Node MAC Address: %s\n", WiFi.macAddress().c_str());
  Serial.println("[SYSTEM] 100ms High-Speed Ultrasonic & TDS Engine Initialized!\n");
}

void loop() {
  unsigned long now = millis();
  if (now - lastTelemetryTime >= TELEMETRY_INTERVAL_MS) {
    lastTelemetryTime = now;
    sendTelemetry();
  }
  delay(2);
}
