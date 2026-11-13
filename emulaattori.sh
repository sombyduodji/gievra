#!/bin/sh
# Treenipäiväkirjan oma Android-emulaattori Dockerissa (vain /dev/kvm tarvitaan, ei Android Studiota).
# Erillinen Sátni FST:stä: oma kuva (treenipaivakirja-android-emu), oma SDK-kopio ja oma virtuaalilaite
# kansiossa ~/.cache/treenipaivakirja-build/android/emu.
#
# Käyttö:
#   ./emulaattori.sh kaynnista              käynnistää laitteen (luo sen ensimmäisellä kerralla) ja odottaa
#   ./emulaattori.sh asenna [APK]           asentaa APK:n (oletus build/app/outputs/flutter-apk/app-debug.apk)
#                                           ja käynnistää sovelluksen
#   ./emulaattori.sh kuva [PNG]             kuvakaappaus (oletus ~/.cache/treenipaivakirja-build/android/kuvat/)
#   ./emulaattori.sh napauta X Y            napautus näytön pikseleissä (1080 × 2400)
#   ./emulaattori.sh kirjoita TEKSTI        kirjoittaa tekstiä (ei ääkkösiä: adb input -rajoitus)
#   ./emulaattori.sh pyyhkaise X1 Y1 X2 Y2  pyyhkäisy (vieritys)
#   ./emulaattori.sh takaisin               Androidin takaisin-näppäin
#   ./emulaattori.sh tyhjenna               poistaa sovelluksen tiedot (ensimmäinen käynnistys uudelleen)
#   ./emulaattori.sh adb ARGS...            muu adb-komento
#   ./emulaattori.sh pysayta                pysäyttää laitteen
#   ./emulaattori.sh tila                   onko laite käynnissä
cd "$(dirname "$0")" || exit 1

WORK="${XDG_CACHE_HOME:-$HOME/.cache}/treenipaivakirja-build/android"
SYSTEM_IMAGE="system-images;android-35;google_apis;x86_64"
IMAGE=treenipaivakirja-android-emu
NAME=treeni-emu
AVD=treeni-dev
PACKAGE=fi.somby.gievra
ADB=/work/emu/sdk/platform-tools/adb

