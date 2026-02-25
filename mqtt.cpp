#include "mqtt.h"
#include "debug.h"

MQTTManager::MQTTManager(RTC_DS3231* rtcPtr, HardwareSerial* serialPtr)
  : rtc(rtcPtr), rtcReady(rtcPtr != nullptr),
    modemSerial(serialPtr), modemReady(false), gprsConnected(false), mqttConnected(false),
    simReady(false), networkRegistered(false),
    lastMqttPublish(0), lastConnectionCheck(0), lastKeepalive(0),
    connectionRetries(0), apn_name("bsnlnet"), signalQuality(0) {
}

MQTTManager::~MQTTManager() {
  // Shared serial is owned by the caller; do not delete here
}

void MQTTManager::initializeModem() {
  DEBUG_PRINTLN("═══════════════════════════════════════");
  DEBUG_PRINTLN("4G Modem Initialization");
  DEBUG_PRINTLN("═══════════════════════════════════════");
  if (!modemSerial) {
    STATUS_FAIL("Modem serial not provided");
    return;
  }
  
  modemSerial->begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  
  pinMode(MODEM_KEY, OUTPUT);
  
  powerOnModem();
  delay(5000);
  
  setupModem();
  
  checkModemStatus();
  displayModemStatus();
  
  DEBUG_PRINTLN("");
}

void MQTTManager::powerOnModem() {
  DEBUG_PRINTLN("Powering modem...");
  digitalWrite(MODEM_KEY, LOW);
  delay(1000);
  digitalWrite(MODEM_KEY, HIGH);
  delay(2000);
  digitalWrite(MODEM_KEY, LOW);
  delay(3000);
  STATUS_OK("Modem power cycle complete");
}

void MQTTManager::setupModem() {
  DEBUG_PRINTLN("Configuring modem...");
  
  delay(2000);
  
  for (int i = 0; i < 1; i++) {
    DEBUG_PRINTF("Attempt %d/5: ", i + 1);
    String response = sendATCommand("AT", 2000);
    if (response.indexOf("OK") != -1) {
      modemReady = true;
      STATUS_OK("Modem responding");
      break;
    }
    DEBUG_PRINTLN("No response, retrying...");
    delay(2000);
  }
  
  if (!modemReady) {
    STATUS_FAIL("Modem not responding!");
    return;
  }
  
  DEBUG_PRINTLN("\n[MODEM] Sending setup commands...");
  sendATCommand("ATE1", 1000);
  delay(100);
  sendATCommand("AT+CMGF=1", 1000);
  delay(100);
  sendATCommand("AT+CREG=2", 1000);
  delay(100);
  sendATCommand("AT+CFUN=1", 2000);
  delay(500);
  
  STATUS_OK("Modem configured");
  DEBUG_PRINTLN("\n[MODEM] Checking SIM...");
  simReady = checkSIMStatus();
  delay(500);
  
  if (!simReady) {
    STATUS_FAIL("SIM not detected - SMS/MQTT won't work!");
    return;
  }
  
  DEBUG_PRINTLN("\n[MODEM] Waiting for network (30-60 sec)...");
  bool networkOK = false;
  for (int i = 0; i < 3; i++) {
    delay(1000);
    if (checkNetworkRegistration()) {
      STATUS_OK("Network registered!");
      networkOK = true;
      networkRegistered = true;
      break;
    }
    DEBUG_PRINT(".");
  }
  
  if (!networkOK) {
    WARN_PRINTLN("\nNetwork registration not confirmed (may still work)");
  }
  
  DEBUG_PRINTLN("\n[MODEM] Checking signal quality...");
  getSignalQuality();
  delay(300);
  
  DEBUG_PRINTLN("\n[MODEM] Detecting SIM provider...");
  String provider = detectSIMProvider();
  autoConfigureAPN();
}

