// ============================================================================
// ADSCREEN Command Center v3.0
// Arduino Mega 2560 + VMA412 2.8" TFT Touch Shield (MCUFRIEND_kbv)
// Portrait Mode (240x320) — English Only
//
// Features:
//   - Portrait orientation matching physical display
//   - Delta drawing (flicker-free, NO fillScreen in loop)
//   - ArduinoJson two-way JSON over Serial with < > markers
//   - Touch with mandatory pin restore
//   - 4 tabs: Dashboard, Server, Network, Settings
//   - Visual bars, status dots, color-coded metrics
// ============================================================================

#include <Adafruit_GFX.h>
#include <MCUFRIEND_kbv.h>
#include <TouchScreen.h>
#include <ArduinoJson.h>
#include <EEPROM.h>

MCUFRIEND_kbv tft;

// ============================================================================
// TOUCH — VMA412 / MCUFRIEND Shield
// ============================================================================
#define YP A3
#define XM A2
#define YM 9
#define XP 8
#define TS_LEFT   150   // rawY (p.y) at screen x=0
#define TS_RT     920   // rawY (p.y) at screen x=SCR_W
#define TS_TOP    940   // rawX (p.x) at screen y=0  — inverted for landscape R1
#define TS_BOT    120   // rawX (p.x) at screen y=SCR_H
#define MINPRESSURE 10
#define MAXPRESSURE 1200
TouchScreen ts = TouchScreen(XP, YP, XM, YM, 300);

// Persistent touch calibration defaults (factory)
#define TS_LEFT_DFT  150   // rawY at screen x=0
#define TS_RT_DFT    920   // rawY at screen x=SCR_W
#define TS_TOP_DFT   940   // rawX at screen y=0 (inverted)
#define TS_BOT_DFT   120   // rawX at screen y=SCR_H

struct TouchCal {
  uint16_t magic;
  int16_t left;
  int16_t right;
  int16_t top;
  int16_t bottom;
};

#define CAL_MAGIC 0xCA1E
TouchCal gCal = { CAL_MAGIC, TS_LEFT_DFT, TS_RT_DFT, TS_TOP_DFT, TS_BOT_DFT };
const int CAL_EEPROM_ADDR = 0;
#define CALIBRATE_EVERY_BOOT 1

// ============================================================================
// COLORS (RGB565)
// ============================================================================
#define C_BG       0x0000
#define C_PANEL    0x10A2
#define C_CYAN     0x07FF
#define C_MAGENTA  0xF81F
#define C_ORANGE   0xFD20
#define C_GREEN    0x07E0
#define C_RED      0xF800
#define C_YELLOW   0xFFE0
#define C_WHITE    0xFFFF
#define C_GREY     0x8410
#define C_DKGREY   0x4208
#define C_BAR_BG   0x18E3
#define C_TAB_ON   0x001F
#define C_TAB_OFF  0x10A2

// ============================================================================
// LANDSCAPE LAYOUT (320 wide x 240 tall)
// ============================================================================
#define SCR_W 320
#define SCR_H 240
#define TAB_H  26
#define NAV_H  28
#define CY     (TAB_H + 2)   // Content Y start
#define TAB_COUNT 4

#define TAB_DASH   0
#define TAB_SRV    1
#define TAB_NET    2
#define TAB_SET    3

// Server buttons: 2 columns, 3 rows
#define SB_W  152
#define SB_H   34
#define SB_X1   4
#define SB_X2 164
#define SB_Y0  (CY + 4)
#define SB_GAP  40

// ============================================================================
// STATE
// ============================================================================
uint8_t  curTab = TAB_DASH;
uint8_t  drawnTab = 255;
unsigned long lastTouchMs = 0;
unsigned long lastDataMs  = 0;
bool sleeping   = false;
bool piOffline  = false;          // true when Pi stops sending data
unsigned long offlineSince = 0;   // millis() when Pi was last seen online
#define OFFLINE_TIMEOUT_MS  8000UL  // show offline screen after 8s without data
#define SLEEP_MS            300000UL
#define DEBOUNCE_MS         250
#define RECONNECT_POLL_MS   5000UL  // request_data interval while Pi is offline
unsigned long lastReconnectMs = 0;

// ============================================================================
// SERIAL
// ============================================================================
#define SBUF_SZ 384
char  sBuf[SBUF_SZ];
uint16_t sIdx = 0;
bool inMsg = false;
bool msgRdy = false;

// ============================================================================
// CACHED VALUES (delta drawing)
// ============================================================================
int16_t p_cpu = -1, p_ram = -1, p_temp = -1, p_disk = -1;
char p_wifi[8] = "", p_docker[8] = "", p_up[16] = "", p_host[16] = "";
int16_t p_http = -1, p_ssl = -1, p_cont = -1;
char p_nginx[8] = "";
char p_ip[20] = "", p_pip[20] = "", p_ping[12] = "", p_ssh[8] = "";
int16_t p_rx = -1, p_tx = -1;

// ============================================================================
// TOUCH CALIBRATION
// ============================================================================
bool loadCalibration() {
  TouchCal tmp;
  EEPROM.get(CAL_EEPROM_ADDR, tmp);
  if (tmp.magic == CAL_MAGIC && tmp.left != tmp.right && tmp.top != tmp.bottom) {
    gCal = tmp;
    return true;
  }
  return false;
}

void saveCalibration() {
  gCal.magic = CAL_MAGIC;
  EEPROM.put(CAL_EEPROM_ADDR, gCal);
}

