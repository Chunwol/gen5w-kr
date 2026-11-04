# 헤드유닛 단독 HUD · 클러스터 길안내 개발 방향성

티맵·카카오내비·네이버지도(Android Auto / CarPlay) 6종 바이너리 정적 분석과 V039 순정 `HKMC_DiPO.odex`·`HKMC_GPM.odex`·`com.tcc.iap2` 역분석 결과를 바탕으로 확정한 **헤드유닛 단독(Head-Unit Standalone) 개발 방향**입니다.

---

## 1. 기본 원칙

1. **폰 보조 앱(브리지) 배제 — 100% 헤드유닛 단독 동작**
   - 사용자 스마트폰에 별도 앱(NotificationListener, 접근성 서비스 등)을 설치하지 않습니다.
   - 헤드유닛이 USB/무선 프로젝션(iAP2 및 Android Auto GAL 프로토콜)으로 이미 수신하고 있는 데이터만 활용합니다.
2. **과도한 자가 제한 해제 (`afterRoad` / `road` / `desc` 텍스트 보강 허용)**
   - 3사 내비게이션 앱 모두 1차 TBT 회전 코드에서 톨게이트(TG)·하이패스·휴게소·졸음쉼터를 `STRAIGHT(36)` / `NAME_CHANGE(2)` / `StraightAhead(3)` / `NoTurn(0)`으로 축약해 보냅니다.
   - 따라서 "도로명·안내문 글자를 보지 않는다"는 기존 자가 제한을 해제하고, **비방향성 직진(`0x41`, `0xac`) 또는 CarPlay `NoTurn(0)`일 때에 한해** 도로명·안내문 키워드로 V039 클러스터의 **`TOLL(0xb2)`** 및 **`REST_AREA(0xb7)`** 아이콘을 복원합니다.
   - 좌·우 회전(`0x42..0x47`), 유턴(`0x48..0x49`), 진출입 램프(`0xa0..0xa5`), 분기(`0xa6..0xab`), 회전교차로(`0x60..0x69`) 등 **방향성 화살표가 있는 경우에는 텍스트로 절대 덮어쓰지 않습니다**.

---

## 2. 방향 1 — 텍스트 기반 TG(`0xb2`) · 휴게소/졸음쉼터(`0xb7`) 복원 (즉시 적용)

### 2.1 앱별 전송 데이터 근거

| 구분 | 티맵 | 카카오내비 | 네이버지도 |
|---|---|---|---|
| **Android Auto 회전 타입** | `STRAIGHT(36)` → GPM `0x41` | `Tollgate(84)`·`NonstopTollgate(85)` → `STRAIGHT(36)` → GPM `0x41` | `Tollgate`·`HipassTollgate`·`OneTollingTollgate`·`Rest`·`DrowsinessShelter` → `NAME_CHANGE(2)` → GPM `0x41` |
| **CarPlay 회전 타입** | `sa(85..86)`·`tolExp(87)`·`tolNormal(88)`·`tollgate(140)` → `StraightAhead(3)` / `hipass*(49..51)` → `NoTurn(0)` | `Tollgate(75)`·`NonstopTollgate(76)` → `StraightAhead(3)` | `tollgate`·`hipassTollgate`·`oneTollingTollgate`·`rest`·`drowsinessShelter` → `StraightAhead(3)` (`accessRest`만 `HighwayOffRampRight(23)` → `0xa4`) |
| **함께 넘어오는 문자열(`road` / `afterRoad` / `desc`)** | 시설명(`"서울TG"`, `"안성휴게소"` 등) 및 요금 문자열(`"\n요금: 1000원"`) | 시설명(`"서울톨게이트"`, `"서울TG"`, `"망향휴게소"`, `"졸음쉼터"`) | 시설명(`"~톨게이트"`, `"~요금소"`, `"~TG"`, `"~휴게소"`, `"~졸음쉼터"`) |

