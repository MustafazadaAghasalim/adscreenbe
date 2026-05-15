# ADscreen Implementation Summary & Next Steps

## Current Status

**Backend (Pi Daemon):** ✅ **FULLY OPERATIONAL**
- Python daemon running on Pi at pi.local (10.10.1.33)
- Arduino detected at `/dev/ttyACM0` with 115200 baud
- System metrics being collected every 2 seconds
- Systemd service configured for auto-start and auto-restart
- **Confirmed**: Daemon is active and ready to send data

**Frontend (Arduino TFT):** 🔧 **IN TESTING**
- Sketch written with complete UI and debug logging
- Not yet confirmed running on hardware
- Hidden issue: Display either not initialized or data not rendering

---

## What We Just Did

### 1. Enhanced Serial Debugging
Added comprehensive debug output to help diagnose the display issue:

```
[LOOP]      - Shows main loop running every 5 seconds with time-since-last-data
[TX]        - Shows commands being sent to Pi (e.g., request_data, reboot_pi)
[RX]        - Shows when data arrives from Pi
[JSON]      - Shows JSON parsing success/failure and message type detection
[ERROR]     - Shows any JSON parse errors
```

### 2. Created Serial Debug Guide
New file: `SERIAL_DEBUG_GUIDE.md` explains every debug line and what it means.

### 3. Prepared Three Diagnostics Paths

**Path A: Hardware Test** (DIAGNOSTICS.ino)
- Tests TFT display initialization
- Tests color rendering
- Tests serial communication
- Use this FIRST to isolate hardware issues

**Path B: Full System** (arduino_stats_display.ino)
- Main sketch with all features
- Now with full debug logging
- Upload after Path A confirms hardware works

**Path C: Daemon Verification** (Already done!)
- Pi daemon confirmed running
- Metrics confirmed being collected
- Ready to send data

---

## Instructions for Next 30 Minutes

### **Step 1: Download Latest Files to Your Machine** (2 min)
```bash
# On your development PC/Mac:
scp -r zynorex@pi.local:/home/zynorex/adscreen_tft/arduino_stats_display.ino ~/Downloads/
scp -r zynorex@pi.local:/home/zynorex/adscreen_tft/DIAGNOSTICS.ino ~/Downloads/
```

Or just use the local files already in workspace:
- `/Users/salim/Downloads/ADSCREEN-MAIN/arduino_stats_display/arduino_stats_display.ino`
- `/Users/salim/Downloads/ADSCREEN-MAIN/arduino_stats_display/DIAGNOSTICS.ino`

### **Step 2: Prepare Arduino (3 min)**
1. **Disconnect** Arduino from Pi USB
2. Connect Arduino to your development machine
3. Open Arduino IDE
4. Install required libraries (if not done):
   - Adafruit GFX Library (by Adafruit)
   - MCUFRIEND_kbv (by David Prentice) - critical for ILI9341
   - TouchScreen (by Adafruit)
   - ArduinoJson v6 (by Benoit Blanchon)

### **Step 3: Upload DIAGNOSTICS Sketch First** (5 min)
```
File → Open → DIAGNOSTICS.ino
Tools → Board → Arduino Mega 2560
Tools → Port → /dev/cu.* (your Arduino)
Sketch → Upload

Wait for: "Uploaded successfully"
```

### **Step 4: Monitor Serial Output** (5 min)
```
Tools → Serial Monitor (115200 baud)

You should see:
✅ Color test (screen flashing red/green/blue)
✅ Text rendering "ADscreen Test"
✅ Serial output: "Test complete, ready for main sketch"

If you see nothing:
❌ Check USB cable
❌ Check Arduino board selection
❌ Check baud rate (must be 115200)
❌ Try another USB port
```

### **Step 5: Upload Main Sketch** (5 min)
If diagnostics passed:
```
File → Open → arduino_stats_display.ino
Sketch → Upload

Watch Serial Monitor for:
✅ [1/3] Reading TFT Display ID...
✅ [2/3] Initializing TFT driver... OK
✅ [3/3] Rendering splash screen... OK
✅ [LOOP] Status - Tab: 0 | Time since last data: Xms
```

### **Step 6: Connect to Pi** (3 min)
```bash
# Reconnect Arduino to Pi
sshpass -p 15261526 ssh -o StrictHostKeyChecking=no zynorex@pi.local \
  'sudo systemctl restart adscreen-daemon'

# Tail the daemon logs
sshpass -p 15261526 ssh -o StrictHostKeyChecking=no zynorex@pi.local \
  'sudo journalctl -u adscreen-daemon -f'

# Should see: "[INFO] Connected to /dev/ttyACM0 at 115200 baud"
```

### **Step 7: Verify Data Flow** (2 min)
In Serial Monitor, watch for:
```
[LOOP] Status - Tab: 0 | Time since last data: 2000ms
[RX] Message ready
[JSON] Parsing: {"c":45,"r":80,"t":65,...}
[JSON] Parse OK
[JSON] Detected telemetry message
```

**AND** visually check the TFT display:
- Does it show the 4-tab interface?
- Do the bars/numbers change every 2 seconds?
- Can you touch the tabs and see them highlight?

---

## Success Criteria

✅ **Success looks like this:**
- Serial Monitor shows `[JSON] Detected telemetry message` every 2 seconds
- TFT display shows:
  - Dashboard tab with CPU/RAM/Temp/Disk bars
  - Bars updating and moving every 2 seconds
  - 4 tabs visible at top: "🏠" "📊" "🌐" "⚙️"
  - Touch response when you tap a button