void waitTouchRelease() {
  while (true) {
    TSPoint p = ts.getPoint();
    pinMode(YP, OUTPUT);
    pinMode(XM, OUTPUT);
    if (!(p.z >= MINPRESSURE && p.z <= MAXPRESSURE)) {
      break;
    }
    delay(10);
  }
}

bool readRawTouchPoint(int16_t &rawX, int16_t &rawY, uint32_t timeoutMs) {
  unsigned long start = millis();
  while (millis() - start < timeoutMs) {
    TSPoint p = ts.getPoint();
    pinMode(YP, OUTPUT);
    pinMode(XM, OUTPUT);
    if (p.z >= MINPRESSURE && p.z <= MAXPRESSURE) {
      rawX = p.x;
      rawY = p.y;
      waitTouchRelease();
      delay(120);
      return true;
    }
    delay(10);
  }
  return false;
}

void drawCalTarget(int16_t x, int16_t y, const __FlashStringHelper *label) {
  tft.fillScreen(C_BG);
  tft.setTextSize(1);
  tft.setTextColor(C_WHITE);
  tft.setCursor(20, 20);
  tft.print(F("Touch target:"));
  tft.setCursor(20, 36);
  tft.print(label);
  tft.setCursor(20, 52);
  tft.setTextColor(C_GREY);
  tft.print(F("Tap once, then release"));
  tft.drawLine(x - 12, y, x + 12, y, C_YELLOW);
  tft.drawLine(x, y - 12, x, y + 12, C_YELLOW);
  tft.drawCircle(x, y, 10, C_YELLOW);
}

void showToast(const __FlashStringHelper *msg, uint16_t bg, uint16_t fg) {
  tft.fillRoundRect(40, 88, 240, 36, 8, bg);
  tft.setCursor(52, 102);
  tft.setTextColor(fg);
  tft.setTextSize(1);
  tft.print(msg);
}

bool runTouchCalibration() {
  int16_t tlx, tly, trx, tryy, blx, bly, brx, bry;
  const int16_t xL = 18;
  const int16_t xR = SCR_W - 18;
  const int16_t yT = 44;
  const int16_t yB = SCR_H - 18;

  waitTouchRelease();

  drawCalTarget(xL, yT, F("Top Left"));
  if (!readRawTouchPoint(tlx, tly, 20000)) return false;

  drawCalTarget(xR, yT, F("Top Right"));
  if (!readRawTouchPoint(trx, tryy, 20000)) return false;

  drawCalTarget(xL, yB, F("Bottom Left"));
  if (!readRawTouchPoint(blx, bly, 20000)) return false;

  drawCalTarget(xR, yB, F("Bottom Right"));
  if (!readRawTouchPoint(brx, bry, 20000)) return false;

  // Landscape R1: p.y (rawY) varies with screen X; p.x (rawX) varies with screen Y (inverted)
  int32_t rawYAtXL = ((int32_t)tly  + (int32_t)bly)  / 2;  // avg rawY at screen x=xL
  int32_t rawYAtXR = ((int32_t)tryy + (int32_t)bry)  / 2;  // avg rawY at screen x=xR
  int32_t rawXAtYT = ((int32_t)tlx  + (int32_t)trx)  / 2;  // avg rawX at screen y=yT
  int32_t rawXAtYB = ((int32_t)blx  + (int32_t)brx)  / 2;  // avg rawX at screen y=yB

  int32_t dx = (int32_t)xR - (int32_t)xL;
  int32_t dy = (int32_t)yB - (int32_t)yT;
  if (dx == 0 || dy == 0) return false;

  int32_t dRawY = rawYAtXR - rawYAtXL;  // rawY change per screen X (positive)
  int32_t dRawX = rawXAtYB - rawXAtYT;  // rawX change per screen Y (negative = inverted)

  // gCal.left/right = rawY extrapolated to screen x=0 and x=SCR_W
  int32_t calLeft   = rawYAtXL - ((int32_t)xL        * dRawY) / dx;
  int32_t calRight  = rawYAtXL + ((int32_t)(SCR_W - xL) * dRawY) / dx;

  // gCal.top/bottom = rawX extrapolated to screen y=0 and y=SCR_H
  // Due to inversion, calTop > calBottom (top ~940, bottom ~120)
  int32_t calTop    = rawXAtYT - ((int32_t)yT        * dRawX) / dy;
  int32_t calBottom = rawXAtYT + ((int32_t)(SCR_H - yT) * dRawX) / dy;

  gCal.left   = (int16_t)calLeft;
  gCal.right  = (int16_t)calRight;
  gCal.top    = (int16_t)calTop;
  gCal.bottom = (int16_t)calBottom;

  if (gCal.top == gCal.bottom || gCal.left == gCal.right) {
    return false;
  }

  saveCalibration();
  tft.fillScreen(C_BG);
  showToast(F("Calibration Saved"), C_GREEN, C_BG);
  delay(900);
  return true;
}

void getMappedTouch(int16_t rawX, int16_t rawY, int16_t &px, int16_t &py) {
  // Landscape R1: p.y (rawY) -> screen X;  p.x (rawX) -> screen Y (inverted via top>bottom)
  px = map(rawY, gCal.left, gCal.right, 0, SCR_W);
  py = map(rawX, gCal.top, gCal.bottom, 0, SCR_H);
  px = constrain(px, 0, SCR_W - 1);
  py = constrain(py, 0, SCR_H - 1);
}

