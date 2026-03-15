#!/usr/bin/env python3
"""
ILI9341 8-Bit Parallel System Stats Display
============================================
Drives a Velleman VMA412 (ILI9341) 2.8" TFT Shield connected to a
Raspberry Pi via an 8-bit parallel (bit-bang) interface.

Displays real-time CPU %, RAM %, and CPU Temperature.

Pin Mapping (BCM):
  Data D0-D7 : GPIO 17, 18, 27, 22, 23, 24, 25, 4
  CS         : GPIO 8
  CD / RS    : GPIO 7   (Command/Data select)
  WR         : GPIO 10
  RST        : GPIO 11
  RD         : GPIO 9   (held HIGH permanently — safety!)

Dependencies:
  sudo apt-get install -y python3-pip python3-dev
  pip3 install psutil RPi.GPIO

Usage:
  sudo python3 ili9341_stats.py
"""

import time
import signal
import sys

try:
    import RPi.GPIO as GPIO
except ImportError:
    print("ERROR: RPi.GPIO not found. Install with: pip3 install RPi.GPIO")
    sys.exit(1)

try:
    import psutil
except ImportError:
    print("ERROR: psutil not found. Install with: pip3 install psutil")
    sys.exit(1)


# ─────────────────────────────────────────────
#  Minimal 5×7 bitmap font (ASCII 32 – 126)
# ─────────────────────────────────────────────
FONT_5X7 = {
    ' ':  [0x00,0x00,0x00,0x00,0x00],
    '!':  [0x00,0x00,0x5F,0x00,0x00],
    '"':  [0x00,0x07,0x00,0x07,0x00],
    '#':  [0x14,0x7F,0x14,0x7F,0x14],
    '$':  [0x24,0x2A,0x7F,0x2A,0x12],
    '%':  [0x23,0x13,0x08,0x64,0x62],
    '&':  [0x36,0x49,0x55,0x22,0x50],
    "'":  [0x00,0x05,0x03,0x00,0x00],
    '(':  [0x00,0x1C,0x22,0x41,0x00],
    ')':  [0x00,0x41,0x22,0x1C,0x00],
    '*':  [0x08,0x2A,0x1C,0x2A,0x08],
    '+':  [0x08,0x08,0x3E,0x08,0x08],
    ',':  [0x00,0x50,0x30,0x00,0x00],
    '-':  [0x08,0x08,0x08,0x08,0x08],
    '.':  [0x00,0x60,0x60,0x00,0x00],
    '/':  [0x20,0x10,0x08,0x04,0x02],
    '0':  [0x3E,0x51,0x49,0x45,0x3E],
    '1':  [0x00,0x42,0x7F,0x40,0x00],
    '2':  [0x42,0x61,0x51,0x49,0x46],
    '3':  [0x21,0x41,0x45,0x4B,0x31],
    '4':  [0x18,0x14,0x12,0x7F,0x10],
    '5':  [0x27,0x45,0x45,0x45,0x39],
    '6':  [0x3C,0x4A,0x49,0x49,0x30],
    '7':  [0x01,0x71,0x09,0x05,0x03],
    '8':  [0x36,0x49,0x49,0x49,0x36],
    '9':  [0x06,0x49,0x49,0x29,0x1E],
    ':':  [0x00,0x36,0x36,0x00,0x00],
    ';':  [0x00,0x56,0x36,0x00,0x00],
    '<':  [0x00,0x08,0x14,0x22,0x41],
    '=':  [0x14,0x14,0x14,0x14,0x14],
    '>':  [0x41,0x22,0x14,0x08,0x00],
    '?':  [0x02,0x01,0x51,0x09,0x06],
    '@':  [0x32,0x49,0x79,0x41,0x3E],
    'A':  [0x7E,0x11,0x11,0x11,0x7E],
    'B':  [0x7F,0x49,0x49,0x49,0x36],
    'C':  [0x3E,0x41,0x41,0x41,0x22],
    'D':  [0x7F,0x41,0x41,0x22,0x1C],
    'E':  [0x7F,0x49,0x49,0x49,0x41],
    'F':  [0x7F,0x09,0x09,0x01,0x01],
    'G':  [0x3E,0x41,0x41,0x51,0x32],
    'H':  [0x7F,0x08,0x08,0x08,0x7F],
    'I':  [0x00,0x41,0x7F,0x41,0x00],
    'J':  [0x20,0x40,0x41,0x3F,0x01],
    'K':  [0x7F,0x08,0x14,0x22,0x41],
    'L':  [0x7F,0x40,0x40,0x40,0x40],
    'M':  [0x7F,0x02,0x04,0x02,0x7F],
    'N':  [0x7F,0x04,0x08,0x10,0x7F],
    'O':  [0x3E,0x41,0x41,0x41,0x3E],
    'P':  [0x7F,0x09,0x09,0x09,0x06],
    'Q':  [0x3E,0x41,0x51,0x21,0x5E],
    'R':  [0x7F,0x09,0x19,0x29,0x46],
    'S':  [0x46,0x49,0x49,0x49,0x31],
    'T':  [0x01,0x01,0x7F,0x01,0x01],
    'U':  [0x3F,0x40,0x40,0x40,0x3F],
    'V':  [0x1F,0x20,0x40,0x20,0x1F],
    'W':  [0x3F,0x40,0x38,0x40,0x3F],
    'X':  [0x63,0x14,0x08,0x14,0x63],
    'Y':  [0x07,0x08,0x70,0x08,0x07],
    'Z':  [0x61,0x51,0x49,0x45,0x43],
    '[':  [0x00,0x00,0x7F,0x41,0x41],
    '\\': [0x02,0x04,0x08,0x10,0x20],
    ']':  [0x41,0x41,0x7F,0x00,0x00],
    '^':  [0x04,0x02,0x01,0x02,0x04],
    '_':  [0x40,0x40,0x40,0x40,0x40],
    '`':  [0x00,0x01,0x02,0x04,0x00],
    'a':  [0x20,0x54,0x54,0x54,0x78],
    'b':  [0x7F,0x48,0x44,0x44,0x38],
    'c':  [0x38,0x44,0x44,0x44,0x20],
    'd':  [0x38,0x44,0x44,0x48,0x7F],
    'e':  [0x38,0x54,0x54,0x54,0x18],
    'f':  [0x08,0x7E,0x09,0x01,0x02],
    'g':  [0x08,0x14,0x54,0x54,0x3C],
    'h':  [0x7F,0x08,0x04,0x04,0x78],
    'i':  [0x00,0x44,0x7D,0x40,0x00],
    'j':  [0x20,0x40,0x44,0x3D,0x00],
    'k':  [0x00,0x7F,0x10,0x28,0x44],
    'l':  [0x00,0x41,0x7F,0x40,0x00],
    'm':  [0x7C,0x04,0x18,0x04,0x78],
    'n':  [0x7C,0x08,0x04,0x04,0x78],
    'o':  [0x38,0x44,0x44,0x44,0x38],
    'p':  [0x7C,0x14,0x14,0x14,0x08],
    'q':  [0x08,0x14,0x14,0x18,0x7C],
    'r':  [0x7C,0x08,0x04,0x04,0x08],
    's':  [0x48,0x54,0x54,0x54,0x20],
    't':  [0x04,0x3F,0x44,0x40,0x20],
    'u':  [0x3C,0x40,0x40,0x20,0x7C],
    'v':  [0x1C,0x20,0x40,0x20,0x1C],
    'w':  [0x3C,0x40,0x30,0x40,0x3C],
    'x':  [0x44,0x28,0x10,0x28,0x44],
    'y':  [0x0C,0x50,0x50,0x50,0x3C],
    'z':  [0x44,0x64,0x54,0x4C,0x44],
    '{':  [0x00,0x08,0x36,0x41,0x00],
    '|':  [0x00,0x00,0x7F,0x00,0x00],
    '}':  [0x00,0x41,0x36,0x08,0x00],
    '~':  [0x08,0x08,0x2A,0x1C,0x08],
}


