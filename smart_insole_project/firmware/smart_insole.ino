/**
 * ============================================================
 * SMART INSOLE FIRMWARE — ESP32
 * ============================================================
 * Hardware:
 *   - ESP32 Dev Module
 *   - 4x FSR (Force Sensitive Resistor) sensors
 *     • Heel        → GPIO 34 (ADC1_CH6)
 *     • Forefoot-L  → GPIO 35 (ADC1_CH7)
 *     • Forefoot-R  → GPIO 32 (ADC1_CH4)
 *     • Toe         → GPIO 33 (ADC1_CH5)
 *   - NEO-6M GPS Module → Serial2 (RX=16, TX=17)
 *
 * Libraries (install via Arduino Library Manager):
 *   - ArduinoJson   v6.x   by Benoit Blanchon
 *   - TinyGPSPlus          by Mikal Hart
 *   - ESP32 BLE Arduino    (included with ESP32 board package)
 *
 * BLE Payload (JSON notified every 100 ms / 10 Hz):
 *   {
 *     "h":   0-4095,   // Heel pressure
 *     "fl":  0-4095,   // Forefoot Left
 *     "fr":  0-4095,   // Forefoot Right
 *     "t":   0-4095,   // Toe
 *     "pace": min/km,  // Current running pace (0 = stopped)
 *     "dist": km,      // Cumulative distance
 *     "lat": decimal,  // GPS latitude
 *     "lng": decimal,  // GPS longitude
 *     "spd": km/h      // GPS speed
 *   }
 * ============================================================
 */

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <TinyGPSPlus.h>
#include <HardwareSerial.h>

// ─── FSR Analog Pins (ADC1 only — BLE disables ADC2) ────────
#define FSR_HEEL        34
#define FSR_FOREFOOT_L  35
#define FSR_FOREFOOT_R  32
#define FSR_TOE         33

// ─── GPS Serial2 (NEO-6M) ───────────────────────────────────
#define GPS_RX_PIN   16
#define GPS_TX_PIN   17
#define GPS_BAUD   9600

// ─── BLE UUIDs (generate fresh ones for your own product) ───
#define SERVICE_UUID      "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_UUID_NOTIFY  "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// ─── Timing ─────────────────────────────────────────────────
#define SAMPLE_MS  100   // 10 Hz notification rate

// ─── Globals ────────────────────────────────────────────────
TinyGPSPlus       gps;
HardwareSerial    gpsSerial(2);

BLEServer*         pServer     = nullptr;
BLECharacteristic* pNotifyChar = nullptr;
bool deviceConnected = false;
bool oldConnected    = false;

double totalDistKm = 0.0;
double prevLat = 0.0, prevLng = 0.0;
unsigned long lastSampleMs = 0;

// ─── BLE Server Callbacks ───────────────────────────────────
class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    deviceConnected = true;
    Serial.println("[BLE] Client connected");
  }
  void onDisconnect(BLEServer*) override {
    deviceConnected = false;
    Serial.println("[BLE] Client disconnected");
  }
};

// ─── ADC Helper: 4x oversampling to reduce noise ────────────
int readFSR(uint8_t pin) {
  long sum = 0;
  for (int i = 0; i < 4; i++) { sum += analogRead(pin); delayMicroseconds(50); }
  return (int)(sum >> 2);
}

// ─── Speed (km/h) → Pace (min/km); returns 0 if stationary ─
float speedToPace(double kmh) {
  return (kmh < 0.5) ? 0.0f : (float)(60.0 / kmh);
}

// ─── Setup ──────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  Serial.println("[BOOT] SmartInsole Firmware v1.0");

  // ADC config — 12-bit, 0–3.3 V full range
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  pinMode(FSR_HEEL,       INPUT);
  pinMode(FSR_FOREFOOT_L, INPUT);
  pinMode(FSR_FOREFOOT_R, INPUT);
  pinMode(FSR_TOE,        INPUT);

  // GPS UART
  gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  Serial.println("[GPS] UART2 ready");

  // BLE init
  BLEDevice::init("SmartInsole_01");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCB());

  BLEService* svc = pServer->createService(SERVICE_UUID);
  pNotifyChar = svc->createCharacteristic(CHAR_UUID_NOTIFY,
                  BLECharacteristic::PROPERTY_NOTIFY);
  pNotifyChar->addDescriptor(new BLE2902());
  svc->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  BLEDevice::startAdvertising();
  Serial.println("[BLE] Advertising as 'SmartInsole_01'");

  lastSampleMs = millis();
}

// ─── Main Loop ──────────────────────────────────────────────
void loop() {
  // Continuously feed GPS NMEA sentences
  while (gpsSerial.available()) gps.encode(gpsSerial.read());

  unsigned long now = millis();
  if (now - lastSampleMs < SAMPLE_MS) return;
  lastSampleMs = now;

  // Read FSR sensors
  int heel      = readFSR(FSR_HEEL);
  int forefootL = readFSR(FSR_FOREFOOT_L);
  int forefootR = readFSR(FSR_FOREFOOT_R);
  int toe       = readFSR(FSR_TOE);

  // Read GPS
  double lat = 0.0, lng = 0.0, speedKmh = 0.0;
  if (gps.location.isValid()) {
    lat = gps.location.lat();
    lng = gps.location.lng();
    if (prevLat != 0.0) {
      double d = TinyGPSPlus::distanceBetween(prevLat, prevLng, lat, lng) / 1000.0;
      if (d > 0.001) totalDistKm += d;   // ignore sub-1m GPS jitter
    }
    prevLat = lat; prevLng = lng;
  }
  if (gps.speed.isValid()) speedKmh = gps.speed.kmph();
  float pace = speedToPace(speedKmh);

  // Build JSON payload
  StaticJsonDocument<256> doc;
  doc["h"]    = heel;
  doc["fl"]   = forefootL;
  doc["fr"]   = forefootR;
  doc["t"]    = toe;
  doc["pace"] = round(pace * 100.0f) / 100.0f;
  doc["dist"] = round(totalDistKm * 1000.0) / 1000.0;
  doc["lat"]  = lat;
  doc["lng"]  = lng;
  doc["spd"]  = round(speedKmh * 10.0) / 10.0;

  char buf[256];
  serializeJson(doc, buf);

  // Notify BLE client
  if (deviceConnected) {
    pNotifyChar->setValue(buf);
    pNotifyChar->notify();
  }

  // Reconnection handling
  if (!deviceConnected && oldConnected) {
    delay(300);
    pServer->startAdvertising();
    oldConnected = false;
  }
  if (deviceConnected && !oldConnected) oldConnected = true;

  // Debug print every 1 s (10 samples)
  static uint8_t dbgCnt = 0;
  if (++dbgCnt >= 10) {
    dbgCnt = 0;
    Serial.printf("[DATA] H:%4d FL:%4d FR:%4d T:%4d | pace:%.2f | dist:%.3f km | %.6f,%.6f\n",
                  heel, forefootL, forefootR, toe, pace, totalDistKm, lat, lng);
  }
}