// ============================================================================
// DRAWING HELPERS
// ============================================================================

void drawBar(int16_t x, int16_t y, int16_t w, int16_t h,
             int16_t newP, int16_t oldP, uint16_t fg) {
  newP = constrain(newP, 0, 100);
  int16_t nf = (int32_t)(w - 2) * newP / 100;
  int16_t of = (oldP < 0) ? 0 : (int32_t)(w - 2) * constrain(oldP, 0, 100) / 100;
  if (oldP < 0) {
    tft.drawRect(x, y, w, h, C_DKGREY);
    tft.fillRect(x+1, y+1, w-2, h-2, C_BAR_BG);
    if (nf > 0) tft.fillRect(x+1, y+1, nf, h-2, fg);
  } else if (nf > of) {
    tft.fillRect(x+1+of, y+1, nf-of, h-2, fg);
  } else if (nf < of) {
    tft.fillRect(x+1+nf, y+1, of-nf, h-2, C_BAR_BG);
  }
}

void drawVal(int16_t x, int16_t y, int16_t cw, int16_t ch,
             const char* t, uint16_t col, uint8_t sz = 1) {
  tft.fillRect(x, y, cw, ch, C_BG);
  tft.setCursor(x, y); tft.setTextColor(col); tft.setTextSize(sz);
  tft.print(t);
}

void drawValP(int16_t x, int16_t y, int16_t cw, int16_t ch,
              const char* t, uint16_t col, uint16_t panelCol, uint8_t sz = 1) {
  tft.fillRect(x, y, cw, ch, panelCol);
  tft.setCursor(x+4, y+2); tft.setTextColor(col); tft.setTextSize(sz);
  tft.print(t);
}

void drawBtn(int16_t x, int16_t y, int16_t w, int16_t h,
             const __FlashStringHelper* label, uint16_t bg, uint16_t fg) {
  tft.fillRoundRect(x, y, w, h, 5, bg);
  tft.drawRoundRect(x, y, w, h, 5, C_WHITE);
  String s(label);
  int16_t tw = s.length() * 6;
  tft.setCursor(x + (w - tw) / 2, y + (h - 8) / 2);
  tft.setTextColor(fg); tft.setTextSize(1);
  tft.print(label);
}

void flashBtn(int16_t x, int16_t y, int16_t w, int16_t h,
              const __FlashStringHelper* label, uint16_t bg) {
  tft.fillRoundRect(x, y, w, h, 5, C_WHITE);
  String s(label);
  int16_t tw = s.length() * 6;
  tft.setCursor(x + (w - tw) / 2, y + (h - 8) / 2);
  tft.setTextColor(bg); tft.setTextSize(1);
  tft.print(label);
  delay(120);
  drawBtn(x, y, w, h, label, bg, C_WHITE);
}

void drawDot(int16_t x, int16_t y, bool ok) {
  tft.fillCircle(x, y, 5, ok ? C_GREEN : C_RED);
}

// ============================================================================
// TAB BAR
// ============================================================================
static const char PROGMEM t0[] = "DASH";
static const char PROGMEM t1[] = "SRV";
static const char PROGMEM t2[] = "NET";
static const char PROGMEM t3[] = "SET";
static const char* const tabLbl[4] PROGMEM = { t0, t1, t2, t3 };

void drawBottomNav() {
  int16_t y = SCR_H - NAV_H;
  int16_t tw = SCR_W / TAB_COUNT;
  tft.drawFastHLine(0, y - 1, SCR_W, C_DKGREY);
  for (uint8_t i = 0; i < TAB_COUNT; i++) {
    uint16_t bg = (i == curTab) ? C_TAB_ON : C_TAB_OFF;
    uint16_t fg = (i == curTab) ? C_WHITE  : C_GREY;
    tft.fillRect(i * tw, y, tw, NAV_H, bg);
    tft.drawRect(i * tw, y, tw, NAV_H, C_DKGREY);
    char buf[8];
    strncpy_P(buf, (const char*)pgm_read_ptr(&tabLbl[i]), 7); buf[7] = '\0';
    int16_t tLen = strlen(buf) * 6;
    tft.setCursor(i * tw + (tw - tLen) / 2, y + (NAV_H / 2) - 4);
    tft.setTextColor(fg);
    tft.setTextSize(1);
    tft.print(buf);
  }
}

void drawTabs() {
  int16_t tw = SCR_W / TAB_COUNT;  // 60px each
  for (uint8_t i = 0; i < TAB_COUNT; i++) {
    uint16_t bg = (i == curTab) ? C_TAB_ON : C_TAB_OFF;
    uint16_t fg = (i == curTab) ? C_WHITE  : C_GREY;
    tft.fillRect(i * tw, 0, tw, TAB_H, bg);
    tft.drawRect(i * tw, 0, tw, TAB_H, C_DKGREY);
    char buf[8];
    strncpy_P(buf, (const char*)pgm_read_ptr(&tabLbl[i]), 7); buf[7] = '\0';
    int16_t tLen = strlen(buf) * 6;
    tft.setCursor(i * tw + (tw - tLen) / 2, TAB_H / 2 - 4);
    tft.setTextColor(fg); tft.setTextSize(1);
    tft.print(buf);
  }
  tft.drawFastHLine(0, TAB_H, SCR_W, C_CYAN);

  // Edge tab-navigation hints
  tft.setTextSize(1);
  tft.setTextColor(C_DKGREY);
  tft.setCursor(1, TAB_H + 2);
  tft.print(F("<"));
  tft.setCursor(SCR_W - 6, TAB_H + 2);
  tft.print(F(">"));
}

