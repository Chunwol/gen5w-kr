# 차 안 화면 1단계(읽기 전용 INFO·LOG) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 헤드유닛 화면에서 무선 상태와 이유(INFO), 한국어로 번역한 최근 기록(LOG)을 읽기 전용으로 보여 준다.

**Architecture:** 이미 root로 도는 무선 감시 프로그램(`service.sh`)이 상태 스냅샷과 최근 기록 몇 줄을 코어 앱의 데이터 폴더에 써 둔다. 코어 앱에 추가하는 화면(Activity)은 그 파일만 읽고 번역해 보여 준다. 화면은 아무것도 쓰거나 바꾸지 않고, 화면이 죽어도 무선·HUD는 영향이 없다.

**Tech Stack:** Java 8 소스(minSdk 18, 리소스 파일 없이 코드로 화면 구성), POSIX/mksh, 기존 `tests/bridge.sh`·`tests/java.sh`, `app/build.sh`.

**Spec:** `docs/superpowers/specs/2026-11-06-in-car-ui-design.md` (이 계획은 spec의 1단계만 다룬다. 2단계 ONOFF 스위치, 3단계 나머지 스위치, 4단계 관리는 이 단계를 차에서 확인한 뒤 각각 별도 계획으로 쓴다.)

## Global Constraints

- 대상: Kona HEV 한국 V039, Android 4.4.2, minSdk 18, mksh. 리소스(XML·이미지) 없이 코드로 화면을 만든다(`app/build.sh`는 매니페스트만 링크한다).
- 로그·진단 파일의 원문은 영어 코드 그대로 둔다(`FAIL bridge:`, `WAIT bridge:`). 번역은 화면에서만 한다.
- 화면은 읽기 전용이다. 시스템 파일·마커·설정을 쓰지 않는다.
- 감시 프로그램의 기존 stdout 출력과 동작을 바꾸지 않는다. 상태 기록 실패는 무시한다(`|| :`).
- root가 앱 폴더에 쓸 때 심볼릭 링크는 따라가지 않는다.
- 기록 파일 최대 60줄, 한 줄 최대 200자.
- 순정 Gen5W 설정 스타일(어두운 배경 `#0b0e12`, 강조색 `#00aad2`, 왼쪽 메뉴 INFO/ONOFF/LOG/관리). 1단계에서 ONOFF·관리 메뉴는 "다음 버전에서 제공" 안내만 보인다.
- 전체 테스트 `bash tests/run.sh`와 unit-commands 정책(`tests/unit_commands.py`)을 통과해야 한다.

## Review Focus

- 스냅샷 파일이 없거나 읽을 수 없을 때(앱이 막 설치됨, 폴더 권한): 화면이 죽지 않고 "상태를 읽을 수 없음"을 보인다.
- 스냅샷이 오래됐을 때(감시 프로그램이 멈춤): 60초 넘으면 "기록이 오래됨"을 표시한다. 값을 현재 상태처럼 보이면 안 된다.
- 번역 표에 없는 로그 줄: 버리지 않고 원문을 그대로 보인다.
- 아주 긴 줄·깨진 UTF-8·60줄 넘는 기록: 잘라서 보이고 화면이 죽지 않는다.
- 앱 폴더에 심볼릭 링크가 있을 때: 감시 프로그램이 따라가지 않고 기록을 건너뛴다.

---

### Task 1: 로그 한국어 번역 (`LogTranslator`)

**Files:**
- Create: `app/src/kr/gen5w/ui/LogTranslator.java`
- Create: `app/test/LogTranslatorTest.java`
- Modify: `tests/java.sh` (컴파일 목록에 두 파일 추가, `java -cp "$work" LogTranslatorTest` 실행 줄 추가)

**Interfaces:**
- Produces: `public final class LogTranslator` with
  - `static String translate(String raw)`: 번역 표에 맞으면 한국어 문장, 아니면 `raw` 그대로(길이 200자로 자름, `null`이면 `""`).
  - `static String category(String raw)`: `"error"`(`FAIL `로 시작하거나 `relay start failure` 포함) / `"wireless"`(`bridge`·`WAIT bridge`·`STEP bridge` 포함) / `"install"`(`INSTALLED`·`READY`·`RESTORED`·`SKIP`·`FAILED` 시작) / `"other"`.

