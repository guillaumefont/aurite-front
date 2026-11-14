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