// ============================================================================
// CLEAR CONTENT AREA
// ============================================================================
void clearContent() {
  tft.fillRect(0, CY, SCR_W, SCR_H - CY, C_BG);
}

// ============================================================================
// PAGE: DASHBOARD — bars + status info + connection dot
// ============================================================================
void renderDashboard() {
  clearContent();
  int16_t y   = CY + 4;   // y=32
  int16_t barW = 162;
  int16_t barH = 12;
  int16_t gap  = 44;

  // Left: metric labels
  tft.setTextSize(1);
  tft.setTextColor(C_CYAN);    tft.setCursor(4, y);           tft.print(F("CPU"));
  tft.setTextColor(C_MAGENTA); tft.setCursor(4, y + gap);     tft.print(F("RAM"));
  tft.setTextColor(C_ORANGE);  tft.setCursor(4, y + gap * 2); tft.print(F("TEMP"));
  tft.setTextColor(C_GREEN);   tft.setCursor(4, y + gap * 3); tft.print(F("DISK"));

  // Empty bar borders
  for (int i = 0; i < 4; i++) {
    tft.drawRect(4, y + 10 + i * gap, barW, barH, C_DKGREY);
    tft.fillRect(5, y + 11 + i * gap, barW - 2, barH - 2, C_BAR_BG);
  }

  // Divider between bars and status column
  tft.drawFastVLine(196, CY, SCR_H - CY - NAV_H, C_DKGREY);

  // Right: status labels
  int16_t sx = 200;
  tft.setTextColor(C_GREY); tft.setTextSize(1);
  tft.setCursor(sx, y);        tft.print(F("WiFi:"));
  tft.setCursor(sx, y + 24);   tft.print(F("Docker:"));
  tft.setCursor(sx, y + 54);   tft.print(F("Host:"));
  tft.setCursor(sx, y + 90);   tft.print(F("Up:"));
  tft.setCursor(sx, y + 136);  tft.print(F("Status:"));

  p_cpu = -1; p_ram = -1; p_temp = -1; p_disk = -1;
  p_wifi[0] = '\0'; p_docker[0] = '\0';
  p_up[0] = '\0'; p_host[0] = '\0';
}

void updateDashboard(int16_t cpu, int16_t ram, int16_t temp, int16_t disk,
                     const char* wifi, const char* docker,
                     const char* uptime, const char* host) {
  int16_t y   = CY + 4;
  int16_t barW = 162;
  int16_t barH = 12;
  int16_t gap  = 44;
  int16_t sx   = 200;

  if (cpu != p_cpu) {
    uint16_t cc = cpu > 90 ? C_RED : cpu > 70 ? C_ORANGE : C_CYAN;
    drawBar(4, y + 10, barW, barH, cpu, p_cpu, cc);
    char b[8]; snprintf(b, 8, "%d%%", cpu);
    drawVal(170, y + 10, 24, 12, b, cc);
    p_cpu = cpu;
  }
  if (ram != p_ram) {
    uint16_t rc = ram > 90 ? C_RED : ram > 70 ? C_ORANGE : C_MAGENTA;
    drawBar(4, y + 10 + gap, barW, barH, ram, p_ram, rc);
    char b[8]; snprintf(b, 8, "%d%%", ram);
    drawVal(170, y + 10 + gap, 24, 12, b, rc);
    p_ram = ram;
  }
  if (temp != p_temp) {
    int16_t tp = constrain(temp, 0, 100);
    uint16_t tc = temp > 75 ? C_RED : temp > 55 ? C_ORANGE : C_GREEN;
    drawBar(4, y + 10 + gap * 2, barW, barH, tp,
            (p_temp < 0) ? -1 : constrain(p_temp, 0, 100), tc);
    char b[8]; snprintf(b, 8, "%dC", temp);
    drawVal(170, y + 10 + gap * 2, 24, 12, b, tc);
    p_temp = temp;
  }
  if (disk != p_disk) {
    uint16_t dc = disk > 90 ? C_RED : disk > 80 ? C_ORANGE : C_GREEN;
    drawBar(4, y + 10 + gap * 3, barW, barH, disk, p_disk, dc);
    char b[8]; snprintf(b, 8, "%d%%", disk);
    drawVal(170, y + 10 + gap * 3, 24, 12, b, dc);
    p_disk = disk;
  }

  // Right status column
  if (strcmp(wifi, p_wifi) != 0) {
    drawDot(sx + 38, y + 4, strcmp(wifi, "OK") == 0);
    drawVal(sx + 48, y, 66, 12, wifi, strcmp(wifi, "OK") == 0 ? C_GREEN : C_RED);
    strncpy(p_wifi, wifi, 7);
  }
  if (strcmp(docker, p_docker) != 0) {
    drawDot(sx + 50, y + 28, strcmp(docker, "UP") == 0);
    drawVal(sx + 60, y + 24, 54, 12, docker, strcmp(docker, "UP") == 0 ? C_GREEN : C_RED);
    strncpy(p_docker, docker, 7);
  }
  if (strcmp(host, p_host) != 0) {
    drawVal(sx, y + 66, 116, 12, host, C_WHITE);
    strncpy(p_host, host, 15);
  }
  if (strcmp(uptime, p_up) != 0) {
    drawVal(sx, y + 102, 116, 12, uptime, C_WHITE);
    strncpy(p_up, uptime, 15);
  }

  bool online = (millis() - lastDataMs < 10000);
  drawDot(sx + 8, y + 148, online);
  drawVal(sx + 20, y + 144, 94, 12, online ? "ONLINE" : "OFFLINE",
          online ? C_GREEN : C_RED);
}

