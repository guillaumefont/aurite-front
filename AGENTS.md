# Notes for agents

## Pull requests

- Work on a branch and open a PR against `main`.
- **You may merge your PR yourself once CI is green** (Builds and Headless sim pass on the PR's
  latest commit, and it has no merge conflict). Guillaume, 2026-11-13. Never merge on red or pending CI,
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
- The game is called "Aurite Front". The player faction is blue `#3fb4e8`, the AI is red `#e0423a`.

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

## Keeping this file up to date

When you learn something a future agent would need (a convention, a gotcha, a check to run), add it here
in your PR, keep it short, and mention the change in the PR description.
