# Adscreen Belgium

Adscreen Belgium is the Belgian deployment of the Adscreen interactive in-vehicle
advertising platform. The codebase is a Flutter app with two runtime targets:

- **Android tablet kiosk** — the customer-facing screen mounted in the vehicle.
- **Web admin dashboard** — operator console for managing devices, ads, and live telemetry.

This repo mirrors the structure of [adscreen.az](https://adscreen.az) (Azerbaijan)
and shares the same backend contract; only locale, branding, and regional defaults
differ.

## Quick start

```bash
flutter pub get
# Run the Android kiosk
flutter run

# Run the web admin (Chrome)
flutter run -d chrome

# Production web build (output: build/web/)
flutter build web --release
```

## Web deployment — Vercel

The web admin is deployed as a static site to Vercel. The repository ships a
[`vercel.json`](./vercel.json) that builds the Flutter web target via
[`scripts/vercel_build.sh`](./scripts/vercel_build.sh) and serves
`build/web/` with SPA rewrites.

To deploy:

```bash
# One-time
vercel login
vercel link

# Trigger a production deploy
vercel --prod
```

Or push to the GitHub repo connected to Vercel
(<https://github.com/MustafazadaAghasalim/adscreenbe>) and Vercel will build on
every push to `main`.

## Localisation

Supported locales: **nl** (Dutch — default), **fr** (French), **en** (English).
Translation files live in [`assets/translations/`](./assets/translations/).

## Regional defaults

- Backend host: `https://adscreen.be`
- MQTT host: `adscreen.be`
- Phone country code: `+32` (Belgium)
- Timezone: `Europe/Brussels` (DST-aware)
- Geofence zones: Brussels Center, Antwerp Center, Brussels Airport

Update the placeholder navbar phone `+32 2 123 45 67` in
[`lib/services/device_settings_service.dart`](./lib/services/device_settings_service.dart)
and [`lib/ui/kiosk_screen.dart`](./lib/ui/kiosk_screen.dart) once the real
support line is available.