String MQTTManager::readResponse(unsigned long timeout) {
  String response = "";
  unsigned long start = millis();
  
  while (millis() - start < timeout) {
    while (modemSerial->available()) {
      char c = modemSerial->read();
      response += c;
      
      if (c == '\n') {
        if (response.endsWith("OK\r\n") || 
            response.endsWith("ERROR\r\n") ||
            response.indexOf("+CME ERROR") != -1 ||
            response.indexOf("+QMTOPEN:") != -1 ||
            response.indexOf("+QMTCONN:") != -1 ||
            response.indexOf("+QMTPUB:") != -1) {
          delay(50);
          while (modemSerial->available()) {
            response += (char)modemSerial->read();
          }
          return response;
        }
      }
    }
    delay(10);
  }
  
  delay(50);
  while (modemSerial->available()) {
    response += (char)modemSerial->read();
  }
  
  return response;
}

String MQTTManager::sendATCommand(String command, unsigned long timeout) {
  while (modemSerial->available()) modemSerial->read();
  
  DEBUG_PRINTLN("TX: " + command);
  modemSerial->println(command);
  
  unsigned long start = millis();
  String response = "";
  
  while (millis() - start < timeout) {
    if (modemSerial->available()) {
      response += (char)modemSerial->read();
    }
  }
  
  if (response.length() > 0) {
    DEBUG_PRINTLN("RX: " + response);
  }
  
  return response;
}

bool MQTTManager::checkModemStatus() {
  String response = sendATCommand("AT", 2000);
  modemReady = (response.indexOf("OK") != -1);
  
  if (!modemReady) {
    simReady = false;
    networkRegistered = false;
    return false;
  }
  
  simReady = checkSIMStatus();
  delay(300);
  
  if (simReady) {
    networkRegistered = checkNetworkRegistration();
    delay(300);
    signalQuality = getSignalQuality();
    delay(300);
    
    simProvider = detectSIMProvider();
    autoConfigureAPN();
    
    if (networkRegistered) {
      checkSIMBalance();
    }
  }
  
  return (modemReady && simReady);
}

bool MQTTManager::checkSIMStatus() {
  String response = sendATCommand("AT+CPIN?", 2000);
  DEBUG_PRINTLN("[SIM] AT+CPIN? Response: " + response);
  
  if (response.indexOf("+CPIN: READY") != -1) {
    STATUS_OK("SIM ready");
    return true;
  } else if (response.indexOf("ERROR") != -1 || response.length() == 0) {
    STATUS_FAIL("No SIM card detected! Check SIM connection.");
    return false;
  } else if (response.indexOf("+CPIN:") != -1) {
    WARN_PRINTLN("[SIM] SIM state: " + response);
    return false;
  }
  
  WARN_PRINTLN("[SIM] SIM status unknown: " + response);
  return false;
}

bool MQTTManager::checkNetworkRegistration() {
  String response = sendATCommand("AT+CREG?", 2000);
  DEBUG_PRINTLN("[NETWORK] AT+CREG? Response: " + response);
  
  if (response.indexOf(",1") != -1 || response.indexOf(",5") != -1) {
    STATUS_OK("Network registered (Home/Roaming)");
    networkRegistered = true;
    return true;
  } else if (response.indexOf(",2") != -1) {
    STATUS_WAIT("Searching network...");
    networkRegistered = false;
    return false;
  } else if (response.indexOf(",0") != -1) {
    WARN_PRINTLN("[NETWORK] Not registered, not searching");
    networkRegistered = false;
    return false;
  }
  
  WARN_PRINTLN("[NETWORK] Registration status unknown: " + response);
  networkRegistered = false;
  return false;
}

int MQTTManager::getSignalQuality() {
  String response = sendATCommand("AT+CSQ", 2000);
  DEBUG_PRINTLN("[SIGNAL] AT+CSQ Response: " + response);
  
  int idx = response.indexOf("+CSQ: ");
  if (idx != -1) {
    int start = idx + 6;
    int comma = response.indexOf(",", start);
    if (comma != -1) {
      int rssi = response.substring(start, comma).toInt();
      if (rssi >= 0 && rssi <= 31) {
        if (rssi == 31) {
          WARN_PRINTLN("Signal: 31/31 (Unknown - weak signal likely)");
        } else {
          STATUS_INFO("Signal: " + String(rssi) + "/31");
        }
        signalQuality = rssi;
        return rssi;
      }
    }
  }
  WARN_PRINTLN("[SIGNAL] Signal unknown or unavailable");
  signalQuality = 0;
  
  return 0;
}

