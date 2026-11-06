# 차 안 화면 1단계(읽기 전용 INFO·LOG) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 헤드유닛 화면에서 무선 상태와 이유(INFO), 한국어로 번역한 최근 기록(LOG)을 읽기 전용으로 보여 준다.

**Architecture:** 코어 패키지에 새 root 서비스(`uilog.sh`)를 하나 더 둔다. 이 서비스는 무선 감시 프로그램과 별개로 **모든 gen5w 패키지의 서비스 로그**(`/data/nemesis/logs/gen5w.kr.*/*.log`)와 우리 관련 logcat을 용량 상한 안에서 모아, 상태 스냅샷과 함께 **root 소유 폴더 `/data/nemesis/gen5wkr.ui`** 에 써 둔다(앱이 소유한 폴더에는 root가 쓰지 않는다: 보안 검토 반영). 코어 앱에 추가하는 화면(Activity)은 그 파일만 읽고 번역해 보여 준다. 화면은 아무것도 쓰거나 바꾸지 않고, 화면이 죽어도 무선·HUD는 영향이 없다.

**Tech Stack:** Java 8 소스(minSdk 18, 리소스 파일 없이 코드로 화면 구성), POSIX/mksh, 기존 `tests/bridge.sh`·`tests/java.sh`, `app/build.sh`.

**Spec:** `docs/superpowers/specs/2026-11-06-in-car-ui-design.md` (이 계획은 spec의 1단계만 다룬다. 2단계 ONOFF 스위치, 3단계 나머지 스위치, 4단계 관리는 이 단계를 차에서 확인한 뒤 각각 별도 계획으로 쓴다.)

## Global Constraints

- 대상: Kona HEV 한국 V039, Android 4.4.2, minSdk 18, mksh. 리소스(XML·이미지) 없이 코드로 화면을 만든다(`app/build.sh`는 매니페스트만 링크한다).
- 로그·진단 파일의 원문은 영어 코드 그대로 둔다(`FAIL bridge:`, `WAIT bridge:`). 번역은 화면에서만 한다.
- 화면은 읽기 전용이다. 시스템 파일·마커·설정을 쓰지 않는다.
- 무선 감시 프로그램(`service.sh`)은 수정하지 않는다. 수집 서비스의 쓰기 실패는 무시하고 계속 돈다(`|| :`).
- root가 앱 폴더에 쓸 때 심볼릭 링크는 따라가지 않는다.
- **용량 상한(시스템이 넘치지 않게)**: 원본 로그 파일이 128KB를 넘으면 읽지 않고 건너뛴다. 파일 하나당 최근 25줄, 한 줄 최대 200자, 전체 최대 200줄(약 40KB), 출력 파일은 임시 파일에 쓴 뒤 `mv`로 교체하고 임시 파일은 남기지 않는다. logcat은 최근 40줄. 앱 쪽 읽기는 64KB·300줄까지만. 수집 주기는 15초. 이 상한은 테스트로 고정한다.
- 개인정보: 로그를 모을 때 `tools/integrated/diag.sh`의 `PRIV` 패턴(MAC 주소, SSID, 비밀번호, 일련번호, VIN 등)에 걸리는 줄은 버린다.
- 순정 Gen5W 설정 스타일(어두운 배경 `#0b0e12`, 강조색 `#00aad2`, 왼쪽 메뉴 INFO/ONOFF/LOG/관리). 1단계에서 ONOFF·관리 메뉴는 "다음 버전에서 제공" 안내만 보인다.
- 전체 테스트 `bash tests/run.sh`와 unit-commands 정책(`tests/unit_commands.py`)을 통과해야 한다.

## Review Focus