- [ ] **Step 1: 실패하는 테스트 작성** `LogTranslatorTest` (기존 `StockFlagTest`와 같은 형식, 마지막에 실패 수가 0이 아니면 `System.exit(1)`). 단정:
  - `translate("WAIT bridge: installer reboot is pending (noreboot marker present)")` → `"설치 후 재부팅을 기다리는 중입니다"`
  - `translate("WAIT bridge: wireless is not in match mode (ap-match is not 'match')")` → `"핫스팟 설정이 아직 일치하지 않아 기다리는 중입니다"`
  - `translate("WAIT bridge: wired-only mode is set")` → `"유선 전용 모드라 무선을 쓰지 않습니다"`
  - `translate("WAIT bridge: restart guard is off (too many unfinished starts); wireless stays off")` → `"재시작 보호가 걸려 무선이 꺼져 있습니다"`
  - `translate("WAIT bridge: dongle edition: no wlan0 yet")` → `"USB 동글 Wi-Fi가 아직 인식되지 않았습니다"`
  - `translate("FAIL bridge: host repeatedly failed to start; wireless suspended until restart")` → `"무선 호스트가 반복해서 시작에 실패해 무선을 멈췄습니다"`
  - `translate("relay start failure: java.lang.NoClassDefFoundError: x")` → `"릴레이를 켜지 못했습니다 (NoClassDefFoundError)"`
  - `translate("STEP bridge: host alive")`은 `"무선 호스트가 실행 중입니다"`
  - 번역 표에 없는 줄 `"something new"` → `"something new"` 그대로.
  - `translate(null)` → `""`. 300자 줄 → 정확히 200자.
  - `category` 4가지 각각 한 줄씩.
- [ ] **Step 2: 실행해 실패 확인** — `bash tests/java.sh` → `LogTranslatorTest` 컴파일 실패(클래스 없음).
- [ ] **Step 3: `LogTranslator` 구현.** 접두어·부분 문자열 목록을 `String[][]` 표로 두고 위 순서로 첫 일치를 반환한다. 번역 문구는 위 단정이 정한 값을 그대로 쓴다. 표에 없는 줄은 원문.
- [ ] **Step 4: 통과 확인** — `bash tests/java.sh` → `== LogTranslator: all passed`.
- [ ] **Step 5: 커밋** — `git add app/src/kr/gen5w/ui/LogTranslator.java app/test/LogTranslatorTest.java tests/java.sh && git commit -m "ui: translate bridge log lines to Korean for display"`

---

### Task 2: 상태 모델 (`StatusModel`)

**Files:**
- Create: `app/src/kr/gen5w/ui/StatusModel.java`
- Create: `app/test/StatusModelTest.java`
- Modify: `tests/java.sh`

**Interfaces:**
- Consumes: `LogTranslator.translate`(이유 문장을 같은 표에서 얻을 필요는 없음. 이유는 `reason` 코드에서 자체 표로 만든다).
- Produces: `public final class StatusModel`
  - `static StatusModel parse(java.util.List<String> lines, long nowSeconds)`: `key=value` 줄을 읽는다. `lines==null`이면 `unreadable()`과 같다.
  - `static StatusModel unreadable()`
  - `boolean readable()`, `boolean stale()`(`nowSeconds - ts > 60` 또는 `ts` 없음)
  - `String host()` (`alive`/`dead`/`unknown`), `String relay()` (`on`/`off`/`unknown`), `String backend()`, `String bridgeVersion()`, `boolean apguardOff()`
  - `String why()`: 한 줄 한국어 이유. `reason` 코드 → 문장. 코드 `running`이면 `""`. 알 수 없는 코드나 없는 코드는 `"원인을 확인하지 못했습니다"`.
  - 스냅샷 키: `ts`(epoch 초), `host`, `relay`, `reason`, `backend`, `version`, `apguard`(`on`/`off`). `reason` 코드: `running` `starting` `noreboot` `ap-mismatch` `wired-only` `apguard-off` `no-wlan0` `blocked`.

