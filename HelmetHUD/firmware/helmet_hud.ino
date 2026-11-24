// ============================================================
//  HELMET HUD — Ruroc Atlas 4 visor display
//  ESP32 + 1.3" SH1106 OLED, BLE client to DukePulse (KTM)
//
//  Wiring (common ESP32 DevKit v1):
//    OLED VCC -> 3V3   OLED GND -> GND
//    OLED SCL -> GPIO22  OLED SDA -> GPIO21
//    Shift LED (optional WS2812) -> GPIO13 (3 LEDs near visor top)
//    Button GPIO0 (BOOT) = brightness toggle
//
//  Board: "ESP32 Dev Module" @ 240MHz
//  Libs: NimBLE-Arduino, Adafruit SH110X (or U8g2), Adafruit NeoPixel
// ============================================================

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Wire.h>
#include <Adafruit_SH110X.h>
#include <Adafruit_NeoPixel.h>

// ---- pins ----
#define SDA_PIN 21
#define SCL_PIN 22
#define LED_PIN 13
#define BTN_PIN 0

// ---- DukePulse service (matches DukePulseApp.swift) ----
static const char *HUD_SERVICE = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
static const char *HUD_CHAR    = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

// ---- display ----
Adafruit_SH1106G oled(128, 64, &Wire, -1);
#define NUM_LEDS 3
Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

// ---- telemetry state ----
struct Hud {
  float speed = 0;      // km/h
  float rpm = 0;
  float coolant = 0;    // degC
  float throttle = 0;   // 0..100
  float battery = 12.6;
  float shiftAt = 8500; // rpm redline marker (Duke 125 ~9500 hard, 8500 shift)
  bool  connected = false;
  unsigned long lastPacket = 0;
} hud;

int brightness = 200;   // 0..255
bool dimmed = false;
bool ledOn = true;

// shift thresholds (percent of shiftAt)
#define WARN_PCT 0.85f
#define RED_PCT  0.96f

static NimBLEClient *client = nullptr;
static NimBLERemoteCharacteristic *hudChar = nullptr;
static bool shouldConnect = true;

// ---- packet decode: 6 little-endian floats, 24 bytes:
//  wire format from DukePulse: "<ffffff" (speed, rpm, coolant, throttle, battery, shiftAt)
void decodePacket(const uint8_t *data, size_t len) {
  if (len < 24) return;
  float f[6];
  memcpy(f, data, 24);
  hud.speed    = f[0];
  hud.rpm      = f[1];
  hud.coolant  = f[2];
  hud.throttle = f[3];
  hud.battery  = f[4];
  if (f[5] > 1000) hud.shiftAt = f[5];   // guard against corrupt values
  hud.lastPacket = millis();
}

class HudCallbacks : public NimBLEClientCallbacks {
  void onConnect(NimBLEClient *c) override {
    hud.connected = true;
    digitalWrite(LED_BUILTIN, HIGH);
  }
  void onDisconnect(NimBLEClient *c, int reason) override {
    hud.connected = false;
    digitalWrite(LED_BUILTIN, LOW);
    shouldConnect = true;  // rescan loop picks it back up
  }
};

void notifyCB(NimBLERemoteCharacteristic *, uint8_t *data, size_t len, bool) {
  decodePacket(data, len);
}

// ---- scan + connect ----
bool connectToHud() {
  NimBLEScan *scan = NimBLEDevice::getScan();
  scan->setActiveScan(true);
  NimBLEScanResults res = scan->start(4, false);
  NimBLEAdvertisedDevice *dev = nullptr;
  for (int i = 0; i < res.getCount(); i++) {
    NimBLEAdvertisedDevice *d = res.getDevice(i);
    if (d->isAdvertisingService(NimBLEUUID(HUD_SERVICE))) { dev = d; break; }
  }
  if (!dev) return false;

  client = NimBLEDevice::createClient();
  client->setClientCallbacks(new HudCallbacks(), true);
  if (!client->connect(dev)) return false;

  NimBLERemoteService *svc = client->getService(NimBLEUUID(HUD_SERVICE));
  if (!svc) { client->disconnect(); return false; }
  hudChar = svc->getCharacteristic(NimBLEUUID(HUD_CHAR));
  if (hudChar && hudChar->canNotify()) {
    hudChar->subscribe(true, notifyCB);
    return true;
  }
  return false;
}

