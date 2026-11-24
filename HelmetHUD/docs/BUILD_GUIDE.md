# HELM HUD — cheap glanceable display for the Ruroc Atlas 4

A tiny BLE-paired screen mounted inside the helmet, fed live telemetry from
**DukePulse** (your KTM OBD2 app). One glance: speed, RPM shift-light bar,
coolant, battery — no phone mount needed on the bars.

```
[ DukePulse on iPhone ] --BLE--> [ ESP32 + OLED inside helmet ]
        reads OBD2                        shows glance HUD
```

## Why this works cheap
- ESP32 DevKit: ~£6-8 (has BLE built in — no extra radio)
- 1.3" SH1106 OLED: ~£6 (I2C, 2 wires, sunlight-readable enough at eye glance)
- Optional shift-light LED strip: ~£3
- 18650 + holder or reuse any USB power bank: ~£5
- **Total: ~£20-25** vs £300+ commercial helmet HUDs

---

## Parts list (buy on Amazon/AliExpress)

| Part | Est. cost | Notes |
|---|---|---|
| ESP32 DevKit v1 (30-pin) | £7 | any ESP32 WROOM dev board works |
| 1.3" SH1106 OLED (I2C, 128x64) | £6 | 4-pin `VCC GND SCL SDA` |
| WS2812 LED strip, 3 LEDs | £3 | optional — shift light |
| Small slide/tact button | £0.50 | brightness toggle |
| USB power bank (slim) or 18650 + TP4056 | £5 | 5-10h runtime typical |
| Hook-up wire + heatshrink | £2 | |
| **Total** | **~£23** | |

## Wiring (4 wires to the OLED)

```
ESP32 3V3  ----  OLED VCC
ESP32 GND  ----  OLED GND
ESP32 22   ----  OLED SCL
ESP32 21   ----  OLED SDA
ESP32 13   ----  WS2812 DIN (optional)
ESP32 GND  ----  WS2812 GND + button to GPIO0
```

## Firmware
`firmware/helmet_hud.ino` — Arduino IDE:
1. Board: **ESP32 Dev Module** (240MHz)
2. Libraries: **NimBLE-Arduino**, **Adafruit SH110X**, **Adafruit NeoPixel**
3. Flash over USB, done in ~2 min

## Mounting in the Ruroc Atlas 4
The Atlas 4 has space behind the visor brow (where the Shockwave audio
module sits). The sweet spot: mount the OLED at the **top edge of the visor
interior**, angled down ~15deg, so it reads in the lower peripheral vision
without blocking the road view. Use VHB tape + a small 3D-printed bracket
(or Sugru). The ESP32 + battery tuck into the rear neck roll pocket.

> **Visibility choice:** monochrome OLED is the honest cheap option. It's
> legible at a glance in shade/overcast; direct sunlight washes it a bit —
> raise brightness with the button (3 levels).

## Buttons
- **Short press**: brightness toggle (high / night)
- **Long press (0.8s)**: shift-light LEDs on/off

## LED behaviour (shift light)
- **Green** = cruising (below 85% of redline)
- **Amber** = closing (85-96%)
- **Red** = SHIFT NOW (>=96%)
- **Deep blue** = searching for DukePulse link

## App side
DukePulse v1.1.2 adds a **HELM tab** — flip "Helmet Link ON" and the app
advertises the HUD service; the helmet auto-pairs within ~5s. Set the
redline marker there (Duke 125 stock = ~8500 rpm shift point).

## Power notes
ESP32 ~80mA + OLED ~20mA + LEDs peak 60mA ≈ 160mA worst case → a 2500mAh
bank runs **15h+**. Idle OLED dim (night mode) drops draw to ~40mA total.