# ─────────────────────────────────────────────
#  ILI9341 8-Bit Parallel Bit-Bang Driver
# ─────────────────────────────────────────────
class ILI9341Parallel:
    """
    Drives an ILI9341 TFT display via 8-bit parallel GPIO (bit-bang).
    This does NOT use SPI — it toggles GPIO pins directly.
    """

    # Display dimensions (landscape)
    WIDTH  = 320
    HEIGHT = 240

    # ILI9341 Commands
    CMD_SWRESET  = 0x01
    CMD_SLPOUT   = 0x11
    CMD_DISPON   = 0x29
    CMD_CASET    = 0x2A
    CMD_RASET    = 0x2B
    CMD_RAMWR    = 0x2C
    CMD_MADCTL   = 0x36
    CMD_COLMOD   = 0x3A

    # Color constants (RGB565)
    BLACK   = 0x0000
    WHITE   = 0xFFFF
    RED     = 0xF800
    GREEN   = 0x07E0
    BLUE    = 0x001F
    CYAN    = 0x07FF
    YELLOW  = 0xFFE0
    ORANGE  = 0xFD20
    MAGENTA = 0xF81F
    DARK_GREY  = 0x4208
    LIGHT_GREY = 0xC618

    def __init__(self):
        """Set up GPIO pins and initialize the ILI9341."""
        # Data bus pins D0–D7 (BCM numbering)
        self.data_pins = [17, 18, 27, 22, 23, 24, 25, 4]
        
        # Pre-calculate pin states for all bytes 0-255 for massive speedup
        self.PIN_STATES = [tuple((val >> i) & 1 for i in range(8)) for val in range(256)]

        # Control pins
        self.pin_cs  = 8    # Chip Select (active LOW)
        self.pin_rs  = 7    # Register Select / CD (0=cmd, 1=data)
        self.pin_wr  = 10   # Write strobe (active LOW pulse)
        self.pin_rst = 11   # Hardware reset (active LOW)
        self.pin_rd  = 9    # Read strobe (permanently HIGH for 5V safety)

        # Pi 5 timing compensation: 2us for a balance of speed and stability
        self.speed_delay = 0.000002 

        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)

        # Setup all pins as OUTPUT
        for pin in self.data_pins + [self.pin_cs, self.pin_rs, self.pin_wr, self.pin_rst, self.pin_rd]:
            GPIO.setup(pin, GPIO.OUT, initial=GPIO.HIGH if pin in [self.pin_cs, self.pin_rs, self.pin_wr, self.pin_rst, self.pin_rd] else GPIO.LOW)

        self._hw_reset()
        self._init_display()

    # ── Low-level GPIO helpers ──────────────────

    def _set_data_bus(self, byte):
        """Put an 8-bit value on the data bus."""
        GPIO.output(self.data_pins, self.PIN_STATES[byte])

    def _wr_strobe(self):
        """Pulse WR low then high to latch data."""
        GPIO.output(self.pin_wr, GPIO.LOW)
        GPIO.output(self.pin_wr, GPIO.HIGH)

    def _write_8(self, val):
        """Core 8-bit write."""
        self._set_data_bus(val)
        self._wr_strobe()

    def write_command(self, cmd):
        """Send a command byte (RS=LOW)."""
        GPIO.output(self.pin_rs, GPIO.LOW)
        GPIO.output(self.pin_cs, GPIO.LOW)
        self._write_8(cmd)
        GPIO.output(self.pin_cs, GPIO.HIGH)

    def write_data(self, data):
        """Send a data byte (RS=HIGH)."""
        GPIO.output(self.pin_rs, GPIO.HIGH)
        GPIO.output(self.pin_cs, GPIO.LOW)
        self._write_8(data & 0xFF)
        GPIO.output(self.pin_cs, GPIO.HIGH)

    def write_data16(self, data16):
        """Send 16-bit value as two 8-bit writes."""
        self.write_data((data16 >> 8) & 0xFF)
        self.write_data(data16 & 0xFF)

    def _write_data_bulk(self, color, count):
        """Highly optimized bulk-write for screen fills."""
        hi = (color >> 8) & 0xFF
        lo = color & 0xFF
        
        hi_states = self.PIN_STATES[hi]
        lo_states = self.PIN_STATES[lo]
        pins = self.data_pins
        wr = self.pin_wr
        
        GPIO.output(self.pin_rs, GPIO.HIGH)
        GPIO.output(self.pin_cs, GPIO.LOW)
        
        for _ in range(count):
            GPIO.output(pins, hi_states)
            GPIO.output(wr, GPIO.LOW)
            GPIO.output(wr, GPIO.HIGH)
            
            GPIO.output(pins, lo_states)
            GPIO.output(wr, GPIO.LOW)
            GPIO.output(wr, GPIO.HIGH)
            
        GPIO.output(self.pin_cs, GPIO.HIGH)

    # ── Initialization ──────────────────────────

    def _hw_reset(self):
        """Hardware reset sequence."""
        # Ensure control pins are in idle state (HIGH) before reset
        GPIO.output(self.pin_cs, GPIO.HIGH)
        GPIO.output(self.pin_rs, GPIO.HIGH)
        GPIO.output(self.pin_wr, GPIO.HIGH)
        GPIO.output(self.pin_rd, GPIO.HIGH)
        
        GPIO.output(self.pin_rst, GPIO.HIGH)
        time.sleep(0.01)
        GPIO.output(self.pin_rst, GPIO.LOW)
        time.sleep(0.02)
        GPIO.output(self.pin_rst, GPIO.HIGH)
        time.sleep(0.15) # Wait for display to wake up

    def _init_display(self):
        """ILI9341 initialization sequence (Adafruit compatible)."""
        self.write_command(self.CMD_SWRESET)
        time.sleep(0.150)

        # Power Control A
        self.write_command(0xCB)
        for b in [0x39, 0x2C, 0x00, 0x34, 0x02]:
            self.write_data(b)
        
        # Power Control B
        self.write_command(0xCF)
        for b in [0x00, 0xC1, 0x30]:
            self.write_data(b)

        # Driver Timing Control A
        self.write_command(0xE8)
        for b in [0x85, 0x00, 0x78]:
            self.write_data(b)
            
        # Driver Timing Control B
        self.write_command(0xEA)
        for b in [0x00, 0x00]:
            self.write_data(b)
            
        # Power On Sequence Control
        self.write_command(0xED)
        for b in [0x64, 0x03, 0x12, 0x81]:
            self.write_data(b)
            
        # Pump Ratio Control
        self.write_command(0xF7)
        self.write_data(0x20)
        
        # Power Control 1
        self.write_command(0xC0)
        self.write_data(0x23)
        
        # Power Control 2
        self.write_command(0xC1)
        self.write_data(0x10)
        
        # VCOM Control 1
        self.write_command(0xC5)
        self.write_data(0x3E)
        self.write_data(0x28)
        
        # VCOM Control 2
        self.write_command(0xC7)
        self.write_data(0x86)

        # Memory Access Control - landscape, BGR
        self.write_command(self.CMD_MADCTL)
        self.write_data(0x28)  # MX + BGR
        
        # Pixel format: 16-bit RGB565
        self.write_command(self.CMD_COLMOD)
        self.write_data(0x55)
        
        # Frame Rate Control (normal mode)
        self.write_command(0xB1)
        self.write_data(0x00)
        self.write_data(0x18)
        
        # Display Function Control
        self.write_command(0xB6)
        for b in [0x08, 0x82, 0x27]:
            self.write_data(b)
            
        # Enable 3G (gamma)
        self.write_command(0xF2)
        self.write_data(0x00)
        
        # Gamma Set
        self.write_command(0x26)
        self.write_data(0x01)
        
        # Positive Gamma Correction
        self.write_command(0xE0)
        for b in [0x0F,0x31,0x2B,0x0C,0x0E,0x08,0x4E,0xF1,
                  0x37,0x07,0x10,0x03,0x0E,0x09,0x00]:
            self.write_data(b)
            
        # Negative Gamma Correction
        self.write_command(0xE1)
        for b in [0x00,0x0E,0x14,0x03,0x11,0x07,0x31,0xC1,
                  0x48,0x08,0x0F,0x0C,0x31,0x36,0x0F]:
            self.write_data(b)
            
        self.write_command(self.CMD_SLPOUT)
        time.sleep(0.120)

        # Display ON
        self.write_command(self.CMD_DISPON)
        time.sleep(0.100)

    # ── Drawing primitives ──────────────────────

    def set_address_window(self, x0, y0, x1, y1):
        """Define the rectangular area for subsequent pixel writes."""
        self.write_command(self.CMD_CASET)
        self.write_data16(x0)
        self.write_data16(x1)
        self.write_command(self.CMD_RASET)
        self.write_data16(y0)
        self.write_data16(y1)
        self.write_command(self.CMD_RAMWR)

    def fill_screen(self, color):
        """Fill the entire screen with a single color."""
        self.set_address_window(0, 0, self.WIDTH - 1, self.HEIGHT - 1)
        self._write_data_bulk(color, self.WIDTH * self.HEIGHT)

    def fill_rect(self, x, y, w, h, color):
        """Draw a filled rectangle."""
        if x >= self.WIDTH or y >= self.HEIGHT:
            return
        if x + w > self.WIDTH:
            w = self.WIDTH - x
        if y + h > self.HEIGHT:
            h = self.HEIGHT - y
        self.set_address_window(x, y, x + w - 1, y + h - 1)
        self._write_data_bulk(color, w * h)

    def draw_pixel(self, x, y, color):
        """Set a single pixel."""
        if 0 <= x < self.WIDTH and 0 <= y < self.HEIGHT:
            self.set_address_window(x, y, x, y)
            self.write_data16(color)

    def draw_char(self, x, y, ch, color, bg=None, scale=1):
        """
        Draw a single character at (x, y) using the built-in 5×7 font.
        `scale` multiplies pixel size for larger text.
        Returns the width consumed (for chaining).
        """
        glyph = FONT_5X7.get(ch, FONT_5X7.get('?', [0]*5))
        char_w = len(glyph) * scale
        char_h = 7 * scale

        # Fill background rectangle if specified
        if bg is not None:
            self.fill_rect(x, y, char_w + scale, char_h, bg)

        for col_idx, col_data in enumerate(glyph):
            for row in range(7):
                if col_data & (1 << row):
                    if scale == 1:
                        self.draw_pixel(x + col_idx, y + row, color)
                    else:
                        self.fill_rect(
                            x + col_idx * scale,
                            y + row * scale,
                            scale, scale, color
                        )
        return char_w + scale  # include 1-pixel gap

    def draw_string(self, x, y, text, color, bg=None, scale=1):
        """Draw a string of characters starting at (x, y)."""
        cursor_x = x
        for ch in text:
            w = self.draw_char(cursor_x, y, ch, color, bg=bg, scale=scale)
            cursor_x += w

    def draw_hline(self, x, y, w, color):
        """Draw a horizontal line."""
        self.fill_rect(x, y, w, 1, color)

    def draw_progress_bar(self, x, y, w, h, pct, fg, bg, border_color):
        """
        Draw a progress bar outline with filled portion.
        pct: 0–100
        """
        # Border
        self.fill_rect(x, y, w, 1, border_color)        # top
        self.fill_rect(x, y + h - 1, w, 1, border_color)  # bottom
        self.fill_rect(x, y, 1, h, border_color)          # left
        self.fill_rect(x + w - 1, y, 1, h, border_color)  # right

        inner_w = w - 4
        inner_h = h - 4
        fill_w = max(0, int(inner_w * min(pct, 100) / 100))

        # Background portion
        self.fill_rect(x + 2, y + 2, inner_w, inner_h, bg)
        # Filled portion
        if fill_w > 0:
            self.fill_rect(x + 2, y + 2, fill_w, inner_h, fg)

    def cleanup(self):
        """Turn off display and clean up GPIO."""
        try:
            self.fill_screen(self.BLACK)
            # Display OFF
            self.write_command(0x28)
            time.sleep(0.050)
            # Enter sleep
            self.write_command(0x10)
            time.sleep(0.120)
        except Exception:
            pass
        GPIO.cleanup()