// ---- rendering ----
void render() {
  oled.clearDisplay();
  oled.setTextColor(SH110X_WHITE);

  // top bar: link + coolant
  oled.setTextSize(1);
  oled.setCursor(0, 0);
  oled.print(hud.connected ? "LINK" : "SCANNING");
  oled.setCursor(84, 0);
  char tmp[16];
  snprintf(tmp, sizeof(tmp), "%.0fC", hud.coolant);
  oled.print(tmp);

  // speed — giant
  oled.setTextSize(4);
  snprintf(tmp, sizeof(tmp), "%3.0f", hud.speed);
  int w = strlen(tmp) * 24;
  oled.setCursor(max(0, (128 - w) / 2), 16);
  oled.print(tmp);

  // unit
  oled.setTextSize(1);
  oled.setCursor(96, 52);
  oled.print("km/h");

  // rpm bar (bottom strip)
  int rpmPct = constrain(map(hud.rpm, 0, hud.shiftAt, 0, 124), 0, 124);
  oled.drawRect(0, 56, 128, 8, SH110X_WHITE);
  oled.fillRect(2, 58, rpmPct, 4, SH110X_WHITE);
  // redline tick
  int tick = map(hud.shiftAt * WARN_PCT, 0, hud.shiftAt, 0, 124);
  oled.fillRect(tick, 56, 2, 8, SH110X_WHITE);

  oled.display();
}

void renderShiftLeds() {
  if (!ledOn) { strip.clear(); strip.show(); return; }
  float pct = hud.rpm / hud.shiftAt;
  uint32_t col = strip.Color(0, 40, 0);                 // dim green cruise
  if (!hud.connected)      col = strip.Color(0, 0, 25);  // deep blue = searching
  else if (pct >= RED_PCT) col = strip.Color(255, 0, 0); // red = SHIFT
  else if (pct >= WARN_PCT) col = strip.Color(255, 120, 0); // amber = close
  for (int i = 0; i < NUM_LEDS; i++) strip.setPixelColor(i, col);
  strip.show();
}

// ---- button: cycle brightness / long press toggles LEDs ----
unsigned long btnDown = 0;
void pollButton() {
  bool pressed = digitalRead(BTN_PIN) == LOW;
  if (pressed && btnDown == 0) btnDown = millis();
  if (!pressed && btnDown > 0) {
    unsigned long dur = millis() - btnDown;
    btnDown = 0;
    if (dur > 800) { ledOn = !ledOn; }                    // long press: LED strip on/off
    else {
      dimmed = !dimmed;
      brightness = dimmed ? 40 : 200;
      oled.setBrightness(brightness);
    }
  }
}

void setup() {
  pinMode(BTN_PIN, INPUT_PULLUP);
  pinMode(LED_BUILTIN, OUTPUT);
  Wire.begin(SDA_PIN, SCL_PIN);

  if (!oled.begin(0x3C, true)) {
    // no display attached — loop still serves packets (headless test mode)
  }
  oled.setBrightness(brightness);
  oled.clearDisplay();
  oled.setTextSize(1);
  oled.setCursor(0, 24);
  oled.print("HELM HUD BOOTING");
  oled.display();

  strip.begin();
  strip.setBrightness(120);
  strip.show();

  NimBLEDevice::init("HelmHud");
  NimBLEDevice::setPower(3);
  shouldConnect = true;
}

void loop() {
  pollButton();

  if (!hud.connected && shouldConnect) {
    shouldConnect = false;
    connectToHud();
    if (!hud.connected) { delay(1500); shouldConnect = true; }
  }

  // stale-link watchdog: if no packet for 15s, force rescan
  if (hud.connected && millis() - hud.lastPacket > 15000) {
    if (client) client->disconnect();
    shouldConnect = true;
  }

  render();
  renderShiftLeds();
  delay(80);   // ~12fps, plenty for speed + saves the OLED
}