String MQTTManager::detectSIMProvider() {
  DEBUG_PRINTLN("\n🔍 Detecting SIM provider...");
  String response = sendATCommand("AT+COPS?", 5000);
  
  if (response.indexOf("+COPS:") != -1) {
    int start = response.indexOf("\"");
    int end = response.indexOf("\"", start + 1);
    
    if (start != -1 && end != -1) {
      String operatorName = response.substring(start + 1, end);
      operatorName.toUpperCase();
      DEBUG_PRINTLN("Network: " + operatorName);
      
      if (operatorName.indexOf("BSNL") != -1) {
        STATUS_OK("Detected: BSNL");
        return "BSNL";
      } else if (operatorName.indexOf("JIO") != -1 || operatorName.indexOf("RJIL") != -1) {
        STATUS_OK("Detected: Jio");
        return "Jio";
      } else if (operatorName.indexOf("AIRTEL") != -1) {
        STATUS_OK("Detected: Airtel");
        return "Airtel";
      } else if (operatorName.indexOf("VODAFONE") != -1 || operatorName.indexOf("VI") != -1 || operatorName.indexOf("IDEA") != -1) {
        STATUS_OK("Detected: VI");
        return "VI";
      } else {
        WARN_PRINTLN("Unknown operator: " + operatorName);
        return operatorName;
      }
    }
  }
  
  STATUS_FAIL("Provider detection failed");
  return "Unknown";
}

void MQTTManager::autoConfigureAPN() {
  DEBUG_PRINTLN("\n⚙️ Auto-configuring APN...");
  
  String oldAPN = apn_name;
  
  String simProvider = detectSIMProvider();
  
  if (simProvider == "BSNL") {
    apn_name = "bsnlnet";
  } else if (simProvider == "Jio") {
    apn_name = "jionet";
  } else if (simProvider == "Airtel") {
    apn_name = "airtelgprs.com";
  } else if (simProvider == "VI") {
    apn_name = "portalnmms";
  } else {
    WARN_PRINTLN("Using default APN: " + apn_name);
    return;
  }
  
  if (apn_name != oldAPN) {
    STATUS_INFO("APN changed: " + oldAPN + " → " + apn_name);
  } else {
    DEBUG_PRINTLN("APN already set to: " + apn_name);
  }
}

void MQTTManager::checkSIMBalance() {
  DEBUG_PRINTLN("\n💰 Checking SIM balance...");
  
  String ussdCode = "";
  
  String simProvider = detectSIMProvider();
  
  if (simProvider == "BSNL") {
    ussdCode = "*124#";
  } else if (simProvider == "Jio") {
    ussdCode = "*333#";
  } else if (simProvider == "Airtel") {
    ussdCode = "*123#";
  } else if (simProvider == "VI") {
    ussdCode = "*199#";
  } else {
    WARN_PRINTLN("Balance check not supported for " + simProvider);
    return;
  }
  
  DEBUG_PRINTLN("Sending USSD: " + ussdCode);
  
  String command = "AT+CUSD=1,\"" + ussdCode + "\"";
  String response = sendATCommand(command, 15000);
  
  if (response.indexOf("+CUSD:") != -1) {
    int start = response.indexOf("\"");
    int end = response.indexOf("\"", start + 1);
    
    if (start != -1 && end != -1) {
      String balanceInfo = response.substring(start + 1, end);
      balanceInfo.replace("\\n", " ");
      balanceInfo.replace("\\r", "");
      balanceInfo.trim();
      
      if (balanceInfo.length() > 100) {
        balanceInfo = balanceInfo.substring(0, 97) + "...";
      }
      
      DEBUG_PRINTLN("Balance: " + balanceInfo);
    }
  }
}

