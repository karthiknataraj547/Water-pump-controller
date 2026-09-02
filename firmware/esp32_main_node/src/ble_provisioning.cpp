#include "ble_provisioning.h"
#include "protocol.h"
#include "wifi_manager.h"
#include <ArduinoJson.h>

BleProvisioningServer bleProv;

BleProvisioningServer::BleProvisioningServer()
  : pServer(nullptr), pSsidChar(nullptr), pPassChar(nullptr),
    pTokenChar(nullptr), pStatusChar(nullptr), pInfoChar(nullptr),
    deviceConnected(false), provisioningComplete(false) {}

void BleProvisioningServer::begin(const String &deviceName) {
  NimBLEDevice::init(deviceName.c_str());
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(this);

  NimBLEService *pService = pServer->createService(SERVICE_UUID_PROV);

  pSsidChar = pService->createCharacteristic(CHAR_UUID_WIFI_SSID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  pSsidChar->setCallbacks(this);

  pPassChar = pService->createCharacteristic(CHAR_UUID_WIFI_PASS, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  pPassChar->setCallbacks(this);

  pTokenChar = pService->createCharacteristic(CHAR_UUID_AUTH_TOKEN, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  pTokenChar->setCallbacks(this);

  pStatusChar = pService->createCharacteristic(CHAR_UUID_PROV_STATUS, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  pInfoChar = pService->createCharacteristic(CHAR_UUID_DEVICE_INFO, NIMBLE_PROPERTY::READ);
  
  // Set device info JSON
  StaticJsonDocument<256> infoDoc;
  infoDoc["device_id"] = wifiMgr.getDeviceId();
  infoDoc["mac"] = wifiMgr.getMacAddress();
  infoDoc["fw_version"] = "1.0.0";
  String infoStr;
  serializeJson(infoDoc, infoStr);
  pInfoChar->setValue(infoStr);

  pService->start();

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID_PROV);
  pAdvertising->setScanResponse(true);
  pAdvertising->start();

  Serial.printf("[BLE] Advertising started as '%s'\n", deviceName.c_str());
}

void BleProvisioningServer::stop() {
  if (pServer) {
    NimBLEDevice::getAdvertising()->stop();
    NimBLEDevice::deinit(true);
    pServer = nullptr;
    Serial.println("[BLE] Provisioning server stopped.");
  }
}

void BleProvisioningServer::updateStatus(const String &state, const String &ip, const String &error) {
  if (!pStatusChar) return;

  StaticJsonDocument<256> doc;
  doc["state"] = state;
  doc["ip_address"] = ip;
  doc["mac_address"] = wifiMgr.getMacAddress();
  doc["device_id"] = wifiMgr.getDeviceId();
  if (error.length() > 0) {
    doc["error_message"] = error;
  }
  
  String jsonStr;
  serializeJson(doc, jsonStr);
  pStatusChar->setValue(jsonStr);
  pStatusChar->notify();

  Serial.printf("[BLE] Status Notification: %s\n", jsonStr.c_str());
}

void BleProvisioningServer::onConnect(NimBLEServer* pServer) {
  deviceConnected = true;
  Serial.println("[BLE] Central device connected via BLE!");
  updateStatus("CONNECTED_BLE");
}

void BleProvisioningServer::onDisconnect(NimBLEServer* pServer) {
  deviceConnected = false;
  Serial.println("[BLE] Central device disconnected.");
  if (!provisioningComplete) {
    NimBLEDevice::startAdvertising();
  }
}

void BleProvisioningServer::onWrite(NimBLECharacteristic* pCharacteristic) {
  std::string uuid = pCharacteristic->getUUID().toString();
  std::string value = pCharacteristic->getValue();
  String valStr = String(value.c_str());

  if (uuid == CHAR_UUID_WIFI_SSID) {
    incomingSsid = valStr;
    Serial.printf("[BLE] Received SSID: %s\n", incomingSsid.c_str());
  } else if (uuid == CHAR_UUID_WIFI_PASS) {
    incomingPass = valStr;
    Serial.println("[BLE] Received Wi-Fi Password.");
  } else if (uuid == CHAR_UUID_AUTH_TOKEN) {
    incomingToken = valStr;
    Serial.printf("[BLE] Received Claim Token: %s\n", incomingToken.c_str());

    // Trigger Wi-Fi connection attempt with newly received credentials
    if (incomingSsid.length() > 0) {
      updateStatus("CONNECTING_WIFI");
      bool success = wifiMgr.connectNew(incomingSsid, incomingPass);
      if (success) {
        updateStatus("SUCCESS", wifiMgr.getIP());
        provisioningComplete = true;
      } else {
        updateStatus("ERROR", "", "Failed to connect to Wi-Fi. Invalid credentials or network out of range.");
      }
    }
  }
}
