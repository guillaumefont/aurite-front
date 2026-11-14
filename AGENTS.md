# Notes for agents

## Pull requests

- Work on a branch and open a PR against `main`.
- **Merge your PR as soon as CI is green, without asking** (Builds and Headless sim pass on the PR's latest
  commit, and it has no merge conflict). Guillaume, 2026-11-13. Never merge on red or pending CI,
  and never skip or disable a test to get green.
- Add a **Try it** section to the PR body with the preview APK, once the PR number is known:

  ```
  ## Try it
  - Android APK: https://guillaumefont.github.io/aurite-front/pr/<N>/aurite-front.apk
  ```

## Layout

- `godot/`: the main version, Godot 4.7.2 (GDScript), exported to Android. Renderer: Mobile (Vulkan), with automatic fallback
  to GL Compatibility on devices without Vulkan (`rendering_device/fallback_to_opengl3`). Some phone GL drivers
  drew huge stretched triangles in Compatibility, so keep Mobile as the default and keep MultiMesh buffers fully
  initialised (`View3D._batch` uploads zeros first and hides empty batches).
  Test locally with `xvfb-run godot --path godot` (needs `mesa-vulkan-drivers`); add
  `--rendering-method gl_compatibility` to check the fallback.
  See `godot/README.md` for the scripts and controls.
- `web-3d/`: the low-poly 3D browser version the port is based on (one HTML file). Reference only.
- `android-webview/`: older Android WebView wrapper around `web-3d` (`build.sh`, no Gradle). Not built by CI.
- `web-2d/`: original 2D prototype. Archived.
- The game is called "Aurite Front". Team colours follow the faction (`D.FCOL`, set per match by `D.set_team_colors`):
  the Vanguard is blue `#3fb4e8`, the Ashen Pact red `#e0423a`, the Hollow Choir green `#3cc457`. Guillaume, 2026-11-14: the game is red themed, so
  campaign I is played as the (red) Ashen Pact and campaign II as the Vanguard.

## Hollow Choir (third faction, skirmish only so far)

- Faction-only types have `fac: "choir"`; shared types the Choir does without have `no: ["choir"]`, and
  `D.sub(fac, type)` gives the faction's stand-in (`refinery` → `garden`, `rifle` → `thrall`, `arty` → `geode`).
  Requirements go through `Sim.req_of`, so `factory` (needs a refinery) unlocks from a garden. Use `D.sub` in AI and
  start-up code instead of naming shared types.
- Tunnels: `Sim.plan_tunnel` (from `group_move`), `tunnel_tick`, `_emerge`. A unit in a tunnel has `intun > 0`: it is
  hidden, unselectable and skipped by separation. `under` (tunnels and moving sappers) makes a unit untargetable and
  undamageable. Handle both in any new targeting or selection code.
- Shard fields are `Sim.fields`, drawn in `View3D.draw_parts`. Unit limits (`lim`, the Cantor) go through `Sim.at_limit`.
- `tests/sim_test.gd` `choir_tests()` covers AI soaks with the Choir on each side, gardens, tunnels, burrowing,
  geode fields, the aura, the limit and the Chorus Well. In AI-vs-AI runs (2026-11-14) the Choir won 5 of 12, lost 6, drew 1.
- New sounds (`shard`, `geode`, `burrow`, `ack_choir`) are in `tools/synth.py`. Re-rendering every sound on another
  numpy version changes the old files slightly, so copy only the new ones into `sfx/`.

## Building upgrades (Guillaume 2026-11-14: "allow structure upgrade, for example the reactor to a superreactor")

- `D.UPG[type]` holds each upgrade (cost, time, req, say, plus the stats it replaces); `D.BLD2[type]` is the merged
  upgraded def. An upgraded building keeps its `type` (so counts, requirements and the AI build order still work) and
  gets `b.lv = 2`, `b.d = D.BLD2[type]`. Read stats from `b.d`, not `D.BLD[b.type]`, in any new building code.