void MQTTManager::displayModemStatus() {
  INFO_PRINTLN("\n╔═══════════════════════╗");
  INFO_PRINTLN("║   MODEM STATUS        ║");
  INFO_PRINTLN("╠═══════════════════════╣");
  INFO_PRINTLN("║ Ready:    " + String(modemReady ? "✅ YES" : "❌ NO ") + "       ║");
  INFO_PRINTLN("╚═══════════════════════╝");
  
  if (!modemReady) {
    WARN_PRINTLN("Check modem connections!");
  }
}

void MQTTManager::activatePDPContext() {
  if (!modemReady) return;
  
  DEBUG_PRINTLN("Setting APN...");
  sendATCommand("AT+QICSGP=1,1,\"" + apn_name + "\",\"\",\"\",1", 2000);
  
  sendATCommand("AT+QIDEACT=1", 5000);
  delay(1000);
  
  DEBUG_PRINTLN("Activating PDP context...");
  String response = sendATCommand("AT+QIACT=1", 15000);
  
  response = sendATCommand("AT+QIACT?", 2000);
  if (response.indexOf("+QIACT:") != -1) {
    int start = response.indexOf("\"") + 1;
    int end = response.indexOf("\"", start);
    modemIP = response.substring(start, end);
    
    if (modemIP != "0.0.0.0" && modemIP.length() > 7) {
      gprsConnected = true;
      STATUS_OK("PDP active, IP: " + modemIP);
    } else {
      STATUS_FAIL("No valid IP assigned");
      gprsConnected = false;
    }
  }
}

bool MQTTManager::checkGPRSStatus() {
  String response = sendATCommand("AT+QIACT?", 2000);
  if (response.indexOf("+QIACT:") != -1) {
    int start = response.indexOf("\"") + 1;
    int end = response.indexOf("\"", start);
    String ip = response.substring(start, end);
    return (ip != "0.0.0.0" && ip.length() > 7);
  }
  return false;
}

void MQTTManager::connectToMQTT() {
  connectionRetries++;
  
  if (!gprsConnected) {
    STATUS_FAIL("GPRS not connected, reactivating...");
    activatePDPContext();
    if (!gprsConnected) return;
  }
  
  DEBUG_PRINTLN("\nConfiguring MQTT...");
  
  sendATCommand("AT+QMTDISC=0", 2000);
  delay(100);
  sendATCommand("AT+QMTCLOSE=0", 2000);
  delay(100);
  
  sendATCommand("AT+QMTCFG=\"keepalive\",0,60", 2000);
  String cleanResp = sendATCommand("AT+QMTCFG=\"clean session\",0,0", 2000);
  if (cleanResp.indexOf("ERROR") != -1) {
    WARN_PRINTLN("Clean session not supported, skipping...");
  }
  sendATCommand("AT+QMTCFG=\"version\",0,4", 2000);
  
  DEBUG_PRINTLN("Opening MQTT socket...");
  String cmd = "AT+QMTOPEN=0,\"" + String(MQTT_SERVER) + "\"," + String(MQTT_PORT);
  modemSerial->println(cmd);
  
  unsigned long start = millis();
  bool socketOpened = false;
  while (millis() - start < 25000) {
    if (modemSerial->available()) {
      String msg = readResponse(500);
      DEBUG_PRINTLN("  << " + msg);
      if (msg.indexOf("+QMTOPEN: 0,0") != -1) {
        STATUS_OK("Socket opened successfully");
        socketOpened = true;
        break;
      } else if (msg.indexOf("+QMTOPEN: 0") != -1 && msg.indexOf("0,0") == -1) {
        STATUS_FAIL("Socket open failed: " + msg);
        return;
      }
    }
    delay(100);
  }
  
  if (!socketOpened) {
    WARN_PRINTLN("Socket open timeout");
    return;
  }
  
  delay(1000);
  
  DEBUG_PRINTLN("Connecting to MQTT broker...");
  cmd = "AT+QMTCONN=0,\"" + String(MQTT_CLIENT_ID) + "\"";
  modemSerial->println(cmd);
  
  start = millis();
  bool connected = false;
  while (millis() - start < 25000) {
    if (modemSerial->available()) {
      String msg = readResponse(500);
      DEBUG_PRINTLN("  << " + msg);
      if (msg.indexOf("+QMTCONN: 0,0,0") != -1) {
        mqttConnected = true;
        connectionRetries = 0;
        lastKeepalive = millis();
        INFO_PRINTLN("✅✅✅ Connected to AWS MQTT broker!");
        connected = true;
        break;
      } else if (msg.indexOf("+QMTCONN: 0") != -1 && msg.indexOf("0,0,0") == -1) {
        STATUS_FAIL("Connection failed: " + msg);
        return;
      }
    }
    delay(100);
  }
  
  if (!connected) {
    WARN_PRINTLN("Connection timeout");
    mqttConnected = false;
  }
}

