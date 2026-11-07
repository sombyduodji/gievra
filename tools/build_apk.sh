#!/bin/bash
# Julkaisu-APK (arm64) versiolla X.Y.Z.VVVVKKPP.N: Gievra-<versio>-arm64.apk kansioon $GIEVRA_DIST (oletus build/dist).
set -e
cd "$(dirname "$0")/.."
[ -f ~/sdk/env.sh ] && source ~/sdk/env.sh
ARGS=$(python3 tools/version.py --flutter)
NAME=$(echo "$ARGS" | sed -E 's/--build-name=([^ ]+).*/\1/')
flutter build apk --release --split-per-abi --target-platform android-arm64 $ARGS
(cd android && ./gradlew --stop >/dev/null 2>&1 || true)
DIST=${GIEVRA_DIST:-build/dist}
mkdir -p "$DIST"
OUT=$DIST/Gievra-${NAME}-arm64.apk
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$OUT"
echo "Valmis: $OUT"