// ============================================================================
// PAGE: SERVER — 6 control buttons + status
// ============================================================================
void renderServer() {
  clearContent();

  drawBtn(SB_X1, SB_Y0,            SB_W, SB_H, F("REBOOT"),    C_RED,     C_WHITE);
  drawBtn(SB_X2, SB_Y0,            SB_W, SB_H, F("SHUTDOWN"),  0x7800,    C_WHITE);
  drawBtn(SB_X1, SB_Y0 + SB_GAP,   SB_W, SB_H, F("DOCKER"),   C_ORANGE,  C_BG);
  drawBtn(SB_X2, SB_Y0 + SB_GAP,   SB_W, SB_H, F("NGINX"),    C_CYAN,    C_BG);
  drawBtn(SB_X1, SB_Y0 + SB_GAP*2, SB_W, SB_H, F("CLR CACHE"),C_MAGENTA, C_WHITE);
  drawBtn(SB_X2, SB_Y0 + SB_GAP*2, SB_W, SB_H, F("UPDATE"),   C_GREEN,   C_BG);

  // Server status — landscape: single horizontal row
  int16_t sy = SB_Y0 + SB_GAP * 2 + SB_H + 8;
  tft.drawFastHLine(4, sy - 4, SCR_W - 8, C_DKGREY);
  tft.setTextSize(1); tft.setTextColor(C_GREY);
  tft.setCursor(4,   sy);  tft.print(F("HTTP:"));
  tft.setCursor(80,  sy);  tft.print(F("Nginx:"));
  tft.setCursor(168, sy);  tft.print(F("SSL:"));
  tft.setCursor(236, sy);  tft.print(F("Cont:"));

  p_http = -1; p_nginx[0] = '\0'; p_ssl = -1; p_cont = -1;
}

void updateServer(int16_t http, const char* nginx, int16_t ssl, int16_t cont) {
  int16_t sy = SB_Y0 + SB_GAP * 2 + SB_H + 8;

  if (http != p_http) {
    char b[8]; snprintf(b, 8, "%d", http);
    uint16_t hc = (http == 200) ? C_GREEN : C_RED;
    drawDot(44, sy + 4, http == 200);
    drawVal(52, sy, 28, 12, b, hc);
    p_http = http;
  }
  if (strcmp(nginx, p_nginx) != 0) {
    bool up = (strcmp(nginx, "UP") == 0);
    drawDot(126, sy + 4, up);
    drawVal(134, sy, 34, 12, nginx, up ? C_GREEN : C_RED);
    strncpy(p_nginx, nginx, 7);
  }
  if (ssl != p_ssl) {
    char b[8]; snprintf(b, 8, "%dd", ssl);
    drawVal(196, sy, 40, 12, b, ssl > 14 ? C_GREEN : C_RED);
    p_ssl = ssl;
  }
  if (cont != p_cont) {
    char b[8]; snprintf(b, 8, "%d", cont);
    drawVal(270, sy, 40, 12, b, C_CYAN);
    p_cont = cont;
  }
}

// ============================================================================
// PAGE: NETWORK — IPs, ping, SSH, bandwidth
// ============================================================================
void renderNetwork() {
  clearContent();
  int16_t y = CY + 4;   // y=32
  int16_t gap = 28;

  tft.setTextSize(1); tft.setTextColor(C_GREY);
  tft.setCursor(4, y);            tft.print(F("Local IP:"));
  tft.setCursor(4, y + gap);      tft.print(F("Public IP:"));
  tft.setCursor(4, y + gap * 2);  tft.print(F("Ping:"));
  tft.setCursor(4, y + gap * 3);  tft.print(F("SSH:"));
  tft.setCursor(4, y + gap * 4);  tft.print(F("RX / TX:"));
  tft.setCursor(4, y + gap * 5);  tft.print(F("Containers:"));

  tft.drawFastHLine(4, y + gap * 2 - 4, SCR_W - 8, C_DKGREY);
  tft.drawFastHLine(4, y + gap * 4 - 4, SCR_W - 8, C_DKGREY);

  p_ip[0] = '\0'; p_pip[0] = '\0'; p_ping[0] = '\0';
  p_ssh[0] = '\0'; p_rx = -1; p_tx = -1; p_cont = -1;
}

void updateNetwork(const char* ip, const char* pubip, const char* ping_ms,
                   const char* ssh, int16_t rx, int16_t tx, int16_t cont) {
  int16_t y = CY + 4;
  int16_t gap = 28;

  if (strcmp(ip, p_ip) != 0) {
    drawVal(4, y + 14, 310, 12, ip, C_CYAN);
    strncpy(p_ip, ip, 19);
  }
  if (strcmp(pubip, p_pip) != 0) {
    drawVal(4, y + gap + 14, 310, 12, pubip, C_MAGENTA);
    strncpy(p_pip, pubip, 19);
  }
  if (strcmp(ping_ms, p_ping) != 0) {
    char b[20]; snprintf(b, 20, "%s ms", ping_ms);
    drawVal(55, y + gap * 2 + 2, 120, 12, b, C_ORANGE);
    strncpy(p_ping, ping_ms, 11);
  }
  if (strcmp(ssh, p_ssh) != 0) {
    char b[16]; snprintf(b, 16, "%s user(s)", ssh);
    drawVal(45, y + gap * 3 + 2, 120, 12, b, C_WHITE);
    strncpy(p_ssh, ssh, 7);
  }
  if (rx != p_rx || tx != p_tx) {
    char b[24]; snprintf(b, 24, "%dMB / %dMB", rx, tx);
    drawVal(75, y + gap * 4 + 2, 240, 12, b, C_GREEN);
    p_rx = rx; p_tx = tx;
  }
  if (cont != p_cont) {
    char b[8]; snprintf(b, 8, "%d", cont);
    drawVal(85, y + gap * 5 + 2, 50, 12, b, C_CYAN);
    p_cont = cont;
  }
}