usage() { sed -n '/^# Käyttö:/,/^cd /p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1; }
running() { [ -n "$(docker ps -q -f "name=^$NAME\$")" ]; }
adb() {
    running || { echo "Laite ei ole käynnissä (./emulaattori.sh kaynnista)" >&2; exit 1; }
    docker exec "$NAME" "$ADB" "$@"
}

image() {  # kuva tarvittaessa tämän projektin Dockerfileistä
    docker image inspect "$IMAGE" >/dev/null 2>&1 && return
    docker build -q -t treenipaivakirja-android-build packaging/android >/dev/null &&
        docker build -q -t "$IMAGE" packaging/android/emulator >/dev/null
}

in_image() {
    docker run --rm --user "$(id -u):$(id -g)" --entrypoint "" -e HOME=/work/home \
        -e ANDROID_HOME=/work/emu/sdk -e ANDROID_SDK_ROOT=/work/emu/sdk -e ANDROID_AVD_HOME=/work/emu/avd \
        -v "$WORK":/work "$IMAGE" "$@"
}

setup() {
    mkdir -p "$WORK/emu/avd" "$WORK/home" "$WORK/kuvat" || exit 1
    if [ ! -x "$WORK/emu/sdk/emulator/emulator" ] || [ ! -d "$WORK/emu/sdk/system-images/android-35" ]; then
        echo "Asennetaan emulaattori ja järjestelmäkuva (kerran, ~5 Gt)..."
        in_image sh -c "yes | /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/work/emu/sdk --licenses >/dev/null &&
            /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/work/emu/sdk \
                emulator platform-tools 'cmdline-tools;latest' '$SYSTEM_IMAGE' >/dev/null" || exit 1
    fi
    if [ ! -f "$WORK/emu/avd/$AVD.ini" ]; then
        echo "Luodaan virtuaalilaite $AVD (Pixel 6, Android 15)..."
        in_image sh -c "echo no | /work/emu/sdk/cmdline-tools/latest/bin/avdmanager -s create avd \
            -n $AVD -k '$SYSTEM_IMAGE' -d pixel_6 >/dev/null" || exit 1
    fi
}

start() {
    if running; then echo "Laite on jo käynnissä"; return; fi
    image || exit 1
    setup
    docker rm -f "$NAME" >/dev/null 2>&1
    rm -f "$WORK/emu/avd/$AVD.avd/"*.lock
    mkdir -p "$WORK/emu/home-dev"
    # --group-add kvm: laite /dev/kvm ei peri isäntäkoneen ACL:ää, joten säiliön käyttäjä tarvitsee kvm-ryhmän
    docker run -d --name "$NAME" --device /dev/kvm --group-add "$(getent group kvm | cut -d: -f3)" \
        --user "$(id -u):$(id -g)" --entrypoint "" \
        -e HOME=/work/emu/home-dev -e ANDROID_HOME=/work/emu/sdk -e ANDROID_SDK_ROOT=/work/emu/sdk \
        -e ANDROID_AVD_HOME=/work/emu/avd \
        -v "$WORK":/work "$IMAGE" \
        /work/emu/sdk/emulator/emulator -avd "$AVD" -no-window -no-audio -no-boot-anim -no-metrics \
            -gpu swiftshader_indirect -memory 3072 >/dev/null || exit 1
    printf "Käynnistetään"
    i=0
    until [ "$(docker exec "$NAME" "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
        if ! running; then
            echo; echo "Emulaattori pysähtyi:"; docker logs "$NAME" 2>&1 | grep -E "FATAL|ERROR" | tail -5; exit 1
        fi
        i=$((i + 1)); [ $i -gt 120 ] && { echo; echo "Käynnistys ei valmistunut 10 minuutissa"; exit 1; }
        printf "."; sleep 5
    done
    # Suomi ja Suomen aika, jotta tervehdys ja päivämäärät näkyvät kuten puhelimessa
    docker exec "$NAME" "$ADB" shell "setprop persist.sys.locale fi-FI; setprop persist.sys.timezone Europe/Helsinki" >/dev/null 2>&1
    echo " valmis"
}

[ $# -ge 1 ] || usage
cmd=$1; shift
case "$cmd" in
    kaynnista) start ;;
    asenna)
        apk=${1:-build/app/outputs/flutter-apk/app-debug.apk}
        [ -f "$apk" ] || { echo "APK:ta ei löydy: $apk (flutter build apk --debug)"; exit 1; }
        running || start
        docker cp "$apk" "$NAME:/tmp/treeni.apk" >/dev/null || exit 1
        adb install -r /tmp/treeni.apk | tail -1
        adb shell am force-stop "$PACKAGE"
        adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 ;;
    kuva)
        out=${1:-$WORK/kuvat/$(date +%Y%m%d-%H%M%S).png}
        mkdir -p "$(dirname "$out")"
        sleep 1
        adb exec-out screencap -p > "$out" && echo "$out" ;;
    napauta) [ $# -eq 2 ] || usage; adb shell input tap "$1" "$2" ;;
    kirjoita) [ $# -eq 1 ] || usage; adb shell input text "$(printf %s "$1" | sed 's/ /%s/g')" ;;
    pyyhkaise) [ $# -eq 4 ] || usage; adb shell input swipe "$1" "$2" "$3" "$4" 400 ;;
    takaisin) adb shell input keyevent 4 ;;
    tyhjenna) adb shell pm clear "$PACKAGE" ;;
    adb) [ $# -ge 1 ] || usage; adb "$@" ;;
    pysayta)
        if running; then
            # Levyn välimuisti talteen ensin: muuten viimeisimmät tallennukset voivat jäädä tyhjiksi tiedostoiksi.
            adb shell sync >/dev/null 2>&1 || true
            docker exec "$NAME" "$ADB" emu kill >/dev/null 2>&1
            sleep 3
            docker rm -f "$NAME" >/dev/null && echo "Pysäytetty"
        fi ;;
    tila)
        if running; then
            v=$(docker exec "$NAME" "$ADB" shell dumpsys package "$PACKAGE" 2>/dev/null | grep -m1 versionName | tr -d ' ')
            echo "Käynnissä ${v:-(sovellusta ei asennettu)}"
        else
            echo "Pysäytetty"
        fi ;;
    *) usage ;;
esac