- [ ] **Step 1: 실패하는 테스트.** 단정:
  - 정상 입력 `["ts=1000","host=alive","relay=on","reason=running","backend=builtin","version=0.3.46","apguard=on"]`, now=1010 → `readable()` true, `stale()` false, `host()`=`"alive"`, `why()`=`""`.
  - `reason=ap-mismatch` → `why()`가 `"핫스팟 설정이 아직 일치하지 않아 기다리는 중입니다"`.
  - `reason=noreboot` → `"설치 후 재부팅을 기다리는 중입니다"`, `wired-only` → `"유선 전용 모드라 무선을 쓰지 않습니다"`, `apguard-off` → `"재시작 보호가 걸려 무선이 꺼져 있습니다"`, `no-wlan0` → `"USB 동글 Wi-Fi가 아직 인식되지 않았습니다"`, `blocked` → `"무선 호스트가 반복해서 시작에 실패해 무선을 멈췄습니다"`, `starting` → `"무선 호스트를 시작하는 중입니다"`.
  - now=1100(ts=1000) → `stale()` true. `ts` 없음 → `stale()` true.
  - `parse(null, 0)` → `readable()` false. 줄에 `=`가 없거나 키만 있으면 그 줄은 무시(예외 없음). 값이 없는 키 `host=` → `host()`=`"unknown"`.
  - 알 수 없는 `reason=xyz` → `"원인을 확인하지 못했습니다"`.
- [ ] **Step 2: 실행해 실패 확인** — `bash tests/java.sh` → 컴파일 실패.
- [ ] **Step 3: 구현.** 위 서명대로. `ts`는 `Long.parseLong`, 실패하면 없는 것으로 본다.
- [ ] **Step 4: 통과 확인** — `bash tests/java.sh` → `== StatusModel: all passed`.
- [ ] **Step 5: 커밋** — `git commit -m "ui: status model with Korean reasons and staleness"`

---

### Task 3: 감시 프로그램이 상태·기록을 앱 폴더에 쓴다

**Files:**
- Modify: `packages/wireless-bridge/scripts/service.sh` (`note()` 근처와 메인 루프)
- Modify: `tests/bridge.sh`

**Interfaces:**
- Produces (파일): `$UI_DIR/status`(위 스냅샷 키), `$UI_DIR/log`(원문 최근 60줄). `UI_DIR=${BRIDGE_TEST_UIDIR:-/data/data/kr.gen5w.core/gen5w-ui}`. 폴더 모드 755, 파일 모드 644.
- 함수: `say()`(`echo "$1"` 후 `ui_log "$1"`), `ui_log()`, `ui_status()`.

- [ ] **Step 1: 실패하는 테스트** (`tests/bridge.sh`, 기존 `WAIT bridge` 점검 근처 형식). 단정:
  - 기본 실행(한 번 돌고 종료, `BRIDGE_TEST_ONCE`)에서 `BRIDGE_TEST_UIDIR` 아래 `status`에 `host=`·`reason=`·`version=`·`ts=` 줄이 생기고, 모드가 644, 폴더가 755.
  - `gen5wkr.noreboot`가 있으면 `reason=noreboot`, `ap-match`가 `match`가 아니면 `reason=ap-mismatch`, wired-only 마커면 `reason=wired-only`, `gen5wkr.apguard.off`면 `reason=apguard-off`, 동글+wlan0 없음이면 `reason=no-wlan0`.
  - `log`에는 stdout에 나온 `WAIT bridge:` 줄이 그대로 들어간다. 70줄을 밀어 넣어도 `log`는 60줄, 300자 줄은 200자로 잘린다.
  - `UI_DIR`이 심볼릭 링크이거나 `status`가 심볼릭 링크면 링크 대상 파일이 바뀌지 않는다(대상 내용 보존 확인). 폴더가 없고 부모도 없으면 감시 프로그램은 정상 종료하고 stdout은 그대로다.
  - 기존 테스트의 stdout 단정(`WAIT bridge`/`FAIL bridge` 문구)은 한 글자도 바뀌지 않는다.
