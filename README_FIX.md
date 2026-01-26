# Project Fixes & Setup Guide

I have made several updates to ensure the Website and Tablet (Flutter) code work together locally.

## 1. Website Setup (`AdscreenWebsite copy`)

The website requires a few environment variables to function correctly, especially for Firebase.

1.  Open `AdscreenWebsite copy/.env`.
2.  Fill in the `VITE_FIREBASE_...` variables with your actual Firebase project configuration. You can find these in your Firebase Console > Project Settings.
3.  (Optional) Update `GEMINI_API_KEY` if you want the AI Chatbot to work.

### Running the Website
Open a terminal in `AdscreenWebsite copy/` and run:

```bash
# Install dependencies
npm install

# Start the Backend Server (Port 3000)
npm start
```

To run the Frontend in development mode (with hot reload):
```bash
# In a separate terminal
npm run dev
```

## 2. Tablet App Setup (`AdscreenAndroid App`)

I have updated the configuration to point to the local server by default.

### Configuration
Check `lib/config/server_config.dart`.
- `useLocal` is set to `true`.
- It points to `http://10.0.2.2:3000` which is the special IP for the Android Emulator to access your computer's localhost.
- If you are using a physical device, you must change this to your computer's LAN IP (e.g., `http://192.168.1.5:3000`).

### Running the App
Open the project in VS Code or Android Studio and run:

```bash
flutter pub get
flutter run
```

## 3. One-Click Start Script

I have created a script `start_all.sh` that will start the website server and the Flutter app for you.

**First Time Setup:**
Since you don't have Flutter installed, run this script first to download and configure it:
```bash
./setup_flutter.sh
```

**Then, to run the app:**
```bash
./start_all.sh
```

## Summary of Changes
- **Flutter**: Updated `ServerConfig` to support local development.
- **System**: Added `setup_flutter.sh` to install Flutter automatically.
- **System**: Updated `local.properties` with correct macOS paths.- **Flutter**: Fixed `AdService` to prevent socket re-initialization issues.
- **Website**: Added placeholders for missing Firebase config in `.env`.
