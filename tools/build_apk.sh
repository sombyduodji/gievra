#!/bin/bash
# Julkaisu-APK (arm64) versiolla X.Y.Z.VVVVKKPP.N: Gievra-<versio>-arm64.apk kansioon $GIEVRA_DIST (oletus build/dist).
set -e
cd "$(dirname "$0")/.."
# Käännetään neutraalista polusta (/mnt), jottei koneen hakemistopolku (käyttäjänimi) tallennu APK:hon.
# Gradle ilman taustaprosessia: muualla käynnistetty daemon ei näe /mnt-liitosta.
if [ -z "$GIEVRA_NEUTRAL" ] && [ "$(pwd)" != /mnt ] && unshare --user --map-root-user --mount true 2>/dev/null; then
    DIST=$(realpath -m "${GIEVRA_DIST:-build/dist}")
    exec unshare --user --map-root-user --mount sh -c "mount --bind '$(pwd)' /mnt && cd /mnt && \
        GIEVRA_NEUTRAL=1 GRADLE_OPTS='-Dorg.gradle.daemon=false' HOME='$HOME' GRADLE_USER_HOME='${GRADLE_USER_HOME:-$HOME/.gradle}' GIEVRA_DIST='$DIST' \
        bash tools/build_apk.sh"
fi
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
