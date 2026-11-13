#!/bin/bash
set -euo pipefail
unset JAVA_TOOL_OPTIONS
cd "$(dirname "$0")"
SDK=/usr/lib/android-sdk/platforms/android-23/android.jar
rm -rf build; mkdir -p build/gen build/classes build/dex
aapt package -f -m -J build/gen -M AndroidManifest.xml -S res -I $SDK
javac --release 8 -nowarn -Xlint:-options -d build/classes -classpath $SDK $(find src build/gen -name '*.java')
dalvik-exchange --dex --output=build/dex/classes.dex build/classes
aapt package -f -M AndroidManifest.xml -S res -A assets -I $SDK -F build/unsigned.apk -0 woff2
(cd build/dex && aapt add ../unsigned.apk classes.dex >/dev/null)
zipalign -f -p 4 build/unsigned.apk build/aligned.apk
[ -f debug.keystore ] || keytool -genkeypair -keystore debug.keystore -storepass android -keypass android -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 10000
apksigner sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android --out build/aurite-front-3d.apk build/aligned.apk
apksigner verify -v build/aurite-front-3d.apk | head -5