### 2.2 헤드유닛 `ClusterIcon` 변환 규칙 (`app/src/kr/gen5w/hud/ClusterIcon.java`)

- **적용 대상**:
  - CarPlay (`ClusterIcon.of(Maneuver m)`): `m.type == 3`(`StraightAhead` → `0x41`), `m.type == 5`(`FollowRoad` → `0xac`), `m.type == 0`(`NoTurn`, `drivingSide == 0 && junctionType == 0 && exitAngle == 0`)
  - Android Auto (`ClusterIcon.refineManeuver(int baseIcon, String road, String desc)` 및 `CoreService.java`): `baseIcon == 0x41` 또는 `baseIcon == 0xac`
- **키워드 매칭 규칙**:
  1. **`TOLL(0xb2)` 승격**: `"톨게이트"`, `"요금소"`, `"하이패스"`, `"원톨링"`, `"통행료"`, `"요금:"`, `"요금 :"`, 또는 독립 토큰/접미사 `"TG"`(`"서울TG"`, `"동서울 TG"` 등 한글·공백 경계와 결합된 `"TG"`)
  2. **`REST_AREA(0xb7)` 승격**: `"휴게소"`, `"졸음쉼터"`
  3. **그 외(IC/JC 등)**: 직진 상태에서 `"판교IC"`, `"신갈JC"` 등이 들어와도 진·출입 방향을 임의로 지어내지 않고 직진(`0x41`)을 유지합니다(구조화된 `type=9/22/23` 및 AA `ON_RAMP/OFF_RAMP`는 이미 `0xa0..0xa5`로 매핑됨).

---

## 3. 방향 2 — 헤드유닛 `HKMC_GPM` 네이티브 / DEX 후킹 아키텍처 (Android Auto)

스마트폰을 건드리지 않고 헤드유닛 내부의 순정 Android Auto 리시버 앱(`HKMC_GPM.odex` + `libautoreceiver_infobank.so`)에서 데이터를 가로채거나 보강하는 방식입니다.

### 3.1 순정 V039 `HKMC_GPM` 내부 파이프라인 구조

V039 `HKMC_GPM.odex` 역분석으로 확인한 Android Auto 내비게이션 데이터 흐름은 다음과 같습니다.

```text
[스마트폰 Android Auto (Gearhead)]
   │  USB / Wi-Fi GAL 프로토콜
   │  Service ID = 0x9 (NAVIGATION_STATUS_SERVICE_ID)
   ▼
[1] 네이티브 계층: libautoreceiver_infobank.so (GalReceiver.<clinit>에서 로드)
   │  - 0x8001: INSTRUMENT_CLUSTER_START
   │  - 0x8002: INSTRUMENT_CLUSTER_STOP
   │  - 0x8003: INSTRUMENT_CLUSTER_NAVIGATION_STATUS
   │  - 0x8004: INSTRUMENT_CLUSTER_NAVIGATION_TURN_EVENT (Protos$NavigationNextTurnEvent)
   │  - 0x8005: INSTRUMENT_CLUSTER_NAVIGATION_DISTANCE_EVENT (Protos$NavigationNextTurnDistanceEvent)
   │  (※ 0x8006 INSTRUMENT_CLUSTER_NAVIGATION_STATE는 순정 프로토콜 정의에서 누락)
   │
   │  JNI Upcall (C++ → Java)
   ▼
[2] com.google.android.projection.protocol.NavigationStatus
   │  - navigationNextTurnCallback(String road, int turnSide, int event, byte[] image, int turnNumber, int turnAngle)
   │  - navigationNextTurnDistanceCallback(int distanceMeters, int timeToTurnSeconds, int displayDistanceE3, int distanceUnits)
   │  - navigationStatusCallback(int status)
   ▼
[3] com.google.android.projection.service.GalConnectionSession$4
   │  - onNextTurn(String road, int turnSide, int event, byte[] image, int turnNumber, int turnAngle)
   │    (여기서 p4 byte[] image를 버리고 GpmNaviTBTManager로 전달)
   ▼
[4] com.telechips.android.gpm.manager.GpmNaviTBTManager
   │  - onNextTurn(String road, int turnSide, int event, int turnNumber, int turnAngle)
   │    - setTurnDisplayType / setRampDisplayType / setRoundaboutDisplayType으로 mDisplayType(0x41..0xa9) 결정
   │    - updateTBTInfo() / updateTPCrossroadName(road) 호출
   │    - ※ NavigationCluster.updateLaneInfo(...) 호출은 아예 존재하지 않음
```