void MQTTManager::disconnectMQTT() {
  if (!mqttConnected) {
    DEBUG_PRINTLN("[MQTT] Already disconnected");
    return;
  }
  
  DEBUG_PRINTLN("[MQTT] Disconnecting from broker...");
  String cmd = "AT+QMTDISC=0";
  modemSerial->println(cmd);
  
  unsigned long start = millis();
  while (millis() - start < 5000) {
    if (modemSerial->available()) {
      String msg = modemSerial->readStringUntil('\n');
      DEBUG_PRINTLN(msg);
      
      if (msg.indexOf("OK") != -1 || msg.indexOf("+QMTDISC") != -1) {
        STATUS_OK("MQTT disconnected");
        mqttConnected = false;
        return;
      }
    }
  }
  
  mqttConnected = false;
  WARN_PRINTLN("Disconnect timeout");
}

void MQTTManager::closeMQTTSocket() {
  DEBUG_PRINTLN("[MQTT] Closing socket...");
  String cmd = "AT+QMTCLOSE=0";
  modemSerial->println(cmd);
  
  unsigned long start = millis();
  while (millis() - start < 5000) {
    if (modemSerial->available()) {
      String msg = modemSerial->readStringUntil('\n');
      DEBUG_PRINTLN(msg);
      
      if (msg.indexOf("OK") != -1 || msg.indexOf("+QMTCLOSE") != -1) {
        STATUS_OK("MQTT socket closed");
        return;
      }
    }
  }
  
  WARN_PRINTLN("Socket close timeout");
}

