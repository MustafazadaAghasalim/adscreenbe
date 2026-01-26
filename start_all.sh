#!/bin/bash

# Add Flutter to PATH
export PATH="$PATH:$HOME/development/flutter/bin"

# 1. Start Website Server (Background)
echo "Starting Website Server..."
cd "AdscreenWebsite copy"
npm install
npm start &
WEBSITE_PID=$!
cd ..

echo "Website Server running (PID: $WEBSITE_PID)"

# 2. Run Flutter App
echo "Starting Flutter App..."
# Ensure local.properties is updated by flutter tool
flutter pub get
flutter run

# Cleanup when flutter app exits
kill $WEBSITE_PID