// ============================================================================
// PAGE: SETTINGS — utility buttons + system info
// ============================================================================
void renderSettings() {
  clearContent();
  int16_t y = CY + 10;  // y=38

  drawBtn(4, y,       SCR_W - 8, 32, F("REQUEST DATA"),    C_CYAN,   C_BG);
  drawBtn(4, y + 40,  SCR_W - 8, 32, F("PING TEST"),       C_ORANGE, C_BG);
  drawBtn(4, y + 80,  SCR_W - 8, 32, F("RESET DISPLAY"),   C_RED,    C_WHITE);
  drawBtn(4, y + 120, SCR_W - 8, 32, F("CALIBRATE TOUCH"), C_YELLOW, C_BG);

  // System info
  int16_t iy = y + 158;
  tft.drawFastHLine(4, iy - 2, SCR_W - 8, C_DKGREY);
  tft.setTextSize(1); tft.setTextColor(C_GREY);
  tft.setCursor(4, iy + 2);
  tft.print(F("Landscape-R1 | 320x240 | Mega 2560 | VMA412 | 115200"));
}

// ============================================================================
// PI OFFLINE SCREEN
// ============================================================================
void renderOfflineScreen() {
  tft.fillScreen(C_BG);

  // Header bar
  tft.fillRect(0, 0, SCR_W, 28, 0x7800);  // dark red
  tft.setCursor(8, 8); tft.setTextColor(C_WHITE); tft.setTextSize(1);
  tft.print(F("ADSCREEN - RASPBERRY PI OFFLINE"));

  // Big icon area
  tft.fillRoundRect(8, 34, 64, 50, 6, C_DKGREY);
  tft.setCursor(16, 48); tft.setTextColor(C_RED); tft.setTextSize(2);
  tft.print(F("PI"));
  tft.setCursor(16, 66); tft.setTextSize(1); tft.setTextColor(C_GREY);
  tft.print(F("OFFLINE"));

  // Status details
  int16_t x = 82, y = 36, lh = 16;
  tft.setTextSize(1);
  tft.setTextColor(C_GREY);  tft.setCursor(x, y);        tft.print(F("Connection:"));
  tft.setTextColor(C_RED);   tft.setCursor(x + 74, y);   tft.print(F("LOST"));

  tft.setTextColor(C_GREY);  tft.setCursor(x, y + lh);   tft.print(F("Last seen:"));
  tft.setTextColor(C_ORANGE);
  {
    unsigned long secs = (millis() - offlineSince) / 1000UL;
    char b[24];
    if (secs < 60)        snprintf(b, 24, "%lus ago", secs);
    else if (secs < 3600) snprintf(b, 24, "%lum %lus ago", secs/60, secs%60);
    else                  snprintf(b, 24, "%luh %lum ago", secs/3600, (secs%3600)/60);
    tft.setCursor(x + 68, y + lh); tft.print(b);
  }

  tft.setTextColor(C_GREY);  tft.setCursor(x, y + lh*2); tft.print(F("Serial:"));
  tft.setTextColor(C_CYAN);  tft.setCursor(x + 50, y + lh*2); tft.print(F("115200 baud"));

  tft.setTextColor(C_GREY);  tft.setCursor(x, y + lh*3); tft.print(F("Timeout:"));
  tft.setTextColor(C_WHITE); tft.setCursor(x + 56, y + lh*3);
  tft.print(OFFLINE_TIMEOUT_MS / 1000); tft.print(F("s threshold"));

  // Separator
  tft.drawFastHLine(4, 112, SCR_W - 8, C_DKGREY);

  // Possible causes
  int16_t cy2 = 118;
  tft.setTextColor(C_YELLOW); tft.setCursor(4, cy2);     tft.print(F("Possible causes:"));
  tft.setTextColor(C_GREY);
  tft.setCursor(8, cy2 + 12);  tft.print(F("> Pi is rebooting or shutting down"));
  tft.setCursor(8, cy2 + 24);  tft.print(F("> serial_stats.py not running"));
  tft.setCursor(8, cy2 + 36);  tft.print(F("> USB cable unplugged"));
  tft.setCursor(8, cy2 + 48);  tft.print(F("> Pi power failure"));

  // Footer
  tft.drawFastHLine(4, SCR_H - 18, SCR_W - 8, C_DKGREY);
  tft.setTextColor(C_DKGREY); tft.setCursor(4, SCR_H - 12);
  tft.print(F("Will auto-reconnect when Pi returns..."));
}
// ============================================================================
// JSON COMMANDS (Arduino -> Pi)
// ============================================================================
void sendCmd(const char* cmd) {
  StaticJsonDocument<96> doc;
  doc["cmd"] = cmd;
  Serial.print('<');
  serializeJson(doc, Serial);
  Serial.println('>');
}

