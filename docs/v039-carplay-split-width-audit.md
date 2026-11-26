# V039 CarPlay split-width regression audit (2026-11-26)

## Finding and verification boundary

**Proven:** forcing `isSupportWirelessCarPlay()` false changes a 1920 display with
`fy()==true` to a 1280 video configuration. Permitting it only in `mU()` restores
stock 1920 selection, including `mW()`'s 1920 video enum. This is a necessary
width correction, not proof that the corner arrow now resizes the image each time.
The user's observation of dynamic resizing in early builds is accepted as vehicle evidence.

**Not established:** a complete stock Java path that changes the CarPlay video/view
area on every INFO arrow press. In the supplied V039 code the split listener does
not implement such a path. Do not describe this candidate as a vehicle-verified
restoration of dynamic resizing.

All stock locations below are relative to
`analysis_private/hud-v039/j/HKMC_DiPO/sources/com/daudio/app/dipo/`, unless marked
smali. Stock files were read only; no OEM code or rebuilt OEM artifacts are saved here.

## 1. Width, surface and split callbacks

- `e/a/i.java:272`: `mU()` reads the actual display metrics. Only the conjunction
  wireless=false, `DipoService.fy()`=true and width=1920 substitutes 1280.
- `e/a/i.java:296`: `mW()` calls `mU()` to select the video stream enum.
  `e/b.java:1093-1096` calls both and passes dimensions, physical dimensions and
  stream enum to `CarPlayService.createCarPlay()`.
- `e/a/i.java:326`: `nc()` chooses physical width using `fy()`, independently of
  the wireless capability. `DipoService.java:9577` (`fx()`) compares current and
  full physical width; `fw()` at 9555 checks the created video width instead.
  These are different decisions.
- **smali** `ui/DipoActivity.smali:3501-3548`: on a 1920 display, `!fx()` selects
  PP fullscreen=false and `removeBtnOffScreen`. This path sets SurfaceView width
  to 1280 at 3709-3718. The `fx()` path at 3845-3891 selects fullscreen=true,
  `addBtnOffScreen`, hides the right pane and sets width 1920. There is no direct
  wireless-capability check in these layout branches. In KR the non-ME branch
  at 3776 initially makes the right pane visible, independently of `fw()`.
- `ui/g.java:47-115`: split HIDE/SHOW broadcasts queue handler messages 3/2
  (subject to connected state and `fG()`). `ui/b.java:46-58`: message 2 hides
  the right pane; message 3 shows it only when `!fw()`. Neither message changes
  SurfaceView LayoutParams. A 1920 stream prevents the 1280 fallback pane from
  being re-shown by message 3, but does not itself prove a layout transition.
- **smali** `service/l.smali:27-38`: `onChangeButton` and `onChangeOnOff` return
  immediately. `onChangePage` at 40 checks split support, page/view and call/OSD
  state, then updates OSD through `k/d`; it contains no layout or native size call.
  `automotive/.../SplitScreenManager.java:705,730,752` dispatches page/on-off/button
  callbacks (with cached state and handler dispatch); dispatch is not a resize.
- `ui/e.java:16`: surfaceChanged forwards the holder, ignoring callback width and
  height; `ui/DipoActivity.java:334` -> `DipoService.a(holder, mode)` -> display
  handling -> `e/b.java:525` -> `CarPlayService.showDisplay(Surface)` at 4151 ->
  `TccCarPlayNativeMethod_ShowDisplay`. Native Create is declared at 1645 and
  called at 2241. There is no exposed view-area/screen-size update native method
  in this CarPlayService. Native library internals and the split window service
  have not been disassembled/proven here. String scans of the available
  libCarPlay/libCarPlayAndroid/libCarPlayCore libraries found no matching resize,
  view-area, screen-size or split strings; that negative scan is not behavioral proof.

If the width candidate still fails on the car, the next investigation is the early
working delta/native runtime versus current surface bounds and split window policy.
A possible alternative is a guarded HIDE/SHOW surface/view-area adapter, but it
requires evidence of the native supported area-update contract and touch-coordinate
mapping first. Do not invent a native resize call or force physical `fx()`/`fy()`:
that can also disable the arrow or corrupt aspect ratio/touch input.

## 2. Every direct capability call site

| Stock location | Effect of true | Decision |
| --- | --- | --- |
| `e/a.java:56` | skips post-connect `b.t()` | Unsafe transport change; false |
| `e/a.java:72` | skips disconnect `G().aF()` | Unsafe cleanup change; false |
| `e/b.java:941` | exits onTransportIdentifier before USB identity/device updates | Unsafe identity change; false |
| `e/e.java:145` | skips IdentificationAccepted `G().aG()` | Unsafe authentication/start change; false |
| `e/a/i.java:280` | keeps actual 1920 width instead of 1280 substitution | Allow only inside `mU()` |
| `i/e.java:204` (`D(Context)`) | reads OEM USB-enable preferences | Unrelated transport policy; false |
| `i/e.java:243` (`E(Context)`) | reads OEM wireless-enable preferences | Unrelated transport policy; false |
| `i/e.java:998` (`iY()`) | returns capability | No caller found in supplied DiPO; keep false |
| `i/e.java:1755` (`F(Context)`) | permits stock split preference query | Existing narrow scope retained |
| `i/e.java:2498` (`jx()`) | no effective result change | Smali proves both branches return false; leave alone |
| `DipoService.java:4643,6417` | only changes diagnostic string | Harmless alone; no broad service scope |
| `DipoService.java:5097` (`ft()`) | bypasses KR default RHD initialization and directly uses stored G | Unrelated/possibly unset preference; false |
| `DipoService.java:8979` | suppresses delayed first-consent message 47 | Unsafe consent/UI change; false |
| `DipoService.java:9993` | skips `ft()` during service initialization | Unsafe RHD initialization change; false |
| `DipoService.java:10092` | omits connectedsuccess receiver action | Unsafe connection routing change; false |