void MQTTManager::publishModbusData(float reg1, float reg2, String timestamp) {
  if (!mqttConnected) {
    STATUS_FAIL("MQTT not connected - Cannot publish event");
    
    if (!gprsConnected && modemReady) {
      DEBUG_PRINTLN("   Trying GPRS activation...");
      activatePDPContext();
      if (gprsConnected) {
        DEBUG_PRINTLN("   Trying MQTT connection...");
        connectToMQTT();
      }
    }
    
    if (!mqttConnected) {
      DEBUG_PRINTLN("   MQTT publish skipped\n");
      return;
    }
  }
  
  INFO_PRINTLN("\n======================================");
  INFO_PRINTLN("   MQTT PUBLISHING TO AWS");
  INFO_PRINTLN("======================================");
  
  String payload = "{";
  payload += "\"device_id\":\"" + String(MQTT_CLIENT_ID) + "\",";
  payload += "\"register1\":" + String(reg1, 2) + ",";
  payload += "\"register2\":" + String(reg2, 2) + ",";
  payload += "\"timestamp\":\"" + timestamp + "\"";
  payload += "}";
  
  DEBUG_PRINTLN(getRTCTimestamp() + " - PUBLISHING TO AWS");
  DEBUG_PRINTLN("Server: " + String(MQTT_SERVER) + ":" + String(MQTT_PORT));
  DEBUG_PRINTLN("Topic: " + String(MQTT_TOPIC));
  DEBUG_PRINTLN("Data: " + payload);
  INFO_PRINTLN("--------------------------------------");
  
  String cmd = "AT+QMTPUB=0,0,0,0,\"" + String(MQTT_TOPIC) + "\"";
  
  while (modemSerial->available()) modemSerial->read();
  DEBUG_PRINTLN("Sending: " + cmd);
  modemSerial->println(cmd);
  
  unsigned long start = millis();
  bool gotPrompt = false;
  
  while (millis() - start < 3000) {
    if (modemSerial->available()) {
      char c = modemSerial->read();
      DEBUG_PRINT(String(c));
      if (c == '>') {
        gotPrompt = true;
        break;
      }
    }
    delay(10);
  }
  
  if (!gotPrompt) {
    STATUS_FAIL("No prompt received");
    return;
  }
  
  delay(50);
  while (modemSerial->available()) modemSerial->read();
  
  modemSerial->print(payload);
  
  delay(100);
  modemSerial->write(0x1A);
  DEBUG_PRINTLN("Sent Ctrl+Z");
  
  start = millis();
  while (millis() - start < 10000) {
    if (modemSerial->available()) {
      String response = "";
      while (modemSerial->available()) {
        char c = modemSerial->read();
        response += c;
        DEBUG_PRINT(String(c));
        delay(5);
      }
      if (response.indexOf("+QMTPUB: 0,0,0") != -1) {
        INFO_PRINTLN("✅✅✅ Published to AWS successfully!");
        lastKeepalive = millis();
        return;
      } else if (response.indexOf("ERROR") != -1) {
        STATUS_FAIL("Publish failed: " + response);
        mqttConnected = false;
        return;
      }
    }
    delay(100);
  }
  
  WARN_PRINTLN("Publish timeout");
  mqttConnected = false;
}

void MQTTManager::publishGPIOEvent(String deviceId, String status, String timestamp) {
  // Create JSON payload in the format: {"device_id": "str", "status": "str", "timestamp": "str"}
  String payload = "{";
  payload += "\"device_id\":\"" + deviceId + "\",";
  payload += "\"status\":\"" + status + "\",";
  payload += "\"timestamp\":\"" + timestamp + "\"";
  payload += "}";
  
  // Print JSON to Serial Monitor
  Serial.println("\n╔════════════════════════════════════════╗");
  Serial.println("║     MQTT PAYLOAD TO PUBLISH           ║");
  Serial.println("╠════════════════════════════════════════╣");
  Serial.println("║ Topic: " + String(MQTT_TOPIC));
  Serial.println("║ JSON Payload:");
  Serial.println("║ " + payload);
  Serial.println("╚════════════════════════════════════════╝\n");
  
  // Publish to MQTT
  publishToTopic(String(MQTT_TOPIC), payload);
}