- 스냅샷 파일이 없거나 읽을 수 없을 때(앱이 막 설치됨, 폴더 권한): 화면이 죽지 않고 "상태를 읽을 수 없음"을 보인다.
- 스냅샷이 오래됐을 때(감시 프로그램이 멈춤): 60초 넘으면 "기록이 오래됨"을 표시한다. 값을 현재 상태처럼 보이면 안 된다.
- 번역 표에 없는 로그 줄: 버리지 않고 원문을 그대로 보인다.
- 아주 긴 줄·깨진 UTF-8·60줄 넘는 기록: 잘라서 보이고 화면이 죽지 않는다.
- 앱 폴더에 심볼릭 링크가 있을 때: 수집 서비스가 따라가지 않고 기록을 건너뛴다.
- 용량: 로그가 갑자기 커지거나(원본 128KB 초과) 패키지가 많아도 출력은 상한 안에서 끝난다. 디스크가 가득 차 쓰기가 실패해도 서비스가 죽지 않는다.

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
- Consumes: `LogTranslator.translate`.
- Produces: `public final class StatusModel`
  - `static StatusModel parse(java.util.List<String> statusLines, java.util.List<String> logLines, long nowSeconds)`: `statusLines`는 `key=value` 줄, null이면 `unreadable()`과 같다. `logLines`는 `<출처>|<원문>` 줄(null 허용).
  - `static StatusModel unreadable()`
  - `boolean readable()`, `boolean stale()`(`nowSeconds - ts > 60` 또는 `ts` 없음)
  - `String host()` (`alive`/`dead`/`unknown`), `String relay()` (`on`/`off`/`unknown`), `String backend()`, `String bridgeVersion()`, `boolean apguardOff()`
  - `String why()`: 한 줄 한국어 이유. `host`가 `alive`이거나 `unknown`이면 `""`. 아니면 `logLines` 중 **마지막** `bridge|WAIT bridge:` 또는 `bridge|FAIL bridge:` 줄을 `LogTranslator.translate`로 옮긴 문장. 그런 줄이 없으면 `"원인을 확인하지 못했습니다"`.
  - 스냅샷 키(Task 3과 같음): `ts`(부팅 후 초) `host` `relay` `backend` `version` `apguard` `wired`.

- [ ] **Step 1: 실패하는 테스트.** 단정:
  - 입력 `["ts=1000","host=alive","relay=on","backend=builtin","version=0.3.46","apguard=on","wired=no"]`, 로그 `["bridge|WAIT bridge: wired-only mode is set"]`, now=1010 → `readable()` true, `stale()` false, `host()`=`"alive"`, `why()`=`""`(호스트가 살아 있으면 오래된 WAIT 줄은 무시).
  - `host=dead`, 마지막 bridge 줄이 `WAIT bridge: wireless is not in match mode (ap-match is not 'match')` → `"핫스팟 설정이 아직 일치하지 않아 기다리는 중입니다"`. bridge 줄이 여럿이면 마지막 줄이 이긴다. `core|…` 같은 다른 출처 줄은 무시한다.
  - `host=dead`이고 bridge 줄이 없으면 `"원인을 확인하지 못했습니다"`.
  - now=1100(ts=1000) → `stale()` true. `ts` 없음 → `stale()` true.
  - `parse(null, null, 0)` → `readable()` false. `=`가 없는 줄은 무시(예외 없음). `host=`(값 없음) → `host()`=`"unknown"`.
- [ ] **Step 2: 실행해 실패 확인** — `bash tests/java.sh` → 컴파일 실패.
- [ ] **Step 3: 구현.** 위 서명대로. `ts`는 `Long.parseLong`, 실패하면 없는 것으로 본다.
- [ ] **Step 4: 통과 확인** — `bash tests/java.sh` → `== StatusModel: all passed`.
- [ ] **Step 5: 커밋** — `git commit -m "ui: status model with Korean reasons and staleness"`

---

### Task 3: 전체 로그 수집 서비스 (`uilog.sh`, 코어 패키지)

**Files:**
- Create: `packages/core/scripts/uilog.sh`
- Modify: `packages/core/NEMESIS.data` (`[service.2] name=uilog kind=sh path=scripts/uilog.sh uid=root mode=restart`)
- Create: `tests/uilog.sh`; Modify: `tests/run-shell.sh`(목록에 `tests/uilog.sh` 추가)

**Interfaces:**
- Produces (파일, `UI_DIR=${UILOG_TEST_DIR:-/data/nemesis/gen5wkr.ui}`, 폴더 755, 파일 644):
  - `status`: `key=value` 줄 `ts`(부팅 후 초, `/proc/uptime`) `host`(`alive`/`dead`) `relay`(`on`/`off`/`unknown`) `backend` `version`(브리지 패키지 `package-version`) `apguard`(`on`/`off`) `wired`(`yes`/`no`).
  - `log`: 줄 형식 `<출처>|<원문>`. 출처는 패키지 id에서 `gen5w.kr.`을 뗀 이름(`bridge`, `core`, `bluelink`…)과 `logcat`. 한 번에 하나의 `log`로 교체된다.