### 3.2 방식 A — `HKMC_GPM.odex` DEX 후킹 / 패치 (TBT · 도로명 · TG/휴게소 아이콘)

- **원리**:
  - 이미 Java 계층인 `GpmNaviTBTManager.onNextTurn(String road, int turnSide, int event, int turnNumber, int turnAngle)`과 `onNextTurnDistance(int distanceMeters, ...)`에 **`String road`(교차로/도로/시설명 + 티맵 요금 문자열)**, **`int event`(`NextTurnEnum` `0..19`)**, **`int turnSide`(`1..3`)**, **`int distanceMeters`**가 전부 올라와 있습니다.
- **구현 방법 (택 1 또는 병행)**:
  1. **`CoreService` 로컬 소켓(`gen5wkr.aa.tbt`) / 브로드캐스트(`kr.gen5w.action.AA_TBT`) 포워딩**:
     - `GpmNaviTBTManager.onNextTurn` / `onNextTurnDistance`에서 결정된 `mDisplayType`(`ICON`), `mDistance`(`DIST`), `mTurnName`(`ROAD`)을 `CoreService`로 전달합니다.
     - `CoreService`는 이미 `ClusterIcon.refineManeuver(icon, road, desc)`와 `renderAaTbt(...)`를 갖추고 있어, `mDisplayType == 0x41`(직진/`NAME_CHANGE`)일 때 `road`에 `"TG"`/`"톨게이트"`/`"요금소"`/`"요금:"`/`"휴게소"`/`"졸음쉼터"`가 있으면 즉시 `0xb2`(톨게이트) 또는 `0xb7`(휴게소)로 바꿔 계기판·HUD에 송출합니다.
  2. **`GpmNaviTBTManager` 직접 smali 패치**:
     - `GpmNaviTBTManager.setTurnDisplayType` 직후 `mDisplayType == 0x41`일 때 `mTurnName`(`p1`) 문자열을 검사하여 `0xb2` 또는 `0xb7`을 `mDisplayType`에 대입합니다.
- **장점**: 네이티브(`.so`) 수정 없이 Java/smali 계층만으로 Android Auto 3사 앱의 TG(`0xb2`)·휴게소(`0xb7`) 아이콘과 교차로명/거리 연동을 완벽하게 처리할 수 있습니다.
- **한계**: `0x8006`(`NavigationState`)에 들어 있는 **구조화 차선(`NavigationLane`)**은 C++(`libautoreceiver_infobank.so`)에서 Java로 올려주지 않으므로 DEX 후킹만으로는 차선 정보를 얻을 수 없습니다.

### 3.3 방식 B — `libautoreceiver_infobank.so` 네이티브 후킹 (Android Auto 구조화 차선 `0x8006` 복원)

