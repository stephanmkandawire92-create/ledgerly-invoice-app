#!/bin/sh
set -eu

# Keep the Vercel build reproducible and aligned with the project's Flutter toolchain.
FLUTTER_VERSION="3.47.2"
FLUTTER_DIR="${TMPDIR:-/tmp}/flutter-sdk-${FLUTTER_VERSION}"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"

flutter --version
flutter pub get
flutter build web --release

# Keep the existing same-origin auth return page available to Windows clients.
mkdir -p build/web/auth-callback
cp auth-callback/index.html build/web/auth-callback/index.html
