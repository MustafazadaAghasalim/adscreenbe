#!/bin/bash

echo "🚀 Setting up Local Development Environment for Adscreen..."

# 1. Setup ADB Reverse for USB Debugging
echo "🔌 Configuring USB Debugging connection..."
if command -v adb &> /dev/null; then
    adb reverse tcp:3000 tcp:3000
    echo "✅ ADB Reverse (tcp:3000) configured."
else
    echo "⚠️ ADB command not found. Make sure Android SDK Platform-Tools are in your PATH."
    echo "   If you have Android Studio, it's usually in ~/Library/Android/sdk/platform-tools"
fi

# 2. Start the Website Server
echo "🌐 Starting Website Server..."
cd "AdscreenWebsite copy"

if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

if [ ! -d "dist" ]; then
    echo "🏗️ Building frontend..."
    npm run build
fi

echo "✅ Starting Server on http://localhost:3000"
echo "   Open this URL in your browser to upload ads."
npm start