- [ ] **Step 2: 실행해 실패 확인** — `bash tests/run.sh`(또는 `bash tests/bridge.sh` via WSL mksh) → 새 단정 실패.
- [ ] **Step 3: 구현.**
  - `ui_prepare()`: `UI_DIR`의 부모(앱 데이터 폴더)가 디렉터리가 아니면 반환 1. `UI_DIR` 또는 `status`·`log`가 링크면 반환 1. 없으면 `mkdir`(`chmod 755`). 모든 쓰기는 임시 파일에 쓰고 `mv`(링크 확인 뒤).
  - `ui_log()`: 줄을 200자로 잘라 `log`에 붙이고 60줄만 남긴다(이전 내용을 읽어 마지막 59줄 + 새 줄).
  - `ui_status CODE`: 현재 값으로 스냅샷을 쓴다. `host`는 `host_alive`, `relay`는 `relay_status`(0=on, 77=off), `apguard`는 `$APG_OFF` 유무, `backend`는 `getprop persist.gen5w.wifi.backend`(비면 `builtin`), `version`은 패키지의 `NEMESIS.data`의 `package-version`, `ts`는 `date +%s`.
  - 기존 `echo 'FAIL bridge:…'`/`note()`의 `echo "WAIT bridge: …"`를 `say`로 바꿔 stdout은 그대로 두고 기록을 남긴다. `note()`가 이유 코드를 인자로 받아(`note CODE TEXT`) 변경 때 `ui_status CODE`를 호출한다. 메인 루프에서 호스트를 시작할 때 `starting`, 호스트가 살아 있으면 `running`, `blocked` 직전에 `blocked`. 모든 호출은 `|| :`.
  - 쓰는 명령은 `unit_commands.py`가 허용하는 것만 쓴다(`mkdir`·`chmod`·`mv`·`cat`·`date`·`printf`).
- [ ] **Step 4: 통과 확인** — `bash tests/run.sh` → 전체 통과(1분 20초 안팎).
- [ ] **Step 5: 커밋** — `git commit -m "bridge: write status snapshot and recent log for the in-car screen"`

---

### Task 4: 화면 (`MainActivity`)

**Files:**
- Create: `app/src/kr/gen5w/ui/MainActivity.java`
- Modify: `app/AndroidManifest.xml` (Activity 선언, 런처 인텐트)
- Modify: `app/build.sh` (필요하면 소스 목록은 `find src`라 변경 없음. 확인만)

**Interfaces:**
- Consumes: `StatusModel.parse(List<String>, long)`, `StatusModel.unreadable()`, `LogTranslator.translate`, `LogTranslator.category`.
- Produces: `public final class MainActivity extends android.app.Activity`.

- [ ] **Step 1: 매니페스트.** `<activity android:name="kr.gen5w.ui.MainActivity" android:exported="true" android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen" android:label="Gen5W KR">` + 인텐트 필터 `MAIN`/`LAUNCHER`. 기존 서비스·리시버·`uses-library`는 그대로. `versionCode`는 3으로 올리고 `app/build.sh`의 `--version-code 3`도 같이 맞춘다.
- [ ] **Step 2: 구현.** 코드로만 화면을 구성한다(왼쪽 메뉴 4개 + 오른쪽 내용).
  - `onResume`에서 `new File(getApplicationInfo().dataDir, "gen5w-ui/status")`와 `log`를 읽는다(백그라운드 스레드, 5초마다 갱신, `onPause`에서 멈춤). 읽기 실패·없음은 `StatusModel.unreadable()`.
  - INFO: `why()`가 비어 있지 않으면 노란 설명 상자. 목록은 무선 호스트(실행 중/꺼짐/확인 못 함), 릴레이(켜짐/꺼짐/확인 못 함), 설치 버전, 내장 Wi-Fi 방식, 재시작 보호(정상/걸림). `stale()`이면 맨 위에 "기록이 오래됨(마지막 갱신 N초 전)", `!readable()`이면 "상태를 읽을 수 없음" 한 줄과 안내만 보인다.
  - LOG: 필터 칩 전체/오류/무선/설치(`LogTranslator.category`), 각 줄은 `translate`한 문장과 원문을 작게. 새로고침 버튼은 즉시 다시 읽기.
  - ONOFF·관리: "다음 버전에서 제공됩니다" 한 줄. 어떤 파일도 쓰지 않는다.
  - 색과 크기는 위 Global Constraints. 글자는 `sp` 기준 15~17, 터치 영역 최소 48dp.