- `Sim.start_upgrade` / `cancel_upgrade` / `upd_upgrade` (paid over time like a queue) / `finish_upgrade`; `upg_block`
  gives the reason a building cannot upgrade. Effects: `d.pwr`, `d.yield` (refinery deliveries, garden harvests),
  `d.speed` via `Sim.prod_speed` (training speed of the producer's category), weapon stats.
- Models: `Models.get_model(..., lv)` adds `_upgraded()` parts; the view rebuilds a building's model when `e.lv`
  changes and plays a reveal (`View3D._anim_upgrade`). `AF_MODE=up AF_SHOT=dir` shoots every base/upgraded pair per
  faction, a running upgrade, the reveal and the button.
- AI: upgrades in skirmish, in campaigns only on Hard (`ai_ups` in `ai_think`), to keep Normal beatable.
  `upgrade_tests()` in `tests/sim_test.gd` checks this and each effect.

## Self-update (`godot/scripts/updater.gd`, Guillaume 2026-11-14)

- Installed games update themselves: the `Updater` autoload (listed FIRST in `project.godot`) fetches `version.json`
  from the build's Pages folder on launch and on resume, downloads the newer `aurite-front.pck` into `user://update/`,
  and mounts it at the next launch in its `_init`, before any other game script loads. The menu's top-right line shows
  the build and status; tapping it restarts into a downloaded update. Saves in `user://` are untouched.
- A pack only fits its "shell": the engine version, `project.godot`, `export_presets.cfg`, `updater.gd`, the icons and
  the splash (CI hashes them into `build.json`/`version.json`). Changing any of them means installed games ask for the
  new APK instead, so avoid touching them casually. `updater.gd` must not use other game scripts or classes.
- A pack that fails to start twice is dropped (back to the APK). Locally `build.json` has build 0, so the updater is
  off; `AF_UPDATE=1` forces it on (with a `url` in `build.json`), `AF_UPDATE=0` turns it off.

## CI (`.github/workflows/`)

- **Headless sim** (`sim.yml`): `godot --headless --path godot tests/sim_test.tscn`. Godot exits 0 on script
  errors, so the job greps the log for script/parse errors and for `SIM TEST DONE`, the test's last line.
  Keep that line last when you change the test, and add a step there for any new test.
- **Builds** (`build.yml`): exports `godot/` with the Android preset as a release APK, signed with the committed
  `android-webview/debug.keystore` (or an `ANDROID_DEBUG_KEYSTORE_BASE64` secret). versionCode is
  `100 + run number`, so do not bump `version/code` by hand. It publishes to the `gh-pages` branch with
  `.github/publish-pages.sh`: `main` at the site root, PR N under `pr/N/` (removed when the PR closes),
  each with `aurite-front.apk`, a download page (`.github/pages/index.html`) and `web-3d/`.
  The APK is also a run artifact.
- **Deploy Pages** (`pages.yml`): deploys `gh-pages`, one run at a time. Builds dispatches it from `main`.
  It needs Settings > Pages > Source = "GitHub Actions" and skips until then.

## Before pushing

```
cd godot
godot --headless --import
godot --headless tests/sim_test.tscn   # must end with SIM TEST DONE and no SCRIPT ERROR
```

## Building animations

- Build and sell reveal a building with `Models.cut_material()` (a copy of the lit shader that discards above `cut_y`),
  set as `material_override` only while the animation runs, so finished buildings keep the shared material.
  Sold and destroyed buildings stay in `View3D.recs` until their animation ends (`Ent.end_kind`, `end_t`).
- Check them with `AF_SHOT=<dir> AF_MODE=b xvfb-run godot --path godot`. The test pauses the sim, so it moves
  `S.time` by hand between shots.

## Campaigns

- Missions live in `godot/scripts/campaign.gd` (two campaigns, 8 missions each). Each one draws its own map with
  `MapGen` (rivers, lakes, ridges, mesas, sea, roads, ore) in one of the landscapes in `D.THEMES`, optionally at dusk.
- Goals run in order (`Sim.mission_tick`): destroy_all, kill (types and/or tag), mine, survive, reach, hold, escort,
  rescue, capture. `keep` loses the mission when a hero or the Command Yard is gone. Heroes (`vey`, `furnace`, `harrow`,
  `saint`) and the Convoy Truck are mission-only units (`req: ["never"]`).
- `tests/sim_test.gd` sets up every mission, runs it a minute, then wins it goal by goal by cheating (`solve()`).
  Add a branch there for any new goal kind.
- `AF_MODE=camp AF_SHOT=<dir>` shoots the campaign menu, every briefing, every opening view and a wide map view.
- Progress is saved per campaign in `user://campaigns.json`. Campaign II (the story sequel) stays locked until campaign I is won
  (Guillaume, 2026-11-14); `main.camp_open()`.
- Wave plans spawn the units they name whatever the mission's `aiTech` says (it is often empty). The test jumps to
  each wave of a wave goal and checks enemies really arrive.
- Campaign difficulty (Easy / Normal / Hard on the briefing, saved as `_level` in `user://campaigns.json`):
  `D.LEVELS` shifts the mission's AI tier (`D.DIFF_ORDER`, Easy can reach `recruit`), scales enemy start credits and
  wave sizes (`Sim.scaled`) and delays or advances the first attack. Balance target: Normal must be beatable on a phone
  (Guillaume could not beat Kettleford, 2026-11-14), so early missions keep the enemy off tanks and give the player a
  head start. Check a change with an AI-vs-AI soak (player side driven by `ai_think`) before raising enemy pressure.

## Cutscenes (Guillaume 2026-11-14: "Can you do cutscenes?")

- In-engine, no video: `scripts/cutscenes.gd` holds each scene as data (map borrowed from a mission, cast, shots with
  camera moves, subtitle lines, title cards, actions); `scripts/cutscene.gd` (`CutscenePlayer`, on top of the UI) draws
  the letterbox, subtitles, Skip and fades and drives the camera; `main.start_cutscene` / `play_reel` build the world.
- `Sim.cine` turns off AI, goals and win checks and shows the whole map; `"bare"` skips the mission's units (`gi = 99`, no marks).
  `View3D.cine` is a free orbit camera ({yaw, pitch}); `set_cine_look` swaps the black void for the menus' dusk sky.
- Scene ids: `<camp>_open` plays before the campaign's first mission the first time (seen ids in `_seen` of
  `user://campaigns.json`; the campaign screen has an OPENING button to replay it); `<camp>_<n>` is mission n's intro,
  played on every Begin. First batch: both openings and Embers mission 1. Guillaume wants to judge the style before more.
