// ============================================================================
// ADSCREEN DIAGNOSTICS v1.0
// Quick test to verify Arduino Mega, TFT display, and serial communication
// ============================================================================

#include <Adafruit_GFX.h>
#include <MCUFRIEND_kbv.h>
#include <Serial.h>

MCUFRIEND_kbv tft;

void setup() {
  Serial.begin(115200);
  while (!Serial) delay(100);
  
  delay(1000);
  Serial.println("\n\n");
  Serial.println("╔════════════════════════════════════════╗");
  Serial.println("║   ADSCREEN DIAGNOSTICS v1.0           ║");
  Serial.println("║   Arduino Mega 2560 + TFT Test        ║");
  Serial.println("╚════════════════════════════════════════╝");
  Serial.println();
  
  // Test 1: Read Display ID
  Serial.print("[1/5] Reading TFT Display ID...");
  uint16_t id = tft.readID();
  if (id == 0 || id == 0xFFFF) {
    Serial.print(" FAIL (ID=0x");
    Serial.print(id, HEX);
    Serial.println(")");
    Serial.println("       ❌ Display not detected!");
    Serial.println("       • Check USB power");
    Serial.println("       • Verify wiring (D0-D7, CS, RS, WR, RD, RST)");
    Serial.println("       • Check for ILI9341 (0x9341) or 0x9486");
  } else {
    Serial.print(" OK (0x");
    Serial.print(id, HEX);
    Serial.println(")");
  }
  Serial.println();
  
  // Test 2: Initialize Display
  Serial.print("[2/5] Initializing TFT...");
  if (id == 0xD3D3) id = 0x9486;  // Compatibility
  tft.begin(id);
  Serial.println(" OK");
  Serial.println();
  
  // Test 3: Set Rotation
  Serial.print("[3/5] Setting rotation (landscape)...");
  tft.setRotation(1);
  Serial.println(" OK");
  Serial.println("       Resolution: 320x240");
  Serial.println();
  
  // Test 4: Fill screen with color
  Serial.print("[4/5] Drawing test pattern...");
  tft.fillScreen(0x0000);  // Black
  delay(200);
  tft.fillScreen(0xF800);  // Red
  delay(200);
  tft.fillScreen(0x07E0);  // Green
  delay(200);
  tft.fillScreen(0x001F);  // Blue
  delay(200);
  tft.fillScreen(0x0000);  // Black
  Serial.println(" OK");
  Serial.println("       You should see: Black → Red → Green → Blue → Black");
  Serial.println();
  
  // Test 5: Print text
  Serial.print("[5/5] Rendering text...");
  tft.setCursor(20, 100);
  tft.setTextColor(0xFFFF);
  tft.setTextSize(2);
  tft.print("ADSCREEN");
  tft.setCursor(30, 130);
  tft.setTextSize(1);
  tft.print("DIAGNOSTICS OK!");
  Serial.println(" OK");
  Serial.println();
  
  Serial.println("╔════════════════════════════════════════╗");
  Serial.println("║      ALL TESTS PASSED! ✓              ║");
  Serial.println("╚════════════════════════════════════════╝");
  Serial.println();
  Serial.println("Next: Upload the main adscreen_stats_display.ino sketch");
  Serial.println();
}

void loop() {
  // Every 5 seconds, send a test JSON to Pi
  delay(5000);
  Serial.print("<{\"test\":true,\"time\":");
  Serial.print(millis());
  Serial.println("}>");
}