# ─────────────────────────────────────────────
#  System Stats Collector
# ─────────────────────────────────────────────
class SystemStats:
    """Gathers system metrics using psutil."""

    @staticmethod
    def cpu_percent():
        """Get current CPU usage percentage."""
        return psutil.cpu_percent(interval=0.5)

    @staticmethod
    def ram_percent():
        """Get RAM usage percentage."""
        return psutil.virtual_memory().percent

    @staticmethod
    def cpu_temp():
        """
        Read CPU temperature (°C) from the thermal zone.
        Returns None if unavailable.
        """
        try:
            with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
                return int(f.read().strip()) / 1000.0
        except (FileNotFoundError, ValueError, PermissionError):
            # Fallback for psutil sensors
            try:
                temps = psutil.sensors_temperatures()
                if "cpu_thermal" in temps:
                    return temps["cpu_thermal"][0].current
                if "cpu-thermal" in temps:
                    return temps["cpu-thermal"][0].current
            except Exception:
                pass
            return None


# ─────────────────────────────────────────────
#  Premium UI Assets & Colors
# ─────────────────────────────────────────────

# Pixel Icons (8x8 bitmaps)
ICON_CPU = [0x3C, 0x42, 0x99, 0xBD, 0xBD, 0x99, 0x42, 0x3C]
ICON_RAM = [0xFF, 0x81, 0xBD, 0xA5, 0xA5, 0xBD, 0x81, 0xFF]
ICON_TEMP = [0x18, 0x18, 0x18, 0x7E, 0xFF, 0xFF, 0x7E, 0x3C]

