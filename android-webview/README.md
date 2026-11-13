# Android WebView wrapper

Packages the 3D web version (`../web-3d/index.html`) as an offline Android app
(package `io.aurite.front3d`, minSdk 23, target 34, landscape, immersive).

- `assets/www/` holds a copy of the web game adapted for offline use: three.js r128 is bundled
  as `three.min.js` and the Google Fonts are replaced by `fonts.css` + local `.woff2` files.
- `src/io/aurite/front/MainActivity.java` is the full-screen WebView activity.
- `build.sh` builds without Gradle, using the Ubuntu packages
  `android-sdk-platform-23 aapt dalvik-exchange zipalign apksigner` (plus a JDK).
  Output: `build/aurite-front-3d.apk`.

## Updating the game
Copy `../web-3d/index.html` to `assets/www/index.html`, then point the three.js `<script>` at
`three.min.js`, swap the Google Fonts `<link>` for `fonts.css`, make sure it has a doctype and
viewport meta, bump `versionCode` in `AndroidManifest.xml`, and run `./build.sh`.

## debug.keystore
This is a **debug-only** key (alias `androiddebugkey`, passwords `android`). It is committed on
purpose: Android only installs an update over an existing app when it is signed with the same key,
and both this APK and the Godot APK (`../godot`) were signed with it. Do not use it for a Play Store
release; create a separate release key and keep that out of the repo.
