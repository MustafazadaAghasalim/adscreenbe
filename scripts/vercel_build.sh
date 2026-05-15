#!/usr/bin/env bash
# Vercel build script for Adscreen Belgium (Flutter web).
#
# Vercel build images don't ship Flutter, so we install it from the stable
# channel, then run `flutter build web` and emit the static site to
# `build/web/` (vercel.json points outputDirectory at this path).

set -euo pipefail

# Verbose so the Vercel build log clearly shows what stage failed.
echo "==> Adscreen Belgium :: Vercel build start"
echo "==> $(date -u) | $(uname -a)"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.24.5}"
FLUTTER_DIR="${HOME}/.flutter-${FLUTTER_VERSION}"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "==> Installing Flutter ${FLUTTER_VERSION} into ${FLUTTER_DIR}"
  mkdir -p "${FLUTTER_DIR}"

  echo "==> Downloading ${FLUTTER_URL}"
  curl -fSL --retry 3 --retry-delay 5 "${FLUTTER_URL}" -o /tmp/flutter.tar.xz

  echo "==> Extracting Flutter SDK"
  tar -xJf /tmp/flutter.tar.xz -C "${FLUTTER_DIR}" --strip-components=1
  rm -f /tmp/flutter.tar.xz
else
  echo "==> Flutter ${FLUTTER_VERSION} cache hit at ${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"

# Flutter's own toolchain is a git checkout under the hood; mark it safe so
# `flutter --version` doesn't fail with "fatal: detected dubious ownership".
git config --global --add safe.directory "${FLUTTER_DIR}" || true
git config --global --add safe.directory "${FLUTTER_DIR}/bin/cache/pkg/sky_engine" || true

echo "==> Flutter version"
flutter --version

flutter config --no-analytics --no-cli-animations >/dev/null 2>&1 || true

echo "==> Resolving Dart packages"
flutter pub get

echo "==> Building web bundle (release)"
flutter build web --release

echo "==> Build output:"
ls -lah build/web | head -40
echo "==> Adscreen Belgium :: Vercel build done"
