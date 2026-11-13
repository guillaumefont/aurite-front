# Aurite Front

An original, old-school real-time strategy game for mobile and desktop: two factions
(Vanguard and Ashen Pact) fight over aurite crystals with infantry, vehicles, aircraft and base building.
Skirmish against the AI or play the 5-mission campaign. Touch-first controls, with mouse support.

All art is low-poly and built procedurally; sound effects and the military march are synthesized.

## Versions

| Folder | What it is | Status |
| --- | --- | --- |
| [`godot/`](godot/) | Godot 4.7 (GDScript) port, exports to Android | **Main version** |
| [`web-3d/`](web-3d/) | Low-poly 3D browser version, one HTML file using three.js r128 | Reference / playable in a browser |
| [`android-webview/`](android-webview/) | Android app wrapping `web-3d` in a WebView, built without Gradle | Older Android build |
| [`web-2d/`](web-2d/) | The original 2D canvas prototype, one HTML file | Archived |

## Quick start

- **Godot**: open `godot/project.godot` in Godot 4.7.2, or run it with `godot --path godot`.
  Build and test instructions are in [`godot/README.md`](godot/README.md).
- **Web**: open `web-3d/index.html` (or `web-2d/index.html`) in a browser. The 3D version loads
  three.js and fonts from CDNs, so it needs a network connection.
- **Android WebView**: see [`android-webview/README.md`](android-webview/README.md).

## Signing

Both Android builds are debug-signed with `android-webview/debug.keystore`, a debug-only key that is
committed so that new builds install over existing ones. APKs and other build outputs are not
committed; release keys must never be.
