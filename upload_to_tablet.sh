#!/bin/bash

# Adscreen Robust Tablet Deployment Script
# This script ensures a clean build and correct installation on your connected tablet.

echo "🚀 Starting Robust Adscreen Deployment..."

# 1. Setup Paths
FLUTTER_BIN="/Users/salim/development/flutter/bin/flutter"
ADB_BIN="/Users/salim/Library/Android/sdk/platform-tools/adb"
PACKAGE_NAME="com.example.adscreen"

# Ensure we are in the project root
cd "$(dirname "$0")"
echo "📂 Working Directory: $(pwd)"

# 2. Check for connected devices
echo "📱 Checking for connected devices..."
DEVICES=$("$ADB_BIN" devices | grep -v "List" | grep "device")

if [ -z "$DEVICES" ]; then
    echo "❌ Error: No tablet detected. Please connect your tablet via USB and enable USB Debugging."
    exit 1
fi

echo "✅ Device(s) detected:"
echo "$DEVICES"

# 3. Clean and Prep
# echo "🧹 Cleaning project artifacts..."
# "$FLUTTER_BIN" clean

# echo "📦 Fetching dependencies..."
# "$FLUTTER_BIN" pub get

# 4. Build Release APK
echo "🏗️ Building Release APK..."
"$FLUTTER_BIN" build apk --release

if [ $? -ne 0 ]; then
    echo "❌ Error: Build failed. Please check the logs above."
    exit 1
fi

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

# 5. Install to Tablet
echo "📲 Installing APK to tablet..."
"$ADB_BIN" install -r "$APK_PATH"

if [ $? -ne 0 ]; then
    echo "❌ Error: Installation failed."
    exit 1
fi

# 6. Launch the App
echo "🚀 Forcing restart of Adscreen..."
"$ADB_BIN" shell am force-stop "$PACKAGE_NAME"
sleep 1
"$ADB_BIN" shell am start -n "$PACKAGE_NAME/$PACKAGE_NAME.MainActivity"

echo "✅ Deployment Successful! Adscreen is now restarting on your tablet."