def rgb565(r, g, b):
    """Convert 8-bit RGB to 16-bit RGB565."""
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)

# Premium Cyberpunk Palette
COLOR_OBSIDIAN      = rgb565(10, 10, 15)
COLOR_NEON_CYAN     = rgb565(0, 255, 255)
COLOR_NEON_MAGENTA  = rgb565(255, 0, 255)
COLOR_NEON_ORANGE   = rgb565(255, 128, 0)
COLOR_GLOW_CYAN     = rgb565(0, 80, 80)
COLOR_GLOW_MAGENTA  = rgb565(80, 0, 80)
COLOR_GLASS_PANEL   = rgb565(25, 25, 35)

def draw_icon(lcd, x, y, icon_data, color, scale=2):
    """Draw a pixel icon from a list of 8 bytes."""
    for row_idx, byte in enumerate(icon_data):
        for col_idx in range(8):
            if byte & (1 << (7 - col_idx)):
                lcd.fill_rect(x + col_idx * scale, y + row_idx * scale, scale, scale, color)

def draw_glow_bar(lcd, x, y, w, h, pct, color, glow_color):
    """Draw a bar with a subtle glow border and white highlight."""
    # Outer glow / border
    lcd.fill_rect(x - 1, y - 1, w + 2, h + 2, glow_color)
    lcd.fill_rect(x, y, w, h, COLOR_OBSIDIAN)
    
    fill_w = int(w * min(pct, 100) / 100)
    if fill_w > 0:
        lcd.fill_rect(x, y, fill_w, h, color)
        # 3D Highlight top edge
        lcd.fill_rect(x, y, fill_w, 1, ILI9341Parallel.WHITE)

