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
Hotspot reference: HKMC_WifiSettings.apk SHA256
`48edb9bf294fd3ff8346c37beac7ae9252b41b1cbd0320a67ee96b21b9dc4dd6`;
V039 framework-res.apk SHA256
`2268d339cdd2ecf7ae7d5e8801b3afc125fae141a5bf68ea5b86169bfd9b9ee1`.
The latter's `Theme` maps `checkboxStyle` to `Widget.CompoundButton.CheckBox`,
whose button uses `listChoiceIndicatorMultiple` -> `btn_check.xml` ->
`co_btn_check_on_nor`, `co_btn_check_off_nor` and their state variants.
Its Hyundai-hdpi checked artwork is a blue square with a white check, not
the AOSP emulator's green tick. These private files are reference data only.

- On/off rows follow **HKMC WifiHotspot**, not GeneralSettings `SlideSwitch`.
  `res/xml/wifi_hotspot.xml` maps `hotspot_toggle` to
  `HotspotCheckBoxPreferenceDAudio`; its layout
  `checkbox_custom_preference_hotspot.xml` contains a left-hand Android
  `CheckBox`, followed by the label (22dp outer inset, 8dp label gap).
  The package's `noAnimTheme` inherits `android:style/Theme.NoTitleBar` without
  overriding `checkboxStyle`. Our actual `CheckBox` uses that same base theme,
  so the installed vehicle framework supplies its checked, unchecked, pressed
  and disabled artwork. The row owns clicks and exposes checkable/checked
  accessibility semantics. It cannot be toggled separately around request gates.
  Emulator tests compare to a normal system CheckBox under that theme, **not
  to an independently captured vehicle screen**. AOSP emulator artwork is not
  proof of the exact vehicle appearance.
  The earlier red ON/OFF resource composition was a wrong choice of control;
  its zero-pixel-difference result never established a match to WifiHotspot.
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
The system-checkbox comparison only establishes use of the same local theme;
the actual vehicle appearance still requires a vehicle check.

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