- **왜 네이티브 후킹이 필요한가**:
  - 티맵(`com.skt.tmap.car.screen.e1`, 하이패스 차로 `"0808"` 포함), 카카오(`HipassProvider` 포함), 네이버(`AutoRouteGuidanceStore.x/z`) 세 앱 모두 Android Auto `Step.Builder.addLane(...)`에 구조화 차선(`Lane` + `LaneDirection`)을 넣어 전송합니다.
  - 스마트폰의 Android Auto(Gearhead)는 이 데이터를 GAL 채널 `0x9`(`NavigationStatusService`)의 메시지 ID **`0x8006`(`INSTRUMENT_CLUSTER_NAVIGATION_STATE`)** protobuf(`steps[0].lanes[].lane_directions[]{shape, is_highlighted}`)로 직렬화합니다.
  - 그러나 V039의 `libautoreceiver_infobank.so`는 구형 메시지 `0x8001..0x8005`만 파싱하도록 컴파일되어 있어 `0x8006` 패킷이나 `NavigationLane` 필드를 Java로 전달하지 않습니다.
- **구현 방법**:
  1. `HKMC_GPM` 프로세스에 `LD_PRELOAD` 또는 GOT/PLT 후킹 라이브러리를 주입하여 `libautoreceiver_infobank.so`의 GAL 채널 `0x9` 수신 콜백을 가로챕니다.
  2. 수신된 GAL 프레임 중 메시지 ID `0x8006`(`INSTRUMENT_CLUSTER_NAVIGATION_STATE`)이거나 `0x8004` 확장 필드인 경우, 경량 protobuf 리더로 현재 Step의 `lanes[].lane_directions[]{shape, is_highlighted}`를 파싱합니다.
     - `LaneShape` enum (`1=UNKNOWN`, `2=STRAIGHT(0°)`, `3=SLIGHT_LEFT(-45°)`, `4=SLIGHT_RIGHT(+45°)`, `5=NORMAL_LEFT(-90°)`, `6=NORMAL_RIGHT(+90°)`, `7=SHARP_LEFT(-135°)`, `8=SHARP_RIGHT(+135°)`, `9=U_TURN_LEFT(-180°)`, `10=U_TURN_RIGHT(+180°)`)
  3. 파싱한 차선 배열을 이미 `CoreService.java`에 구현된 로컬 소켓 `gen5wkr.aa.tbt` 포맷(`LANE:<count>:<angle[#]>|<angle[#]>...`)으로 전송합니다.
  4. `CoreService.handleAaClient`(`app/src/kr/gen5w/core/CoreService.java:712-743`)가 이를 `LaneFrame.encodeSimple(...)`로 81바이트 V039 차선 프레임(`0xf1 ...`)으로 인코딩해 `cluster.updateLaneInfo(...)`를 호출함으로써 **Android Auto에서도 일반 차선 및 티맵·카카오 하이패스 추천 차로를 HUD/계기판에 표시**합니다.

---

## 4. 방향 3 — CarPlay (`iAP2 0x5202`) `ClusterIcon` 누락 케이스 보강

3사 iOS 앱이 실제로 보내는 `CPManeuverType` 조합 중 순정 V039 `HKMC_DiPO.odex`(`RouteGuidanceAnalyzer`)가 분기를 빠뜨려 `NONE(-1)`이 되는 항목들과 헤드유닛 측 보강 설계입니다.