def draw_ui_static(lcd):
    """Draw the static elements of the UI once."""
    W = lcd.WIDTH
    H = lcd.HEIGHT

    # 1. Background
    lcd.fill_screen(COLOR_OBSIDIAN)

    # 2. Header Panel
    lcd.fill_rect(0, 0, W, 40, COLOR_GLASS_PANEL)
    lcd.draw_string(15, 10, "SYSTEM // MONITOR", COLOR_NEON_CYAN, bg=COLOR_GLASS_PANEL, scale=2)
    lcd.draw_hline(0, 40, W, COLOR_NEON_CYAN) # Neon divider

    # 3. Modules Layout (Static Labels & Icons)
    module_y = 55
    module_h = 60

    # --- CPU MODULE STATIC ---
    draw_icon(lcd, 15, module_y, ICON_CPU, COLOR_NEON_CYAN, scale=3)
    lcd.draw_string(50, module_y, "CPU PERFORMANCE", ILI9341Parallel.WHITE, scale=1)

    # --- RAM MODULE STATIC ---
    module_y += module_h
    draw_icon(lcd, 15, module_y, ICON_RAM, COLOR_NEON_MAGENTA, scale=3)
    lcd.draw_string(50, module_y, "MEMORY UTILIZATION", ILI9341Parallel.WHITE, scale=1)

    # --- TEMP MODULE STATIC ---
    module_y += module_h
    draw_icon(lcd, 15, module_y, ICON_TEMP, COLOR_NEON_ORANGE, scale=3)
    lcd.draw_string(50, module_y, "THERMAL STATUS", ILI9341Parallel.WHITE, scale=1)
    
    # 4. Footer
    lcd.fill_rect(0, H-25, W, 25, COLOR_GLASS_PANEL)
    lcd.draw_string(10, H-18, "RPi 5 // 8-BIT PARALLEL", ILI9341Parallel.LIGHT_GREY, bg=COLOR_GLASS_PANEL, scale=1)

