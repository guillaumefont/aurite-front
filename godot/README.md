# Aurite Front (Godot 4 port)

The low-poly 3D RTS from `aurite-front-3d/index.html`, rewritten in Godot 4.7 with GDScript.
Same map generator, units, buildings, factions, AI and skirmish, plus two 8-mission campaigns:
*Embers of the Pact* (play the Ashen Pact, red) and *Iron Tide* (play the Vanguard, blue, a year later), with heroes,
hand-shaped maps in six landscapes and objectives beyond destroying a base (escort, rescue, capture, hold, hunt, survive, mine).

## Install on Android
`build/aurite-front.apk` is a debug-signed APK (package `io.aurite.frontgodot`, arm64 + armv7, Android 6.0+).
Copy it to the phone and open it (allow "install unknown apps"). It installs next to the older WebView app.

## Controls
- **Touch**: drag to scroll, pinch to zoom, tap a unit to select, tap ground or an enemy to order.
  Round button = box-select mode. **Double-tap a unit** selects every unit of that type on screen.
  **Hold, then drag** at the destination to place a formation along the drag line; it faces away from you for a left-to-right drag. You see a preview while dragging.
  Long-press a build button to cancel it.
- **Mouse**: click to select or command, drag to box-select, **double-click** for the whole type,
  **right-drag** to face a formation, middle-drag or WASD to scroll, wheel to zoom, right-click a build button to cancel.

## What changed from the web version
- Colours follow the faction: the Vanguard is blue, the Ashen Pact red.
- Fire is terrain-aware. Direct-fire weapons need a clear line over the terrain: units with a blocked shot move closer, and turrets pick another target. Mortars fly a real ballistic arc whose peak clears every hill on the way. A shell that meets a hillside bursts on it.
- Formation facing by drag (see controls).
- Buildings have more low-poly detail (windows, rails, pipes, fans, lamps, sandbags, a crane, a flag) and animations: they assemble inside a scaffold with a glowing cut line and sparks, come apart top-down when sold, and sink and tilt when destroyed. Harvesters throw aurite crystals into their bin and stream them into the refinery, which shows a floating "+N". The war factory door rolls up when a unit comes out.
- Sound effects and the march are pre-rendered from the same synth recipes (`tools/synth.py`).
  The calm and combat layers of the march crossfade with how hot the fighting is.

## Layout
- `scripts/data.gd`: units, buildings, factions, landscapes (autoload `D`)
- `scripts/campaign.gd`: both campaigns' missions; `scripts/mapgen.gd`: campaign map shapes
- `scripts/sim.gd`: the simulation: pathfinding (AStarGrid2D), combat, harvesting, production, AI, campaign goals
- `scripts/models.gd`: low-poly models built from primitives, baked to one vertex-colour mesh per moving part
- `scripts/view3d.gd`: terrain, water, decor, fog of war, entity sync, particles, camera
- `scripts/ui.gd`, `scripts/main.gd`: HUD, side panel, overlays, input gestures, game flow
- `scripts/audio.gd`: sound pool with stereo pan buses, music layers

## Build
```
godot --headless --import
godot --headless --export-debug "Android" build/aurite-front.apk
```
You need the Godot 4.7.2 export templates. Set `export/android/android_sdk_path` (it needs `build-tools/*/apksigner`)
and `debug_keystore` in the editor settings. This APK was signed with the same debug keystore as the WebView APK
(`aurite-front-3d/apk/android-wrapper-src.tgz`).

Tests: `godot --headless --path . tests/sim_test.tscn` (AI vs AI soak + every mission's setup). With a display,
`AF_SHOT=<dir> godot --path .` takes screenshots and `AF_INPUT=1` also replays touch gestures. `AF_MODE=menus` shoots each menu screen (start, skirmish, field manual, briefing, pause, end) instead. `AF_MODE=camp` shoots every campaign briefing and map. `AF_MODE=b` shoots every building model and the build, sell, collapse and harvesting animations.
