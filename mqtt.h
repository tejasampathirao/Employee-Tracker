#ifndef MQTT_H
#define MQTT_H

#include <Arduino.h>
#include "RTClib.h"

// ==================== MODEM & MQTT CONSTANTS ====================
#define MODEM_TX   16
#define MODEM_RX   17
#define MODEM_KEY  38

#define MQTT_SERVER     "13.203.2.58"
#define MQTT_PORT       1883
#define MQTT_CLIENT_ID  "INPUT_MONITOR_#01"
#define MQTT_TOPIC      "home/power"

class MQTTManager {
private:
  // All your private member variables here
  // (like modemSerial, rtc, modemReady, gprsConnected, etc.)
  HardwareSerial* modemSerial;
  RTC_DS3231* rtc;
  bool rtcReady;
  bool modemReady;
  bool gprsConnected;
  bool mqttConnected;
  bool simReady;
  bool networkRegistered;
  int signalQuality;
  String modemIP;
  String simProvider;
  String apn_name;
  unsigned long lastMqttPublish;
  unsigned long lastConnectionCheck;
  unsigned long lastKeepalive;
  int connectionRetries;
  
public:
  // Constructor and destructor
  MQTTManager(RTC_DS3231* rtcPtr, HardwareSerial* serialPtr);
  ~MQTTManager();
  
  // All your function declarations here
  void initializeModem();
  void powerOnModem();
  void setupModem();
  String sendATCommand(String command, unsigned long timeout);
  bool checkModemStatus();
  bool checkSIMStatus();
  bool checkNetworkRegistration();
  int getSignalQuality();
  String detectSIMProvider();
  void autoConfigureAPN();
  void checkSIMBalance();
  void activatePDPContext();
  bool checkGPRSStatus();
  // ... (all the rest of your public functions)
  
  // MQTT operations
  void connectToMQTT();
  void disconnectMQTT();
  void closeMQTTSocket();
  void publishGPIOEvent(String deviceId, String status, String timestamp);
  void publishModbusData(float reg1, float reg2, String timestamp);
  void publishToTopic(String topic, String payload);
  void sendKeepalive();
  void checkMQTTConnectionStatus();
  
  // Utility
  String getRTCTimestamp();
  String getRTCDate();
  String readResponse(unsigned long timeout);
  void displayModemStatus();
  
  // Getters
  bool isModemReady() const;
  bool isGPRSConnected() const;
  bool isMQTTConnected() const;
  bool isSIMReady() const;
  bool isNetworkRegistered() const;
  int getSignalQualityValue() const;
  String getModemIP() const;
  String getSIMProvider() const;
  String getAPN() const;
  void setAPN(String newAPN);
};

#endif // MQTT_H