void MQTTManager::publishToTopic(String topic, String payload) {
  if (!mqttConnected) {
    STATUS_FAIL("MQTT not connected - Cannot publish event");
    
    if (!gprsConnected && modemReady) {
      DEBUG_PRINTLN("   Trying GPRS activation...");
      activatePDPContext();
      if (gprsConnected) {
        DEBUG_PRINTLN("   Trying MQTT connection...");
        connectToMQTT();
      }
    }
    
    if (!mqttConnected) {
      DEBUG_PRINTLN("   MQTT publish skipped\n");
      return;
    }
  }
  
  INFO_PRINTLN("\n======================================");
  INFO_PRINTLN("   MQTT PUBLISHING");
  INFO_PRINTLN("======================================");
  
  DEBUG_PRINTLN("Topic: " + topic);
  DEBUG_PRINTLN("Payload Length: " + String(payload.length()) + " bytes");
  INFO_PRINTLN("📦 Payload: " + payload);
  INFO_PRINTLN("--------------------------------------");
  
  String cmd = "AT+QMTPUB=0,0,0,0,\"" + topic + "\"";
  
  while (modemSerial->available()) modemSerial->read();
  DEBUG_PRINTLN("Sending: " + cmd);
  modemSerial->println(cmd);
  
  unsigned long start = millis();
  bool gotPrompt = false;
  
  while (millis() - start < 3000) {
    if (modemSerial->available()) {
      char c = modemSerial->read();
      DEBUG_PRINT(String(c));
      if (c == '>') {
        gotPrompt = true;
        break;
      }
    }
    delay(10);
  }
  
  if (!gotPrompt) {
    STATUS_FAIL("No prompt received");
    return;
  }
  
  delay(50);
  while (modemSerial->available()) modemSerial->read();
  
  modemSerial->print(payload);
  
  delay(100);
  modemSerial->write(0x1A);
  DEBUG_PRINTLN("Sent Ctrl+Z");
  
  start = millis();
  while (millis() - start < 10000) {
    if (modemSerial->available()) {
      String response = "";
      while (modemSerial->available()) {
        char c = modemSerial->read();
        response += c;
        DEBUG_PRINT(String(c));
        delay(5);
      }
      if (response.indexOf("+QMTPUB: 0,0,0") != -1) {
        INFO_PRINTLN("✅✅✅ Published successfully!");
        lastKeepalive = millis();
        return;
      } else if (response.indexOf("ERROR") != -1) {
        STATUS_FAIL("Publish failed: " + response);
        mqttConnected = false;
        return;
      }
    }
    delay(100);
  }
  
  WARN_PRINTLN("Publish timeout");
  mqttConnected = false;
}

void MQTTManager::sendKeepalive() {
  if (!mqttConnected) return;
  
  DEBUG_PRINTLN("Sending MQTT PINGREQ for keepalive...");
  
  String response = sendATCommand("AT+QMTPING=0", 5000);
  
  if (response.indexOf("OK") != -1) {
    STATUS_OK("Keepalive sent");
    lastKeepalive = millis();
  } else {
    WARN_PRINTLN("Keepalive failed, checking connection...");
    mqttConnected = false;
  }
}

void MQTTManager::checkMQTTConnectionStatus() {
  if (!mqttConnected) return;
  
  DEBUG_PRINTLN("Checking MQTT connection status...");
  
  String response = sendATCommand("AT+QMTCONN?", 2000);
  
  if (response.indexOf("+QMTCONN: 0,0,0") == -1) {
    WARN_PRINTLN("MQTT connection lost");
    mqttConnected = false;
  } else {
    DEBUG_PRINTLN("MQTT connection active");
  }
}

String MQTTManager::getRTCTimestamp() {
  if (!rtcReady || !rtc) return "00:00:00";
  
  DateTime now = rtc->now();
  char timestamp[16];
  sprintf(timestamp, "%02d:%02d:%02d", now.hour(), now.minute(), now.second());
  return String(timestamp);
}

String MQTTManager::getRTCDate() {
  if (!rtcReady || !rtc) return "0000-00-00";
  
  DateTime now = rtc->now();
  char date[16];
  sprintf(date, "%04d-%02d-%02d", now.year(), now.month(), now.day());
  return String(date);
}

bool MQTTManager::isModemReady() const {
  return modemReady;
}

bool MQTTManager::isGPRSConnected() const {
  return gprsConnected;
}

bool MQTTManager::isMQTTConnected() const {
  return mqttConnected;
}

bool MQTTManager::isSIMReady() const {
  return simReady;
}

bool MQTTManager::isNetworkRegistered() const {
  return networkRegistered;
}

int MQTTManager::getSignalQualityValue() const {
  return signalQuality;
}

String MQTTManager::getModemIP() const {
  return modemIP;
}

String MQTTManager::getSIMProvider() const {
  return simProvider;
}

String MQTTManager::getAPN() const {
  return apn_name;
}

void MQTTManager::setAPN(String newAPN) {
  apn_name = newAPN;
}