---

## What Each Component Does

### **Pi Daemon (Running)**
- Collects: CPU%, RAM%, Temperature, Disk%, WiFi, Docker, Uptime, Hostname, IP, Ping, SSH sessions, Bandwidth, HTTP status, Nginx, SSL cert expiry, Containers
- Sends every 2 seconds: `<{"c":45,"r":80,"t":65,...}>`
- Receives: `<{"cmd":"reboot_pi"}>`
- Auto-reconnects if USB disconnects
- Auto-starts on Pi boot (systemd service)

### **Arduino** (To be verified)
- Displays: 4-tab UI with real-time metrics
- Updates via delta-drawing (no flicker)
- Receives JSON from Pi, parses with ArduinoJson
- Sends commands: reboot_pi, restart_docker, update_apt, check_ssl, etc.
- Touch interface: 6 server buttons, 3 language buttons
- Multi-language: English, Dutch, French (PROGMEM optimized)

### **Serial Protocol** (Both sides)
```
Message format: <JSON>
Example TX (Arduino→Pi): <{"cmd":"reboot_pi"}>
Example RX (Pi→Arduino): <{"c":45,"r":80,"t":65,"dk":42,...}>
Delimiter: < > (start/end markers)
Baud: 115200
Timeout: 10 seconds (auto-reconnect)
```

---

## Troubleshooting If Something Goes Wrong

### **Symptom: Serial Monitor shows nothing**
- ❌ USB cable loose → Reconnect
- ❌ Wrong port selected → Check Tools → Port
- ❌ Baud rate wrong → Must be 115200
- ❌ Arduino not responding → Try resetting board

### **Symptom: TFT initialized but no data**
- ❌ Pi daemon not running → Check: `ssh pi 'systemctl status adscreen-daemon'`
- ❌ Arduino not connected to Pi → Reconnect USB
- ❌ Daemon crashed → Restart: `ssh pi 'systemctl restart adscreen-daemon'`
- ❌ Serial malformed → Check daemon sending correct `<JSON>`

### **Symptom: Touch doesn't work**
- ❌ Pins not restored after getPoint() → Check code in loop()
- ❌ Touch shield calibration off → Run touchScreen calibration sketch
- ❌ YP/XM pins causing TFT white-out → Pin restore is mandatory

### **Symptom: Data arrives but doesn't render**
- ❌ updateDashboard() not called → Check currentTab == TAB_DASHBOARD
- ❌ Delta rendering broken → Monitor if renderDashboard() shows new data
- ❌ TFT command timing issue → Try reducing loop() sleep

---

## File Reference

| File | Location | Purpose |
|------|----------|---------|
| **DIAGNOSTICS.ino** | `arduino_stats_display/` | Hardware test sketch |
| **arduino_stats_display.ino** | `arduino_stats_display/` | Main sketch (updated with debug) |
| **adscreen_daemon.py** | On Pi at `~/adscreen_tft/` | Telemetry daemon |
| **adscreen-daemon.service** | On Pi at `/etc/systemd/system/` | Auto-start service |
| **SERIAL_DEBUG_GUIDE.md** | Root folder | Debug output reference |
| **DEPLOYMENT_GUIDE.md** | Root folder | Full system documentation |

---

## Expected Timeline

| Phase | Time | Status |
|-------|------|--------|
| Upload DIAGNOSTICS | 5 min | Next |
| Monitor Serial (hardware check) | 5 min | Next |
| Upload Main Sketch | 5 min | After diagnostics |
| Reconnect to Pi | 3 min | After upload |
| Verify data flow | 2-5 min | Final |
| **Total** | **~25 min** | **Should see live data** |

---

## Key Points to Remember

1. **Always restore pins after touch**: `pinMode(YP, OUTPUT); pinMode(XM, OUTPUT);`
   - Forgetting this causes TFT to white-out

2. **Use PROGMEM for all strings**: Saves precious Arduino RAM
   - Arduino Mega has only 8KB SRAM

3. **Delta drawing only**: Never use `fillScreen()` in loop()
   - Causes flickering and lag

4. **Non-blocking serial**: Use event-driven instead of delay()
   - Keeps UI responsive

5. **JSON markers matter**: Messages must be wrapped in `<>`
   - `<{"cmd":"..."}>` not `{"cmd":"..."}` alone

---

## When You're Ready

**1. Verify Arduino sketch is uploaded** (check Serial Monitor shows startup)
**2. Reconnect to Pi** and watch for data
**3. If data arrives but doesn't display** → check renderDashboard() logic
**4. If everything works** → celebrate! Then test auto-restart on Pi reboot

---

## Next: Automated Verification

Once display is working, we can:
- ✅ Test auto-restart on Pi reboot (systemd service)
- ✅ Test command execution (reboot, docker restart, etc.)
- ✅ Test multi-language switching
- ✅ Monitor long-term stability (24+ hour uptime test)
- ✅ Optimize performance if needed

**But first: Get the display showing live data!**

Good luck! 🚀

---

## Questions During Testing?

Provide these details:
1. What does Serial Monitor show on startup?
2. What do you see on the TFT display?
3. Does it stay the same or change?
4. Are there any [ERROR] messages?
5. Screenshot of Serial Monitor if possible

We'll debug from there.