| 케이스 | 송신하는 앱 및 상황 | 순정 V039 `HKMC_DiPO` 동작 | 헤드유닛 `ClusterIcon.of` 보강 방향 |
|---|---|---|---|
| **`KeepLeft(13)` / `KeepRight(14)`** | **네이버·티맵 CarPlay**: 분기(`left/rightDirection`), 고가·지하 진입/측도, 티맵 좌·우 IC/JC 진입(`icInLeft/Right`, `jcInLeft/Right`) | case `13`, `14` 자체가 없어 `NONE` 반환 | `13` → 좌측 분기/유지(`0xa7` 또는 `0x47`), `14` → 우측 분기/유지(`0xa6` 또는 `0x42`) 매핑 |
| **`OffRamp(8)` / `OffRamp(10)`** | **카카오 CarPlay**: 직진형 `OutHighway`/`OutCityway` → `8`<br>**티맵 CarPlay**: `icOut(115)`/`jcOut(118)` → `10` | `9`(`OnRamp` → `0xa0`), `22`(`0xa5`), `23`(`0xa4`)만 있고 `8`, `10`은 `NONE` | `8`, `10`(`d==0 && j==0 && a==0`) → 고속도로 진출(`0xa3` `IC_EXIT_C` 또는 `0xa4` `IC_EXIT_R`) 매핑 |
| **`exitAngle` 미포함 일반 회전 (`1, 2, 47, 48, 49, 50`)** | **티맵·카카오·네이버 CarPlay**: 일반 좌/우회전(`1, 2`), 급회전(`47, 48`), 완만한 회전(`49, 50`)에서 앱이 `setJunctionExitAngle:`을 호출하지 않는 경우 | `a == -90`, `+90`, `±120`, `±60`, `±45` 등 정확한 각도가 없으면 `NONE` | 실차 `0x5202` 캡처에서 `exitAngle`이 `UNKNOWN_ANGLE` 또는 `0`으로 올 경우 타입별 기본 아이콘(`1→0x46`, `2→0x43`, `47→0x45`, `48→0x44`, `49→0x47`, `50→0x42`) fallback 제공 |
| **`junctionType == 1` 회전교차로 (`type = 0` 또는 `6`)** | **카카오 CarPlay**: `type = 6`(`EnterRoundabout`) + `j = 1` + `exitAngle`<br>**네이버·티맵 CarPlay**: `type = 0`(`NoTurn`) + `j = 1` + `exitAngle` | `type = 19, 28..35`만 회전교차로로 처리하여 `type = 0, 6`은 `NONE` | `j == 1`이고 `type == 0 || type == 6`일 때 `exitAngle`만으로 회전교차로 방향 아이콘(`0x61..0x69`) 선택 |

> **설계 원칙**: 순정 V039 `HKMC_DiPO` 회귀 테스트(`V039DipoIconTest`)와의 정합성을 유지하기 위해, 위 4가지 CarPlay 구조 보강은 실차 iAP2 `0x5202` 패킷 로그에서 iOS `CarPlay` 데몬의 각도·타입 직렬화 형태를 1회 확인한 즉시 해당 조건 분기를 활성화합니다.

---

## 5. 단계별 로드맵

| 단계 | 작업 항목 | 상태 | 비고 |
|---|---|---|---|
| **Phase 1** | 도로명·안내문 텍스트 기반 TG(`0xb2`) · 휴게소/졸음쉼터(`0xb7`) 승격 (`ClusterIcon.of`, `ClusterIcon.refineManeuver`, `CoreService`) 및 JVM 테스트 검증 | **완료** | 직진(`0x41`, `0xac`) 및 CarPlay `NoTurn(0)`에서만 동작, 방향성 화살표 보존 |
| **Phase 2** | `HKMC_GPM.odex` DEX 후킹 연동 (`GpmNaviTBTManager.onNextTurn` → `gen5wkr.aa.tbt` / `0xb2`·`0xb7` 승격) | 설계 완료 · 패키징 대기 | Android Auto 3사 앱 TG·휴게소 아이콘 및 교차로명 연동 |
| **Phase 3** | CarPlay 실차 `0x5202` 1회 캡처 및 `ClusterIcon` 4대 누락 케이스(`13/14`, `8/10`, 무각도 `1/2/47..50`, `j=1` 회전교차로) fallback 활성화 | 설계 완료 · 실차 로그 대기 | iOS가 기본 각도를 합성하지 않는 항목 즉시 보강 |
| **Phase 4** | `libautoreceiver_infobank.so` GAL 채널 `0x9` 네이티브 후킹 (`0x8006` `NavigationLane` 파싱 → `gen5wkr.aa.tbt` `LANE:`) | 설계 완료 | Android Auto 3사 앱 구조화 차선 및 티맵·카카오 하이패스 차로 HUD 표시 |