- 환경 변수(테스트용): `UILOG_TEST_DATA`(기본 `/data`), `UILOG_TEST_DIR`, `UILOG_TEST_ONCE`(한 번 수집하고 종료), `UILOG_TEST_LOGCAT`(logcat 대신 쓸 명령), `UILOG_TEST_INTERVAL`.

- [ ] **Step 1: 실패하는 테스트** (`tests/uilog.sh`, `tests/lib.sh`의 `check` 사용, `tests/core.sh` 형식). 가짜 `/data/nemesis/logs/gen5w.kr.bridge/bridge.log` 등을 만들고 한 번 실행해 단정:
  - `status`에 `ts=`·`host=`·`version=`·`apguard=`·`wired=`·`backend=` 줄이 있다. 마커 `gen5wkr.apguard.off`면 `apguard=off`, `gen5wkr.wireless-disabled`면 `wired=yes`, `bridge-ready`에 살아 있는 pid(테스트가 띄운 프로세스)가 있으면 `host=alive`, 없으면 `host=dead`.
  - `log`에 `bridge|WAIT bridge: …` 줄이 원문 그대로 있고, 다른 패키지(`gen5w.kr.bluelink`)의 줄도 `bluelink|…`로 들어 있다.
  - 폴더 755, `status`·`log` 644. 임시 파일이 `UI_DIR`에 남지 않는다.
  - **용량 상한**: 원본 1개에 300줄 → 그 출처는 25줄. 한 줄 500자 → 200자 이하. 패키지 20개×300줄 → `log` 전체 200줄 이하, 파일 크기 64KB 이하. 130KB짜리 원본 → 그 출처는 `<출처>|(로그가 너무 커서 건너뜀)` 한 줄만. logcat 출력 500줄 → 40줄.
  - **개인정보**: MAC 주소(`aa:bb:cc:dd:ee:ff`), `ssid=`, `VIN=`이 든 줄은 `log`에 없다.
  - **안전**: `UI_DIR` 또는 `status`/`log`가 심볼릭 링크면 링크 대상 파일 내용이 바뀌지 않는다. 앱 폴더(`UI_DIR`의 부모)가 없으면 아무것도 만들지 않고 정상 종료. 원본 로그 폴더가 없어도 `status`는 쓴다.
  - 같은 실행을 두 번 해도 `log`가 쌓이지 않는다(교체).
- [ ] **Step 2: 실행해 실패 확인** — `mksh tests/uilog.sh`(Git Bash에 mksh가 없으면 WSL) → 스크립트 없음으로 실패.
- [ ] **Step 3: 구현** (`#!/system/bin/sh`, mksh R43, `tests/unit/policy.txt` 허용 명령만. `tail`/`head`/`wc`/`sed`/`mktemp` 금지):
  - 원본 크기는 `set -- $(ls -l "$f")`의 4번째 필드. 숫자가 아니면 건너뛴다.
  - 파일마다 `grep -a -v -E "$PRIV" "$f"`(출력은 `UI_DIR`의 임시 파일)로 거른 뒤 `diag.sh`의 `last_lines`와 같은 방식(세고 건너뛰기)으로 마지막 25줄만 읽고 `${line:0:200}`로 자른다. 총 줄 수가 200에 닿으면 나머지 출처는 건너뛴다. bridge 출처를 가장 먼저 처리한다.
  - logcat: `logcat -d -v time` → `grep -a -E 'Gen5w|gen5w|FATAL EXCEPTION'` → `PRIV` 제거 → 마지막 40줄.
  - 쓰기: `UI_DIR`·`status`·`log` 모두 링크가 아니어야 하고, 임시 파일에 쓴 뒤 `mv`. 모든 실패는 건너뛰고 루프를 계속한다(`|| :`). 주기 15초.
  - `host`는 `service.sh`의 `host_alive`와 같은 검사(`bridge-ready`의 pid가 살아 있고 `/proc/<pid>/cmdline`에 `kr.gen5w.wirelesshost`). `relay`는 브리지 패키지의 `scripts/relay-gate.sh` 종료 코드(0=on, 77=off, 그 외·없음=unknown).
  - 시작할 때 `UI_DIR`의 부모가 디렉터리가 아니면 15초마다 다시 확인한다(앱이 막 설치된 직후).