def update_ui_dynamic(lcd, stats):
    """Update only the dynamic numbers and progress bars."""
    W = lcd.WIDTH
    
    # Update Time
    lcd.draw_string(W-100, 15, time.strftime("%H:%M:%S"), COLOR_NEON_CYAN, bg=COLOR_GLASS_PANEL, scale=1)

    # Collect Stats
    cpu = stats.cpu_percent()
    ram = stats.ram_percent()
    temp = stats.cpu_temp()

    module_y = 55
    module_h = 60

    # --- CPU MODULE DYNAMIC ---
    # Draw string with background color to overwrite previous text
    val_str = f"{cpu:3.0f}%"
    lcd.draw_string(W-65, module_y, val_str, COLOR_NEON_CYAN, bg=COLOR_OBSIDIAN, scale=2)
    draw_glow_bar(lcd, 50, module_y+20, W-75, 12, cpu, COLOR_NEON_CYAN, COLOR_GLOW_CYAN)

    # --- RAM MODULE DYNAMIC ---
    module_y += module_h
    val_str = f"{ram:3.0f}%"
    lcd.draw_string(W-65, module_y, val_str, COLOR_NEON_MAGENTA, bg=COLOR_OBSIDIAN, scale=2)
    draw_glow_bar(lcd, 50, module_y+20, W-75, 12, ram, COLOR_NEON_MAGENTA, COLOR_GLOW_MAGENTA)

    # --- TEMP MODULE DYNAMIC ---
    module_y += module_h
    if temp:
        temp_str = f"{temp:4.1f}C"
        t_color = COLOR_NEON_ORANGE
    else:
        temp_str = " N/A "
        t_color = ILI9341Parallel.LIGHT_GREY

    lcd.draw_string(W-95, module_y, temp_str, t_color, bg=COLOR_OBSIDIAN, scale=2)
    draw_glow_bar(lcd, 50, module_y+20, W-75, 12, min(temp or 0, 100), COLOR_NEON_ORANGE, rgb565(80, 40, 0))


