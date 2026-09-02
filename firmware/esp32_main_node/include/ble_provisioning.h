#ifndef BLE_PROVISIONING_H
#define BLE_PROVISIONING_H

#include <NimBLEDevice.h>

class BleProvisioningServer : public NimBLEServerCallbacks, public NimBLECharacteristicCallbacks {
public:
  BleProvisioningServer();
  void begin(const String &deviceName);
  void stop();
  void updateStatus(const String &state, const String &ip = "", const String &error = "");

  void onConnect(NimBLEServer* pServer) override;
  void onDisconnect(NimBLEServer* pServer) override;
  void onWrite(NimBLECharacteristic* pCharacteristic) override;

  bool isClientConnected() const { return deviceConnected; }
  bool isProvisioningComplete() const { return provisioningComplete; }

private:
  NimBLEServer *pServer;
  NimBLECharacteristic *pSsidChar;
  NimBLECharacteristic *pPassChar;
  NimBLECharacteristic *pTokenChar;
  NimBLECharacteristic *pStatusChar;
  NimBLECharacteristic *pInfoChar;

  String incomingSsid;
  String incomingPass;
  String incomingToken;

  bool deviceConnected;
  bool provisioningComplete;
};

extern BleProvisioningServer bleProv;

#endif // BLE_PROVISIONING_H