void sendCmdTarget(const char* cmd, const char* target) {
  StaticJsonDocument<128> doc;
  doc["cmd"] = cmd;
  doc["target"] = target;
  Serial.print('<');
  serializeJson(doc, Serial);
  Serial.println('>');
}

void showConfirm() {
  tft.fillRoundRect(60, 88, 200, 36, 8, C_GREEN);
  tft.setCursor(78, 102);
  tft.setTextColor(C_BG); tft.setTextSize(1);
  tft.print(F("Command Sent!"));
  delay(700);
  drawnTab = 255;
}

// ============================================================================
// TOUCH
// ============================================================================
void handleTouch(int16_t px, int16_t py) {
  if (sleeping) {
    sleeping = false;
    drawnTab = 255;
    return;
  }

  // Primary reliable navigation: large bottom bar
  if (py >= (SCR_H - NAV_H)) {
    uint8_t t = (uint32_t)px * TAB_COUNT / SCR_W;
    if (t < TAB_COUNT && t != curTab) curTab = t;
    return;
  }

  // Fallback gesture navigation: tap left/right edge to change tab.
  if (py > 34 && py < (SCR_H - 10)) {
    if (px <= 12) {
      curTab = (curTab + TAB_COUNT - 1) % TAB_COUNT;
      return;
    }
    if (px >= (SCR_W - 13)) {
      curTab = (curTab + 1) % TAB_COUNT;
      return;
    }
  }

  // Tab bar
  if (py <= (TAB_H + 6)) {
    uint8_t t = (uint32_t)px * TAB_COUNT / SCR_W;
    if (t < TAB_COUNT && t != curTab) curTab = t;
    return;
  }

  // Server buttons
  if (curTab == TAB_SRV) {
    struct { int16_t x, y; uint16_t bg; const __FlashStringHelper* lbl;
             const char* cmd; const char* tgt; } btns[6] = {
      { SB_X1, SB_Y0,            C_RED,     F("REBOOT"),    "reboot_pi",      NULL    },
      { SB_X2, SB_Y0,            0x7800,    F("SHUTDOWN"),  "shutdown_pi",    NULL    },
      { SB_X1, SB_Y0 + SB_GAP,   C_ORANGE,  F("DOCKER"),   "restart_docker", NULL    },
      { SB_X2, SB_Y0 + SB_GAP,   C_CYAN,    F("NGINX"),    "restart_service","nginx" },
      { SB_X1, SB_Y0 + SB_GAP*2, C_MAGENTA, F("CLR CACHE"),"clear_cache",    NULL    },
      { SB_X2, SB_Y0 + SB_GAP*2, C_GREEN,   F("UPDATE"),   "update_os",      NULL    }
    };
    for (uint8_t i = 0; i < 6; i++) {
      if (px >= btns[i].x && px < btns[i].x + SB_W &&
          py >= btns[i].y && py < btns[i].y + SB_H) {
        flashBtn(btns[i].x, btns[i].y, SB_W, SB_H, btns[i].lbl, btns[i].bg);
        if (btns[i].tgt) sendCmdTarget(btns[i].cmd, btns[i].tgt);
        else             sendCmd(btns[i].cmd);
        showConfirm();
        return;
      }
    }
  }

  // Settings buttons
  if (curTab == TAB_SET) {
    int16_t y = CY + 10;
    if (py >= y && py < y + 32) {
      flashBtn(4, y, SCR_W - 8, 32, F("REQUEST DATA"), C_CYAN);
      sendCmd("request_data");
      return;
    }
    if (py >= y + 40 && py < y + 72) {
      flashBtn(4, y + 40, SCR_W - 8, 32, F("PING TEST"), C_ORANGE);
      sendCmd("ping_test");
      return;
    }
    if (py >= y + 80 && py < y + 112) {
      flashBtn(4, y + 80, SCR_W - 8, 32, F("RESET DISPLAY"), C_RED);
      drawnTab = 255;
      return;
    }
    if (py >= y + 120 && py < y + 152) {
      flashBtn(4, y + 120, SCR_W - 8, 32, F("CALIBRATE TOUCH"), C_YELLOW);
      bool ok = runTouchCalibration();
      if (!ok) {
        tft.fillScreen(C_BG);
        showToast(F("Calibration Failed"), C_RED, C_WHITE);
        delay(1000);
      }
      drawnTab = 255;
      return;
    }
  }
}

// ============================================================================
// SERIAL PARSING
// ============================================================================
void processMessage() {
  StaticJsonDocument<384> doc;
  DeserializationError err = deserializeJson(doc, sBuf);
  if (err) return;

  lastDataMs = millis();

  // Pi just came back online — restore UI automatically
  if (piOffline) {
    piOffline = false;
    sleeping  = false;
    drawnTab  = 255;   // forces full redraw
  }

  if (doc.containsKey("c")) {
    int16_t cpu  = doc["c"]  | 0;
    int16_t ram  = doc["r"]  | 0;
    int16_t temp = doc["t"]  | 0;
    int16_t disk = doc["dk"] | 0;
    const char* wifi   = doc["w"]  | "??";
    const char* docker = doc["d"]  | "??";
    const char* uptime = doc["up"] | "--";
    const char* host   = doc["h"]  | "--";

    if (curTab == TAB_DASH)
      updateDashboard(cpu, ram, temp, disk, wifi, docker, uptime, host);

    int16_t http = doc["ht"] | 0;
    const char* nginx = doc["ng"] | "--";
    int16_t ssl  = doc["sl"] | 0;
    int16_t cont = doc["cn"] | 0;

    if (curTab == TAB_SRV)
      updateServer(http, nginx, ssl, cont);

    const char* ip    = doc["ip"] | "0.0.0.0";
    const char* pubip = doc["pi"] | "N/A";
    const char* ping  = doc["pg"] | "N/A";
    const char* ssh   = doc["ss"] | "0";
    int16_t rx = doc["rx"] | 0;
    int16_t tx = doc["tx"] | 0;

    if (curTab == TAB_NET)
      updateNetwork(ip, pubip, ping, ssh, rx, tx, cont);
  }

  if (doc.containsKey("ack")) {
    const char* m = doc["msg"] | "OK";
    tft.fillRoundRect(10, 130, 220, 30, 6, C_PANEL);
    tft.setCursor(18, 138);
    tft.setTextColor(C_GREEN); tft.setTextSize(1);
    tft.print(F("Pi: ")); tft.print(m);
    delay(1000);
    drawnTab = 255;
  }
}