# ─────────────────────────────────────────────
#  Entry Point
# ─────────────────────────────────────────────
def main():
    lcd = None
    stats = SystemStats()

    def signal_handler(sig, frame):
        nonlocal lcd
        print("\nShutting down…")
        if lcd:
            lcd.cleanup()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print("═" * 50)
    print("  ILI9341 8-Bit Parallel — System Stats Monitor")
    print("═" * 50)
    print("  Data pins D0-D7 : GPIO 17,18,27,22,23,24,25,4")
    print("  CS=8  CD/RS=7  WR=10  RST=11  RD=9 (HIGH)")
    print("  Display: 320×240 landscape  RGB565")
    print("  Refresh: every 2 seconds")
    print("  Press Ctrl+C to exit cleanly")
    print("═" * 50)

    try:
        lcd = ILI9341Parallel()
        print("[OK] Display initialized")
        
        # Draw static elements only once
        draw_ui_static(lcd)

        while True:
            # Update only changing elements every 2 seconds
            update_ui_dynamic(lcd, stats)
            time.sleep(2)

    except KeyboardInterrupt:
        print("\nShutting down…")
    except Exception as e:
        print(f"\n[ERROR] {e}")
        import traceback
        traceback.print_exc()
    finally:
        if lcd:
            lcd.cleanup()
            print("[OK] GPIO cleaned up")


if __name__ == "__main__":
    main()
