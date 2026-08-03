# Building for Android

## Prerequisites (one-time)

1. **Godot 4.3+ standard editor** — https://godotengine.org/download
2. **Android export templates**: in Godot, `Editor → Manage Export Templates → Download and Install`.
3. **Android SDK + JDK 17**:
   - Easiest: install [Android Studio](https://developer.android.com/studio), then in its SDK
     Manager install *SDK Platform 34*, *Build-Tools*, *Platform-Tools*, *Command-line Tools*.
   - In Godot: `Editor → Editor Settings → Export → Android`, set:
     - `Java SDK Path` → your JDK 17 folder
     - `Android SDK Path` → e.g. `C:\Users\<you>\AppData\Local\Android\Sdk`
4. **Debug keystore** (Godot usually auto-detects `~/.android/debug.keystore`; if missing):
   ```
   keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
     -keystore debug.keystore -storepass android -dname "CN=Android Debug" -validity 9999
   ```
   Point `Debug Keystore` at it in the same Editor Settings page (user/pass `androiddebugkey`/`android`).

## Export

The repo ships a ready **Android** preset (`export_presets.cfg`):

- Package: `com.dhairyarawal.minedriller`, version 1.0.0 (code 1)
- arm64-v8a only (add armeabi-v7a in the preset if you need 32-bit devices)
- Portrait, immersive mode, `VIBRATE` permission for haptics, user-data backup allowed

Steps:

1. Open the project, `Project → Export…`, select **Android**.
2. Press **Export Project** → `build/MineDriller.apk` (debug), or tick *Release* after
   configuring a release keystore.
3. Install: `adb install build/MineDriller.apk`.

Command-line equivalent:

```
godot --headless --path . --export-debug "Android" build/MineDriller.apk
```

## Play Store notes

- Switch `gradle_build/export_format` to **AAB** in the preset for Play submission.
- Create a release keystore and fill the `keystore/release*` fields (never commit it).
- The generated `icon.png` (512×512) doubles as the store icon source; adaptive icons can
  be added in the preset's `launcher_icons/*` fields.
- Expected APK size: **well under 10 MB** (all assets are generated primitives) — far inside
  the 150 MB target.

## Device sanity checklist

- [ ] 60 fps on a mid-range device (Pixel 6a class) — profiler shows terrain at ~5 draw calls
- [ ] Backgrounding the app pauses the game and forces a save
- [ ] Android Back button opens/closes the pause menu
- [ ] Haptics fire on drill start / ore pickup / damage (and respect the settings toggle)
- [ ] Notch/safe-area: HUD uses inset anchors at the top; verify on a cutout device
