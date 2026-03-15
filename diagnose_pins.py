#!/usr/bin/env python3
import time
import sys

try:
    import RPi.GPIO as GPIO
except ImportError:
    print("Error: RPi.GPIO not found.")
    sys.exit(1)

# Mapping from the user request
DATA_PINS = [17, 18, 27, 22, 23, 24, 25, 4] # D0, D1, D2, D3, D4, D5, D6, D7
CONTROL_PINS = {
    "CS": 8,
    "RS/CD": 7,
    "WR": 10,
    "RST": 11,
    "RD": 9
}

def setup():
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    for pin in DATA_PINS:
        GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)
    for name, pin in CONTROL_PINS.items():
        GPIO.setup(pin, GPIO.OUT, initial=GPIO.HIGH)

def test_pins_sequentially():
    print("Starting sequential pin test.")
    print("I will toggle each pin HIGH for 2 seconds, then LOW.")
    
    # Test Data Pins
    for i, pin in enumerate(DATA_PINS):
        print(f"Toggling D{i} (GPIO {pin}) ...")
        GPIO.output(pin, GPIO.HIGH)
        time.sleep(2)
        GPIO.output(pin, GPIO.LOW)
    
    # Test Control Pins
    for name, pin in CONTROL_PINS.items():
        print(f"Toggling {name} (GPIO {pin}) (Active LOW, will go LOW now) ...")
        GPIO.output(pin, GPIO.LOW)
        time.sleep(2)
        GPIO.output(pin, GPIO.HIGH)

    print("Diagnostic complete.")

if __name__ == "__main__":
    try:
        setup()
        test_pins_sequentially()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        GPIO.cleanup()
