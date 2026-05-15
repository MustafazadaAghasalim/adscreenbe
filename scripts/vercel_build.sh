#!/usr/bin/env bash
# Vercel build script for Adscreen Belgium (Flutter web).
#
# Vercel build images don't ship Flutter, so we install it from the stable
# channel, then run `flutter build web` and emit the static site to
# `build/web/` (vercel.json points outputDirectory at this path).

set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.24.5}"
FLUTTER_DIR="${HOME}/.flutter-${FLUTTER_VERSION}"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "==> Installing Flutter ${FLUTTER_VERSION} into ${FLUTTER_DIR}"
  mkdir -p "${FLUTTER_DIR}"
  curl -fsSL \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    -o /tmp/flutter.tar.xz
  tar -xJf /tmp/flutter.tar.xz -C "${FLUTTER_DIR}" --strip-components=1
  rm -f /tmp/flutter.tar.xz
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"

# Vercel runs as a non-git user; mark the working tree safe so Flutter's
# internal git ops succeed inside its own toolchain checkout.
git config --global --add safe.directory "${FLUTTER_DIR}" || true

flutter --version
flutter config --no-analytics
flutter pub get
flutter build web --release --web-renderer canvaskit
