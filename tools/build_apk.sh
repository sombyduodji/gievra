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
# Dart-symbolit erilleen (--split-debug-info, ilman --obfuscate: avoin lähdekoodi): APK pienenee. Symbolit ja R8:n
# mapping.txt talteen versiokohtaisesti symbols/<versio>/ (git-ignore, ei julkaista), jotta puhelimen kaatumisloki
# saadaan luettavaksi: tools/symbolize.py <versio> loki.txt
SYM=$(pwd)/symbols/$NAME
mkdir -p "$SYM"  # ei tyhjennetä: välimuistista tuleva koonti ei kirjoita symboleja uudelleen (sama koodi = samat symbolit)
flutter build apk --release --split-per-abi --target-platform android-arm64 --split-debug-info="$SYM" $ARGS
cp build/app/outputs/mapping/release/mapping.txt "$SYM/" 2>/dev/null || echo "Varoitus: mapping.txt puuttuu"
cp build/app/outputs/native-debug-symbols/release/native-debug-symbols.zip "$SYM/" 2>/dev/null || true
ls "$SYM"/*.symbols >/dev/null 2>&1 || { echo "Dart-symbolit puuttuvat ($SYM)"; exit 1; }
(cd android && ./gradlew --stop >/dev/null 2>&1 || true)
DIST=${GIEVRA_DIST:-build/dist}
mkdir -p "$DIST"
OUT=$DIST/Gievra-${NAME}${GIEVRA_APK_SUFFIX:-}-arm64.apk  # GIEVRA_APK_SUFFIX: esim. -uusi-ulkoasu (sama versio, eri tiedostonimi)
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$OUT"
python3 tools/check_apk_manifest.py "$OUT"
echo "Valmis: $OUT"
