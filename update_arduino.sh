#!/bin/bash
set -e

export PATH=$PATH:/home/zynorex/bin

echo "=== Installing ArduinoJson Library ==="
arduino-cli lib install "ArduinoJson"

echo "=== Compiling Sketch ==="
mkdir -p /home/zynorex/arduino_stats_display
cp arduino_stats_display.ino /home/zynorex/arduino_stats_display/ || true
arduino-cli compile --fqbn arduino:avr:mega /home/zynorex/arduino_stats_display

echo "=== Detecting Arduino Mega Port ==="
PORT=$(arduino-cli board list | grep -i "mega" | awk '{print $1}')
if [ -z "$PORT" ]; then
    PORT=$(arduino-cli board list | grep "tty" | awk '{print $1}' | head -n 1)
fi

if [ -z "$PORT" ]; then
    echo "ERROR: Could not detect Arduino Mega port!"
    arduino-cli board list
    exit 1
fi

echo "Found Arduino on port: $PORT"

echo "=== Uploading to Arduino Mega ==="
arduino-cli upload -p $PORT --fqbn arduino:avr:mega /home/zynorex/arduino_stats_display

echo "=== Restarting Python JSON Serial Sender ==="
sudo pkill -9 -f python3 || true
python3 /home/zynorex/serial_stats.py > /dev/null 2>&1 &

echo "=== UPDATE COMPLETE ==="