- [ ] **Step 4: 통과 확인** — `mksh tests/uilog.sh` 통과, 이어서 `bash tests/run.sh` 전체 통과(`core.sh`·`integrated*.sh`가 코어 서비스 목록·uid를 검사하면 새 서비스에 맞게 갱신).
- [ ] **Step 5: 커밋** — `git commit -m "core: collect bounded logs from every gen5w package for the in-car screen"`

---

### Task 4: 화면 (`MainActivity`)

**Files:**
- Create: `app/src/kr/gen5w/ui/MainActivity.java`
- Modify: `app/AndroidManifest.xml` (Activity 선언, 런처 인텐트)
- Modify: `app/build.sh` (필요하면 소스 목록은 `find src`라 변경 없음. 확인만)

**Interfaces:**
- Consumes: `StatusModel.parse(List<String>, List<String>, long)`, `StatusModel.unreadable()`, `LogTranslator.translate`, `LogTranslator.category`.
- Produces: `public final class MainActivity extends android.app.Activity`.

- [ ] **Step 1: 매니페스트.** `<activity android:name="kr.gen5w.ui.MainActivity" android:exported="true" android:theme="@android:style/Theme.Black.NoTitleBar" android:label="Gen5W KR">` + 인텐트 필터 `MAIN`/`LAUNCHER`. 기존 서비스·리시버·`uses-library`는 그대로. `versionCode`는 3으로 올리고 `app/build.sh`의 `--version-code 3`도 같이 맞춘다.
- [ ] **Step 2: 구현.** 코드로만 화면을 구성한다(왼쪽 메뉴 4개 + 오른쪽 내용).
  - `onResume`에서 `new File(getApplicationInfo().dataDir, "gen5w-ui/status")`와 `log`를 읽는다(백그라운드 스레드, 5초마다 갱신, `onPause`에서 멈춤). 읽기 실패·없음은 `StatusModel.unreadable()`.
  - INFO: `why()`가 비어 있지 않으면 노란 설명 상자. 목록은 무선 호스트(실행 중/꺼짐/확인 못 함), 릴레이(켜짐/꺼짐/확인 못 함), 설치 버전, 내장 Wi-Fi 방식, 재시작 보호(정상/걸림). `stale()`이면 맨 위에 "기록이 오래됨(마지막 갱신 N초 전)", `!readable()`이면 "상태를 읽을 수 없음" 한 줄과 안내만 보인다.
  - LOG: 필터 칩 전체/오류/무선/설치(`LogTranslator.category`)와 출처 칩(전체/bridge/core/…). 각 줄은 출처 이름 + `translate`한 문장 + 원문(작게). 파일은 앞의 64KB·300줄까지만 읽는다. 새로고침 버튼은 즉시 다시 읽기.
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
- **타입 일관성**: `StatusModel.parse(List<String>, List<String>, long)`·`unreadable()`·`why()`·`stale()`, `LogTranslator.translate/category`, `BoundedLines.read`가 Task 1·2·4에서 같은 이름이다. 스냅샷 키는 Task 2와 Task 3에서 같다.
- **미확정**: `/data/nemesis/gen5wkr.ui`(root 소유)를 앱이 읽을 수 있는지(읽을 수 없으면 시스템 권한 도우미로 읽는 방식으로 바꾼다), 런처에 아이콘이 뜨는지는 PC에서 확인할 수 없다. Task 5의 체크리스트로 차에서 확인한다. 읽을 수 없으면 `상태를 읽을 수 없음`이 뜨고 무선·HUD에는 영향이 없다.

## 구현 중 바뀐 것 (2026-11-06)

- 보안 검토(root가 앱 소유 폴더에 쓰면 폴더 바꿔치기 경합 가능)를 받아 출력 위치를 `/data/nemesis/gen5wkr.ui`(root 소유)로 옮겼다. 앱이 이 폴더를 읽을 수 있는지는 차에서 확인한다.
- `ts`는 부팅 후 초(`/proc/uptime`)다. 차 시계에 의존하지 않고, 지난 부팅의 낡은 파일은 "이전 부팅 때의 기록"으로 표시한다.
- 앱의 파일 읽기는 `BoundedLines`(64KB·300줄)로 상한을 둔다. 테마는 `Theme.Black.NoTitleBar`(전체 화면 아님).
- 화면은 PC 에뮬레이터(1024x600)에서 INFO·LOG·필터 동작을 확인했다. 차에서의 런처 노출과 폴더 읽기는 미확인.
