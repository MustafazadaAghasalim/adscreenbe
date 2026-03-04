#!/bin/bash

# Adscreen Tablet Deployment Script
# This script automatically installs dependencies and deploys the latest code to your connected tablet.

echo "🚀 Starting Adscreen Tablet Deployment..."

# Ensure we are in the correct directory
cd "$(dirname "$0")"

echo "📂 Current Directory: $(pwd)"

# Set Flutter Path explicitly (Found by Auto-Detection)
FLUTTER_BIN="/Users/salim/development/flutter/bin/flutter"

echo "📦 Installing Dependencies..."
"$FLUTTER_BIN" pub get

echo "📱 Detecting Devices..."
"$FLUTTER_BIN" devices

echo "🚀 Building and Running on Tablet (Release Mode)..."
echo "⏳ This might take a few minutes..."

"$FLUTTER_BIN" run --release

if [ $? -eq 0 ]; then
    echo "✅ Success! Adscreen is running on your tablet."
else
    echo "❌ Deployment Failed. Please check the errors above."
fi