- [ ] **Step 3: 빌드 확인** — `bash app/build.sh` → `built app/build/gen5w-core.apk`, dex에 `Lkr/gen5w/ui/MainActivity;` 포함, 앱 외 클래스 없음.
- [ ] **Step 4: 전체 테스트** — `bash tests/run.sh` 통과(`core.sh`가 매니페스트·APK를 검사하면 새 Activity에 맞춰 단정을 갱신).
- [ ] **Step 5: 커밋** — `git commit -m "ui: read-only INFO and LOG screen in the core app"`

---

### Task 5: 버전·문서·산출물

**Files:**
- Modify: `packages/*/NEMESIS.data` 9곳 `package-version=0.3.46`, `CHANGELOG.md`, `docs/vehicle-use.md`(사용 안내 한 단락)
- Create: `docs/in-car-ui.md` (차 확인 체크리스트)

- [ ] **Step 1:** `NEMESIS.data` 버전을 0.3.46으로 올리고(기존 방식대로 전부 같은 값), `CHANGELOG.md`에 v0.3.46 항목을 쓴다(읽기 전용 화면, 상태 스냅샷, 로그는 영어 원문 유지·화면만 한국어).
- [ ] **Step 2:** `docs/in-car-ui.md`에 차 확인 순서를 쓴다: 설치 → 앱이 런처에 보이는지 → 안 보이면 NEMESIS Manager의 My Packages에서 Launch → INFO가 읽히는지(`상태를 읽을 수 없음`이면 앱 폴더 권한 문제로 보고 진단 저장) → LOG 한국어 확인. 확인되지 않은 것(런처 노출, 앱 폴더 읽기)은 "차에서 확인 전"이라고 명시한다.
- [ ] **Step 3:** `bash tools/build-all.sh && python tools/audit-artifacts.py dist`가 통과하고, `bash tests/run.sh`가 통과한다.
- [ ] **Step 4: 커밋** — `git commit -m "v0.3.46: read-only in-car status and log screen"`. 이 단계는 USB 키트로 만들어 차에 설치하기 전에 사용자 확인을 받는다.

---

## Self-Review

- **Spec 범위**: 1단계(INFO·LOG 읽기 전용, 한국어 번역은 화면만, 진입 방법 미확정 명시, 1024x600 가정)를 Task 1~5가 덮는다. ONOFF·관리·ADB·OTA·진단 저장 버튼은 spec의 후속 단계라 이 계획에서 제외했다. 진단 저장 버튼은 쓰기 동작이라 2단계에서 한다.
- **타입 일관성**: `StatusModel.parse(List<String>, long)`·`unreadable()`·`why()`·`stale()`, `LogTranslator.translate/category`가 Task 1·2·4에서 같은 이름이다. 스냅샷 키와 `reason` 코드는 Task 2와 Task 3에서 같다.
- **미확정**: 앱 폴더(`/data/data/kr.gen5w.core`)를 root가 쓰고 앱이 읽을 수 있는지, 런처에 아이콘이 뜨는지는 PC에서 확인할 수 없다. Task 5의 체크리스트로 차에서 확인한다. 읽을 수 없으면 `상태를 읽을 수 없음`이 뜨고 무선·HUD에는 영향이 없다.