void readSerial() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '<') { sIdx = 0; inMsg = true; msgRdy = false; }
    else if (c == '>' && inMsg) { sBuf[sIdx] = '\0'; inMsg = false; msgRdy = true; }
    else if (inMsg && sIdx < SBUF_SZ - 1) { sBuf[sIdx++] = c; }
  }
  if (msgRdy) { processMessage(); msgRdy = false; sIdx = 0; }
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(300);

  uint16_t id = tft.readID();
  if (id == 0xD3D3) id = 0x9486;
  if (id == 0 || id == 0xFFFF) id = 0x9341;

  tft.begin(id);
  tft.setRotation(1);  // LANDSCAPE: 320x240
  bool hasCal = loadCalibration();
  bool legacyBadCal = hasCal && (gCal.top < gCal.bottom || gCal.left == gCal.right || gCal.top == gCal.bottom);

  if (CALIBRATE_EVERY_BOOT || !hasCal || legacyBadCal) {
    tft.fillScreen(C_BG);
    tft.setTextSize(1);
    tft.setTextColor(C_WHITE);
    tft.setCursor(20, 16);
    tft.print(F("Touch calibration starting..."));
    tft.setCursor(20, 30);
    tft.setTextColor(C_GREY);
    tft.print(F("Tap each target accurately"));
    delay(700);

    bool ok = runTouchCalibration();
    if (!ok) {
      // Fallback defaults for VMA412 landscape rotation 1.
      gCal.left   = TS_LEFT_DFT;
      gCal.right  = TS_RT_DFT;
      gCal.top    = TS_TOP_DFT;
      gCal.bottom = TS_BOT_DFT;
      saveCalibration();

      tft.fillScreen(C_BG);
      showToast(F("Using Factory Touch Defaults"), C_ORANGE, C_BG);
      delay(1000);
    }
  }

  // Splash screen
  tft.fillScreen(C_BG);
  tft.setCursor(88, 80); tft.setTextColor(C_CYAN); tft.setTextSize(3);
  tft.print(F("ADSCREEN"));
  tft.setCursor(103, 118); tft.setTextColor(C_MAGENTA); tft.setTextSize(1);
  tft.print(F("Command Center v3.0"));
  tft.setCursor(115, 138); tft.setTextColor(C_GREY);
  tft.print(F("Initializing..."));
  delay(1200);

  tft.fillScreen(C_BG);
  drawTabs();
  renderDashboard();
  drawBottomNav();
  drawnTab = curTab;
  sendCmd("request_data");
}

// ============================================================================
// MAIN LOOP
// ============================================================================
void loop() {
  readSerial();

  // Touch with mandatory pin restore
  TSPoint p = ts.getPoint();
  pinMode(YP, OUTPUT);
  pinMode(XM, OUTPUT);

  if (p.z >= MINPRESSURE && p.z <= MAXPRESSURE) {
    if (millis() - lastTouchMs > DEBOUNCE_MS) {
      int16_t px = 0;
      int16_t py = 0;
      getMappedTouch(p.x, p.y, px, py);
      handleTouch(px, py);
      lastTouchMs = millis();
    }
  }

  // Redraw on tab change
  if (curTab != drawnTab) {
    drawTabs();
    switch (curTab) {
      case TAB_DASH: renderDashboard(); break;
      case TAB_SRV:  renderServer();    break;
      case TAB_NET:  renderNetwork();   break;
      case TAB_SET:  renderSettings();  break;
    }
    drawBottomNav();
    drawnTab = curTab;
    sendCmd("request_data");
  }

  // Sleep on inactivity
  if (!sleeping && !piOffline && millis() - lastTouchMs > SLEEP_MS && millis() - lastDataMs > SLEEP_MS) {
    tft.fillScreen(C_BG);
    sleeping = true;
  }

  // Pi offline detection
  if (!piOffline && lastDataMs > 0 && millis() - lastDataMs > OFFLINE_TIMEOUT_MS) {
    piOffline   = true;
    offlineSince = lastDataMs;
    sleeping    = false;
    renderOfflineScreen();
  }

  // While offline: refresh elapsed time every 5s + keep polling Pi
  if (piOffline) {
    if (millis() - lastReconnectMs > RECONNECT_POLL_MS) {
      lastReconnectMs = millis();
      renderOfflineScreen();   // updates "Last seen X ago"
      sendCmd("request_data"); // poke Pi in case it just woke up
    }
  }
}