`e/g` separately gates startup on component 1. Existing relay component mapping,
notification suppression and Bluetooth/audio behavior are retained. A scope around
createCarPlay, onResume, onCreate or a whole service callback would be too broad.

## 3. History and actual integrated delta

There are no v0.3.5x tags in this checkout. `08c46e4` is the v0.3.50 commit
(2026-11-07). Its permission XML declares carplay_wireless; its builder adds relay
session/data/binder callbacks and the call-key fallback, without overriding the
feature predicate or width method. `tools/stage-v039-relay.sh` stages the checked-in
LPD; `packages/wireless-bridge/scripts/common.sh` applies it to original ODEX and
adds the resulting dex to the original APK on the unit.

To check the actual payload rather than infer it from builder source, the Git LPDs
were decoded **in memory**, using `mkdelta.py`'s apply reference and original V039
ODEX. Both source and target MD5 headers matched for each revision; no APK/ZIP was
created. The resulting DEX method tables/instructions showed:

| Git revision | Reconstructed DEX SHA-256 | Capability method |
| --- | --- | --- |
| `08c46e4` | `e171ce32b7075ccb8d95c6e5f287ae96fcdca012cb5b1584e1501c52c4937931` | 19 code units; calls Feature.hasFeature and Boolean.booleanValue (stock feature OR nP override) |
| `9fd127c` (2026-11-12) | `e5c7248d4843c3963209581b3ceea0cbcc928a5105dc7b69e4b9d7bdbe2b2a1f` | 2 code units; constant false |
| `HEAD` legacy integrated delta | `e2f63715b83449fcb5d8271b2dd713704fa89c9be1d00ff2cff44edd9d9e1a47` | 2 code units; constant false |

All three retain the 63-code-unit `mU()` and its wireless/fy decision calls.
Thus the early delta really retained the stock predicate; with its installed
feature XML loaded, it would return true. This does not identify which exact early
version was on the car during the user's observation. `9fd127c` explicitly added
false alongside the component-1 workaround. Portable `336f996` (2026-11-13) likewise
returned false globally. The pre-task working tree already scoped `F(Context)`.

This change targets portable 0.3.95. The legacy integrated builder/delta remains
unchanged and still has the width limitation; no legacy rebuild is claimed.

## 4. Candidate and tests

`DipoAdapters` discovers the unique mU/mV/mW display role without class initialization,
then wraps only `mU()` in the same thread-local capability scope as `F(Context)`.
It calls the original once and restores the prior scope in finally. Missing or
ambiguous display roles abort discovery before installing hooks. Split defaults,
settings, audio, lifecycle and excluded files are not changed by this patch.
The UI now says only that changing the setting reconnects CarPlay, in Korean and English.

Host verification: portable adapters (8 cases, including missing/ambiguous display,
1920/1280/800, split on/off, nested scopes, exception identity/restoration and thread
isolation), dipo_relay_runtime, dipo_relay_builder (6), unit_commands (130 scripts),
and all 41 JVM test mains listed in tests/java.sh passed.
The actual-stock Dalvik discovery expectation increases from 21 to 22 hooks;
that VM test was updated but not run (no VM/package build in this task). Java compilation targets
release 8 using JDK 25. These are host/fixture checks; no package build or car run.

## 5. Existing stock logs for the next vehicle check

DiPO logger uses tag **`CarPlay_`**, formatting `[ <class> ] <message>`; it does not
use `CarPlay_<class>` tags. `CarPlayService` uses its own logger tag.

| Tag / class | Exact message text or prefix | What it establishes |
| --- | --- | --- |
| `CarPlay_` / `b` | `createCarPlay() mSetScreenWidth = 1920` | 1920 configuration selected |
| `CarPlay_` / `b` | `createCarPlay() ret = ` | Check for OK; width alone does not prove creation succeeded |
| `CarPlay_` / `e` | `getUseSplitScreen result = true` | OEM split preference query permitted and enabled |
| `CarPlay_` / `DipoService` | `isCPResolutionFullScreenMode() width : 1920` | Created-width state, when queried |
| `CarPlay_` / `DipoService` | `onChangePage page : ` / `onChangePage view : ` | Page/view callbacks arrived; not proof of resized video |
| `CarPlay_` / `DipoActivity` | `reached split off` / `reached split on` | HIDE/SHOW broadcasts arrived |
| `CarPlay_` / `DipoActivity` | `onResume SSEnable` / `onResume SSDisabled` | Physical-width layout branch (not stream width) |
| `CarPlay_` / `DipoActivity` | `onResume setPPFullscreenMode false ` / `onResume setPPFullscreenMode true ` | PP fullscreen policy chosen (trailing spaces are stock) |
| `CarPlay_` / `DipoActivity` | `surfaceChanged : 07201` | Surface callback only; stock does not log dimensions |
| `CarPlayService` | `showDisplay() : ` | Surface submitted; does not show view-area dimensions |

No existing line listed here alone proves dynamic arrow resizing. After reconnect,
collect creation + split + surface events together, then verify wider/narrower
content and touch alignment across repeated open/close cycles on the actual car.
The unchanged `drivelog.sh` is outside this fix; no new collection/USB claim is made.
