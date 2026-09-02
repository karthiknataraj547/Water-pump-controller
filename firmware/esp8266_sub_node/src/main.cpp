#include <Arduino.h>
#include "config.h"
#include "protocol.h"
#include "sensor_manager.h"
#include "espnow_transmitter.h"
#include "power_manager.h"

void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(PIN_LED_STATUS, OUTPUT);
  digitalWrite(PIN_LED_STATUS, HIGH); // Off (active LOW on NodeMCU)

  Serial.println("\n=======================================================");
  Serial.println("  IoT Water Tank Sensor Node - ESP8266");
  Serial.printf("  Node ID: %s\n", DEFAULT_NODE_ID);
  Serial.println("=======================================================\n");

  powerMgr.begin();
  sensorMgr.begin();
  espnowTx.begin();

  Serial.println("[Setup] ESP8266 Sensor Node initialized.");
}

void loop() {
  espnowTx.loop();
  delay(10);
}
