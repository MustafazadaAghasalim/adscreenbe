#!/bin/bash

# Exit on error
set -e

# Add Flutter to PATH
export PATH="$PATH:$HOME/development/flutter/bin"

echo "🚀 Starting Full Build and Deployment Process..."

# 1. Build Flutter App (Android APK)
echo "📱 Building Flutter Android APK..."
flutter pub get
flutter build apk --release
echo "✅ Flutter APK built at: build/app/outputs/flutter-apk/app-release.apk"

# 2. Build and Deploy Website
echo "🌐 Building and Deploying Website..."
cd "AdscreenWebsite copy"
chmod +x deploy.sh
./deploy.sh
cd ..

echo "✅ Full Deployment Complete!"
