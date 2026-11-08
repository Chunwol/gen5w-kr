# Gen5W stock UI skin and verification

The application reads **drawable resources only** from the installed
`com.android.generalsettings` package, falling back to `com.android.settings`.
It does not load OEM classes, change either APK/ODEX, or bundle manufacturer
images/fonts. Missing resources use our own drawable/Canvas fallback.

The former corporate nine-color whitelist is intentionally superseded by the
user-approved stock-screen palette. `StockSkin` uses V039 title/summary colors,
including `#888888` summaries and `#505050` disabled controls. Text uses the
device's default font, so the car retains its installed system font; emulator
font rendering must not be presented as a verified car font match.

## Reference and acceptance checks

Private reference: GeneralSettings.apk extracted read-only from Korean Kona
V039 system.ext4, SHA256
`df08d524969a1636af4ad6016ea3f7578a92897f1aadf1ea39074fe64fb27771`.

- `SlideSwitch`: rectangular ON/OFF track plus half-width rectangular handle.
  Its four static states are compared against an independently composed native
  reference using literal 120x44 track / 60x44 handle bounds. The criterion is
  **zero differing pixels**, not a subjective similarity percentage.
- Menu slot: 197dp; title strip: 60dp; menu row: 72dp; content list reference:
  603dp; title/summary: 26sp/22sp. These come from GeneralSettings layout/resource
  entries. Wide layouts expose a separate right-hand explanation pane; narrower
  screens retain explanations within the rows.
- SystemUI keeps ownership of the clock/status area. The app does not render a
  second simulated clock or date bar. Only the app viewport is captured.
- Render Info, On/Off, Log, Manage, removal confirmation and English mode.
- Exercise real switch-request writing (including the new requested state),
  disabled/unknown gates, removal cancellation and language switching.
- Check a wide 1920x720 / density240 profile and a compact 800x480 / density160
  profile, plus the missing-OEM-resource fallback. These are test profiles,
  **not proof of the particular car's physical display mode**.

The wallpaper gradient is an approximation from the user's photographed screen,
not a verified OEM wallpaper bitmap. Whole-screen pixel identity cannot be
claimed from a photographed reference, different text, or emulator font output.
The exact-pixel result applies to the specified native control states only.

## Reproduce on an isolated emulator

Use an explicitly named, separately owned emulator. Do not change a vehicle or
another project's running emulator display configuration. `tests/ui_preview.py`
rejects serials that do not start with `emulator-`.

```powershell
# Configure only the dedicated UI test instance, not a shared emulator.
adb -s emulator-5556 shell wm size 1920x720
adb -s emulator-5556 shell wm density 240
python tests/ui_preview.py --serial emulator-5556 --stock-dir D:/private/v039
python tests/ui_preview.py --serial emulator-5556 --scenario locked
python tests/ui_preview.py --serial emulator-5556 --scenario unknown

# Historical UI: capture only, explicitly not an assertion pass.
python tests/ui_preview.py --serial emulator-5556 --revision 7d4f533 --capture-only
```

The optional `--stock-dir` must contain the user's own `GeneralSettings.apk`.
The script creates a **private, resources-only** reference APK in `.build`,
installs it separately on that emulator, and never adds its contents to our app.
Do not distribute that APK or screenshots containing OEM artwork without the
necessary rights. To test the fallback, uninstall that reference package only
from the dedicated disposable emulator and rerun without `--stock-dir`.

The UI harness compiles the production UI sources with only the collector path
redirected to a private fixture folder. The OEM/HUD service is replaced by an
inert test service. These test-only changes are not part of the shipped APK.
All generated APKs and screenshots remain under `.build/ui-preview-*`.

Run `bash tests/run.sh` and `bash app/build.sh` for the ordinary regression suite
and Android-18-compatible production build. No release or USB update is implied
by these UI-only development checks.