- Subtitles: short (the test fails over 64 characters), one per shot, large, in the bottom bar. Speakers in `Cutscenes.WHO`.
- Check with `AF_SHOT=dir AF_MODE=cine [AF_CINE=id,id] xvfb-run godot --path godot --fixed-fps 20` (one shot per camera cut).
  `cutscene_tests()` in `tests/sim_test.gd` runs every timeline on the sim.
- New scripts use `preload` constants, not `class_name`: the global class list comes from the installed APK's shell,
  so a class added in a self-update pack would be unknown on phones (cutscene.gd and cutscenes.gd do this).

## Audio and UI on phones

- Sounds come from `godot/tools/synth.py` (`python3 tools/synth.py .` from `godot/`). Keep the current levels:
  Guillaume tried +9 to +20 dB louder (PR #4) and asked for the original levels back (2026-11-13).
  To check that the game makes sound without a sound card, record a run with `--write-movie out.avi --fixed-fps 20`
  and measure the audio track with ffmpeg.
- `main.gd _on_resize` scales the UI on mobile from the screen DPI (`content_scale_factor`, about 180 UI units per
  inch, so about ×1.25 on a 2410×1080 phone; Guillaume found ×1.5 too big). Test a phone layout with `AF_DPI=400 ... --resolution 2410x1080`.

## Keeping this file up to date

When you learn something a future agent would need (a convention, a gotcha, a check to run), add it here
in your PR, keep it short, and mention the change in the PR description.
- Keep buttons and text inside the safe area: `main.gd _apply_safe` feeds `UI.set_insets` from the display safe area
  (camera hole/notch, either landscape side) with at least 24 UI units at the sides and 8 at top/bottom on phones
  for rounded corners. Backgrounds still bleed to the edges. Simulate a cutout with `AF_SAFE=left,top,right,bottom` (pixels).
- Touch controls (Guillaume, 2026-11-14): one finger drags the map (he tried two-finger panning and did not like it),
  taps select/order, hold-then-drag boxes (or faces a formation when units are selected and the hold starts on open
  ground). Pinch zooms past a 12% dead zone. `main.gd PAN_FINGERS = 2` is the two-finger variant. The side panel
  hides with the `»` button in the top bar (`UI.set_panel`, `user://prefs.json`); use `U.panel_px()` for its width.
- Phone HUD extras (2026-11-14): production chips in the top bar while the panel is hidden (`UI.ProdChip`,
  `main._prod_chips`), MAP = enlarged minimap (`UI.big_map`, draws the panel minimap's texture), army groups
  (`main.groups`, `group_btn`), objective auto-hide (`obj_t`, `OBJ_SHOW`), drag-to-build from `BuildItem`
  (`drag_build_*`, `GHOST_LIFT`), hold a unit item = queue five, corner ✕ cancels. `AF_INPUT=1` replays all of them.
- HUD look (2026-11-14, "UI too simple, keep low poly but increase quality"): HUD buttons are `UI.HudBtn` made by `mkbtn(text, cb, w, h, size, glyph)`;
  `restyle`/`set_on` give them cached chamfered olive plates (`hsb`) with brass ticks. Icons are vector glyphs in `UI.glyph`
  (aur, pwr, atk, stop, form, inf, veh, air, map, build, repair, sell, up, launch, obj, lock, ...), no image files.
  Readouts sit on `UI.Plate` (`plate_sb`, optional coloured left bar). Health bars: `main._hp_bar`; order prompts: `main._order_banner`.
  The UI is 600 units tall divided by `content_scale_factor` (capped at 1.5), so a high-DPI phone has only ~400 UI units
  of height: Guillaume's phone hits the cap (2026-11-14, menu was cut off). Check menus and HUD with `AF_DPI=520` as well
  as 400. Group chips are pinned under the OBJECTIVE button; the objective box opens over them.
- Menus (2026-11-14, "too much small text"): few words, nothing under 12-13 UI units except the build line; the start
  screen is title + two doors + field manual, the briefing is two columns with difficulty and Begin on one row.
- 3D look (2026-11-14): `Models.LOOK` is pasted into both lit shaders (hemisphere shading, drifting cloud shadows,
  silhouette rim; off when `fog_on` is 0, as for the build icons). Filmic tone, mild grading and bloom on emissive parts
  are in `View3D._ready`, and turned off on the GL Compatibility fallback, which already renders darker. Water depth and
  shore foam come from a heightmap texture of `S.H` (`height_tex`), not the depth buffer (it read empty here).
