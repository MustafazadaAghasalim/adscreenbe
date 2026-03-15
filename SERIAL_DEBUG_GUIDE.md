# Serial Debug Guide for ADscreen Arduino

This guide explains all the debug output you'll see in the Arduino Serial Monitor (115200 baud) to help diagnose the display issue.

## Expected Serial Output Sequence

### 1. **Startup Phase** (first 5 seconds)
```
[1/3] Reading TFT Display ID...
   Display: 0x9341 (ILI9341 detected)
[2/3] Initializing TFT driver... OK
[3/3] Rendering splash screen... OK
   UI Ready - Waiting for Pi telemetry...
```

**What it means:** TFT display initialized successfully and is ready to display data.

**If you see:**
- `Display ID: 0x0000` or `Display ID: 0xFFFF` → **Hardware issue**: TFT not responding on pins
- `Initialize failed` → **Driver issue**: MCUFRIEND_kbv not working
- Nothing at all → **Serial issue**: Check USB cable and baud rate (115200)

---

### 2. **Loop Running Phase** (continuous, every 5 seconds)
```
[LOOP] Status - Tab: 0 | Time since last data: 2341ms
[TX] Sending: request_data
```

**What it means:** 
- Loop is running and requesting data from Pi
- `Time since last data` shows milliseconds since last update from Pi

**If you see:**
- Increasing time (e.g., 5341ms, 10341ms, 15341ms) → **No data from Pi**: Check Pi daemon, USB connection
- Time stays around 2000ms (resets) → **Data is arriving**: Continue to step 3

---

### 3. **Data Reception Phase** (when Pi sends telemetry)
```
[RX] Message ready
[JSON] Parsing: {"c":45,"r":80,"t":65,"dk":42,"w":"OK","d":"UP",...}
[JSON] Parse OK
[JSON] Detected telemetry message
```

**What it means:** Arduino received JSON from Pi and successfully parsed it.

**If you see:**
- `[ERROR] JSON parse failed: ...` → **JSON malformed**: Check Pi daemon sending correct format
- `[RX] Message ready` but no `[JSON] Parsing:` → **Serial communication issue**: Something is wrong with readSerial() function
- No `[RX] Message ready` at all → **No data arriving**: Check USB cable, Pi not connected

---

### 4. **Touch and Commands Phase** (when you touch the display)
```
[TX] Sending: reboot_pi target=
[LOOP] Status - Tab: 0 | Time since last data: 156ms
```

**What it means:** Your touch on a button sent a command to Pi.

**If you see:**
- Commands sending but no data updates → **Pi received command but not responding**: Check Pi daemon logs
- No command output when you touch → **Touch not working**: Verify touch pin configuration or calibration

---

## Detailed Log Format Reference

| Prefix | Meaning | Example |
|--------|---------|---------|
| `[1/3]`, `[2/3]`, `[3/3]` | Initialization phases | Startup only |
| `[LOOP]` | Main loop status | Every 5 seconds |
| `[RX]` | Data received from Pi | When serial data arrives |
| `[TX]` | Data sent to Pi | When you interact with display |
| `[JSON]` | JSON processing | When parsing/detecting message types |
| `[ERROR]` | Something went wrong | When parse fails, etc. |

---

## Troubleshooting Steps

### Display shows nothing (frozen on splash screen)
1. Check startup phase output above
2. Verify TFT display connections (GND, VCC, CS, RST, D0-D7, RD, WR)
3. Try DIAGNOSTICS.ino first to isolate hardware

### Display shows splash but no data updates
1. Check `[LOOP]` output - should show increasing time
2. Check `[TX] Sending: request_data` - should appear every 5 seconds
3. Verify Pi daemon is running: `ssh pi 'sudo systemctl status adscreen-daemon'`
4. Check Pi daemon can see Arduino: `ssh pi 'sudo journalctl -u adscreen-daemon -n 20'`

### Display shows data once, then freezes
1. Check `[RX] Message ready` count - should increase every 2 seconds
2. If missing: USB cable may be loose or Pi daemon crashed
3. Reconnect Arduino to Pi and restart: `ssh pi 'sudo systemctl restart adscreen-daemon'`

### Touch buttons don't respond
1. Check `[TX] Sending:` appears in log when you touch
2. If no output: Verify TouchScreen pins (XP, YP, XM, YM)
3. Run DIAGNOSTICS.ino to test touch separately

---

## How to Use This Information

**Step 1:** Upload `arduino_stats_display.ino` to Arduino Mega 2560
**Step 2:** Open Serial Monitor (115200 baud) BEFORE connecting to Pi
**Step 3:** Note the startup sequence - does TFT initialize?
**Step 4:** Connect Arduino to Pi USB
**Step 5:** Watch for `[RX] Message ready` and data updates
**Step 6:** Send each piece of information to the developer with timestamps

---

## Example Healthy Session Output

```
[1/3] Reading TFT Display ID...
   Display: 0x9341 (ILI9341 detected)
[2/3] Initializing TFT driver... OK
[3/3] Rendering splash screen... OK
   UI Ready - Waiting for Pi telemetry...
[LOOP] Status - Tab: 0 | Time since last data: 200ms
[TX] Sending: request_data
[RX] Message ready
[JSON] Parsing: {"c":45,"r":80,"t":65,"dk":42,"w":"OK","d":"UP",...}
[JSON] Parse OK
[JSON] Detected telemetry message
[LOOP] Status - Tab: 0 | Time since last data: 314ms
[RX] Message ready
[JSON] Parsing: {"c":42,"r":78,"t":66,"dk":42,"w":"OK","d":"UP",...}
[JSON] Parse OK
[JSON] Detected telemetry message
```

This shows the display is working perfectly: TFT initialized, data arriving every 2 seconds, being parsed successfully.

---

## Example Problem Session Output

```
[1/3] Reading TFT Display ID...
   ❌ Display not detected!
```

This means TFT is not responding - hardware issue, not software.

Or:

```
[1/3] Reading TFT Display ID...
   Display: 0x9341 (ILI9341 detected)
[2/3] Initializing TFT driver... OK
[3/3] Rendering splash screen... OK
   UI Ready - Waiting for Pi telemetry...
[LOOP] Status - Tab: 0 | Time since last data: 5234ms
[LOOP] Status - Tab: 0 | Time since last data: 10234ms
[LOOP] Status - Tab: 0 | Time since last data: 15234ms
```

This shows hardware is OK, but no data from Pi. The time keeps increasing, meaning Pi hasn't sent anything.

---

## Questions to Answer with This Output

When reporting issues, provide:
1. **What's on startup?** (TFT ID detected? Driver initialized?)
2. **Is [LOOP] showing?** (Is Arduino code running?)
3. **Is time increasing?** (Is data arriving from Pi?)
4. **When data arrives, does it parse?** (JSON errors or success?)
5. **Does display update visually?** (Can you see the data on screen?)

Good luck! The debug output will tell you exactly what's happening at each step. 🔍
