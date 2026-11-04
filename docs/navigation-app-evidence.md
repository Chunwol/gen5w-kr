# 지도 앱 길안내 변환 계층

네이버지도·티맵·카카오내비가 Android Auto와 CarPlay에 넘기는 구조화 안내를 앱 실행 코드에서 추적한 기록입니다. 분석 대상 바이너리는 배포하지 않습니다. 앱이 API 객체를 만든다는 사실은 Android Auto·iOS가 같은 숫자로 직렬화하거나 V039 계기판/HUD가 실제 표시한다는 증거와 구분합니다.

## 분석 대상

| 앱 | Android | iPhone |
|---|---|---|
| 티맵 | 11.8.3.4061, SHA-256 `9C39DE05597F1B26EDAE9F97B14E76548808C8DEFECF265613309D45AE621330` | 11.8.4, SHA-256 `D9975E15431197E57A316D4D9AED884AF31B172DCD0DB7B075CC88AE5D7F3FFE` |
| 카카오내비 | 4.46.1, SHA-256 `080115C66ED6D211CB1D09CD6E76690295E250F2298C6DADF6B28463D6EB64D5` | 4.52.0, SHA-256 `FE1F94EDD64499D01735F774FE0A44784AEDBBA4A312525ADA5BC1D338581F71` |
| 네이버지도 | 6.11.2.2, SHA-256 `73D58F3C02726357D5783416A8B9994D24A2A1209201FC76F06FCE8A9802449F` | 6.12.1, SHA-256 `4FCE32F95B3B7E9CBDB190D31E69BF77DEF9C7DFD3FE6FBF98B562DF1B6B8F64` |

## Android Auto

세 앱은 자체 길안내 코드를 AndroidX Car App의 `Maneuver`, `Step`, `Trip`으로 바꾸고 `NavigationManager`를 거쳐 `INavigationHost.updateTrip`에 전달합니다. V039에서는 Android Auto 호스트가 만든 Google `NavigationStatus`를 순정 `HKMC_GPM`의 `GpmNaviTBTManager`가 클러스터 아이콘과 거리로 다시 변환합니다. AndroidX type 번호를 CarPlay iAP2 type 번호로 재사용하지 않습니다.

### 카카오내비

`classes5.dex`의 실행 경로에서 `KNRGCode`를 AndroidX type으로 바꾸고 현재·다음 Step과 거리·시간을 Trip에 넣어 `updateTrip`까지 보내는 것을 확인했습니다.

| AndroidX type | 카카오 내부 코드 |
|---|---|
| `STRAIGHT(36)` | Straight, Out/InHighway, Direction12, Out/InCityway, Tollgate, NonstopTollgate, JoinAfterBranch |
| `TURN_SLIGHT_LEFT/RIGHT(5/6)` | Direction10·11 / Direction1·2 |
| `TURN_NORMAL_LEFT/RIGHT(7/8)` | LeftTurn·Direction9·UnprotectedLeft / RightTurn·Direction3 |
| `TURN_SHARP_LEFT/RIGHT(9/10)` | Direction7·8 / Direction4·5 |
| `U_TURN_LEFT(11)` | UTurn, Direction6 |
| `KEEP_LEFT/RIGHT(3/4)` | LeftStraight / RightStraight |
| `ON_RAMP_NORMAL_LEFT/RIGHT(15/16)` | 좌·우 고속도로/도시고속도로 진입 및 차로 변경 (`LeftInCityway/Highway`, `ChangeLeftHighway` / `RightInCityway/Highway`, `ChangeRightHighway`) |
| `OFF_RAMP_NORMAL_LEFT/RIGHT(23/24)` | 좌·우 고속도로/도시고속도로 진출 (`LeftOutCityway/Highway` / `RightOutCityway/Highway`) |
| `FORK_LEFT/RIGHT(25/26)` | 방향 분기, 고가·지하·터널 진입/측도 |
| `ROUNDABOUT_CCW_WITH_ANGLE(35)` | Rotary 30~41, Roundabout 70~81 |
| `DEPART/DESTINATION/FERRY(1/39/37)` | Start / Goal·Via / In·OutFerry |

회전교차로 suffix 1~12는 각각 150°, 120°, 90°, 60°, 30°, 360°, 330°, 300°, 270°, 240°, 210°, 180°로 변환됩니다. 차선은 구조화된 `Lane` 목록과 bitmap을 함께 Step에 넣으며, 하이패스 구간(`HipassProvider.kt`, `com.kakaomobility.knmsdk.v50.b`)에서는 일반 차선 대신 하이패스 차선(`first > 0`)을 `LaneDirection.create(STRAIGHT(2), isRecommended=true)`로, 현금 차선(`first == 0`)을 `LaneDirection.create(UNKNOWN(1), isRecommended=false)`로 만들어 첫 번째 Step(`currentStep`)의 `addLane(...)`과 `setLanesImage(hipassBitmap)`에 넣습니다.

SA(휴게소)·TG(톨게이트)·IC·JC·RA(졸음쉼터)·SATR(화물차휴게소)(`NPHighwayRGType`)는 1차 Step 회전 코드가 아니라, 현재 안내 지점까지 남은 거리가 `2099m`를 초과할 때(`NaviTemplate.T`) **2번째 Step(`nextStep`)의 사용자 정의 그림(`aa_highway_sa/tg/ic/jc/ra`)과 안내문(`"{거리} ({시설명})"` / 요금 문자열)**으로만 구성되며 구조화된 시설 type으로 전달되지는 않습니다. 1차 Step에서 `Tollgate(84)`와 `NonstopTollgate(85)`는 둘 다 `STRAIGHT(36)`으로 합쳐지며, 헤드유닛 `ClusterIcon.refineManeuver`가 직진(`0x41`) 상태에서 도로명·안내문의 톨게이트/요금소/TG·휴게소/졸음쉼터 키워드를 감지해 `TOLL(0xb2)`·`REST_AREA(0xb7)`로 보강합니다.

### 네이버지도

`base.apk/classes6.dex`의 `AutoRouteGuidanceStore.w`와 `GuidanceCodeUtilsKt.b`에서 `TurnPointType → Maneuver.Builder` 실제 호출과 전체 switch를 확인했습니다.

| AndroidX type | 네이버 TurnPointType |
|---|---|
| `STRAIGHT(36)` | Straight |
| `TURN_NORMAL_LEFT/RIGHT(7/8)` | Left·UnsafeLeft·Direction9·AccessCityRoadLeft / Right·Direction3·AccessCityRoadRight |
| `TURN_SHARP_LEFT/RIGHT(9/10)` | Direction8 / Direction4 |
| `TURN_SLIGHT_LEFT/RIGHT(5/6)` | Direction11 / Direction1 |
| `U_TURN_LEFT/RIGHT(11/12)` | UTurn / PTurn |
| `FORK_LEFT/RIGHT(25/26)` | 좌·우 방향 분기, 분기·고가·지하 진입/측도 |
| `ROUNDABOUT_CCW_WITH_ANGLE(35)` | 모든 Rotary·Roundabout straight/UTurn/direction |
| `NAME_CHANGE(2)` | 터널·교량·휴게소 진입, 직진형 고속도로/도시도로/자동차전용도로 진입·진출, DivideAndJoin, TG·하이패스·원톨링, Rest·DrowsinessShelter |
| `ON_RAMP_SLIGHT_LEFT/RIGHT(13/14)` | AccessCarOnlyLeft/Right |
| `ON_RAMP_NORMAL_LEFT/RIGHT(15/16)` | AccessHighwayLeft/Right |
| `OFF_RAMP_SLIGHT_LEFT/RIGHT(21/22)` | ExitCityRoadLeft/Right, ExitCarOnlyLeft/Right |
| `OFF_RAMP_NORMAL_LEFT/RIGHT(23/24)` | ExitHighwayLeft/Right |
| `MERGE_LEFT/RIGHT(27/28)` | JoinLeft/Right |
| `FERRY/DESTINATION(37/39)` | AccessFerry / Via·Goal |

Roundabout type 35일 때만 출구 번호와 변환된 각도를 Builder에 넣습니다. `AutoRouteGuidanceStore.x/z`는 `RouteLaneUnit`을 구조화된 Lane 목록으로 만들고 현재 유효 방향을 추천 차선으로 표시합니다. `classes21.dex`의 `RgNotificationLifecycleObserver.w`는 Step·TravelEstimate·Destination을 Trip에 넣은 뒤 `NavigationManager`를 통해 `updateTrip`을 호출합니다.

TG·IC·JC·휴게소는 전용 AndroidX 시설 필드가 아니라 `NAME_CHANGE`, ramp, merge, fork, Step 문자열 또는 CarIcon으로 축약됩니다. 순정 `HKMC_GPM`은 `NAME_CHANGE(2)`를 직진(`0x41`)으로만 바꾸므로, 헤드유닛 `ClusterIcon.refineManeuver`에서 직진(`0x41`)에 한해 도로명·안내문 키워드로 `TOLL(0xb2)`·`REST_AREA(0xb7)`를 복원합니다.

### 티맵

`base.apk/classes30.dex`의 실제 TBT observer(`com.skt.tmap.car.screen.e1`)가 `TBTInfo.nTBTTurnType`을 `com.skt.tmap.car.y.c`로 변환해 `Maneuver.Builder`에 넣고, Step/Trip을 만든 뒤 AndroidX `NavigationManager`의 Binder `updateTrip`까지 호출합니다.

| AndroidX type | 티맵 raw TBT code |
|---|---|
| `FORK_RIGHT(26)` | 6, 73, 74, 117, 123, 124 |
| `FORK_LEFT(25)` | 7, 75, 76, 118 |
| `ON_RAMP_SLIGHT_RIGHT/LEFT(14/13)` | 101·111 / 102·112 |
| `OFF_RAMP_SLIGHT_RIGHT/LEFT(22/21)` | 104·114 / 105·115 |
| `TURN_NORMAL_LEFT/RIGHT(7/8)` | 12 / 13·15 |
| `U_TURN_LEFT(11)` | 14 |
| `TURN_SHARP_LEFT/RIGHT(9/10)` | 16 / 19 |
| `TURN_SLIGHT_LEFT(5)` | 17 |
| `ROUNDABOUT_CCW_WITH_ANGLE(35)` | 18, 31~42, 131~142 |
| `KEEP_RIGHT(4)` | 43 |
| `DEPART/DESTINATION(1/39)` | 44·200 / 201 |
| `STRAIGHT(36)` | 그 밖의 값 |

31~41과 131~141은 150°, 120°, 90°, 60°, 30°, 360°, 330°, 300°, 270°, 240°, 210°로 대응하며 기본 각도는 180°입니다. 별도 switch가 출구 번호 1~4를 설정합니다. `szTBTMainText`는 cue, 현재 도로명은 Step road와 Trip current road, 남은 거리·시간은 TravelEstimate에 들어갑니다.

구조화 차선(`androidx.car.app.navigation.model.Lane` 및 `LaneDirection`) 역시 `classes30.dex`의 `com.skt.tmap.car.screen.e1`과 `classes31.dex`의 `com.skt.tmap.util.laneresource.a`에서 실제로 생성해 첫 번째 TBT `Step.Builder`(`x0.addLane(...)`)에 넣는 것을 확인했습니다.
- 일반 차선(`showLane == true`): 차선 수만큼 순회하며 `laneTurnInfo`(`1..63` 비트마스크), `laneAvailableInfo`, `laneEtcInfo`(`UNDERPASS`/`OVERPASS`)를 `laneresource.a.c(...)`로 4자리 코드(`0100`~`6340`, 263개 분기)로 조합한 뒤, `laneresource.a.b(String)`에서 `LaneDirection.create(shape, isRecommended)`(`UTURN_LEFT(10)`, `NORMAL_LEFT(5)`, `SLIGHT_LEFT(3)`, `STRAIGHT(2)`, `SLIGHT_RIGHT(4)`, `NORMAL_RIGHT(6)`)로 바꿔 `new Lane.Builder().addDirection(...).build()`를 `Step.Builder.addLane(...)`과 `setLanesImage(...)`에 함께 넣습니다(복합 차선도 차선당 대표 `LaneDirection` 1개만 추가).
- 하이패스 차선(`showHiPassLane == true`): 일반 차로는 `"0800"`(`STRAIGHT(2), false`), 하이패스 차로는 `"0808"`(`STRAIGHT(2), true`)로 만들어 `addLane(...)`에 추가합니다.

## CarPlay

iOS 앱은 `CPNavigationSession`, `CPManeuver`, `CPTravelEstimates`, `CPLane` 계층을 사용합니다. 앱 바이너리에는 iOS의 iAP2 직렬화 구현이 포함되지 않으므로 setter 값과 V039 iAP2 wire 숫자가 같다고 가정하지 않습니다.

### 카카오내비

`KNUCarPlaySDK.framework`의 converter(`0x18e3b0`)에서 `setManeuverType:`, `setJunctionExitAngle:`, `setJunctionType:`, junction image, instruction/dashboard/road-following variants를 실제로 설정합니다. `CPLane` angles·highlighted angle·preferred를 만들고 `setLanes:`, `addLaneGuidances:`, `setCurrentLaneGuidance:`에 전달하며, travel estimate도 갱신합니다.

내부 raw `1..85`를 `CPManeuverType`(`0x18ef5c`, 테이블 `0x19fdb8`)과 심볼 아이콘 번호(`0x18ee08`, 테이블 `0x19fb10`)로 바꾸는 입력값은 Android `NPRgCode`(`com.kakaomobility.navi.drive.sdk.domain.model.type.NPRgCode`) 및 `KNRGCode`의 실외 85개 enum 선언 순서(`1: Start(100)` ~ `85: RightUnderPathSide(94)`)와 1:1로 일치합니다(이 외 값은 `0: Unknown(-1)`).

| `CPManeuverType` | 카카오 내부 enum (`w0 = 1..85`, 괄호는 Android raw 코드) |
|---|---|
| `StartRoute(11)` | `1: Start(100)` |
| `ArriveAtDestinationLeft(10)` / `ArriveAtDestination(12)` | `2: Goal(101)` / `3: Via(1000)` |
| `StraightAhead(3)` | `4: Straight(0)`, `16: OverPath(14)`, `17: UnderPath(15)`, `31: Direction12(29)`, `55: Tunnel(64)`, **`75: Tollgate(84)`**, **`76: NonstopTollgate(85)`**, `77: JoinAfterBranch(86)` |
| `LeftTurn(1)` / `RightTurn(2)` | `5: LeftTurn(1)`, `28: Direction9(26)`, `54: UnprotectedLeftTurn(63)` / `6: RightTurn(2)`, `22: Direction3(20)` |
| `UTurn(4)` | `7: UTurn(3)`, `25: Direction6(23)` |
| `SlightLeftTurn(49)` | `8: LeftDirection(5)`, `29..30: Direction10..11(27..28)`, `57: LeftTunnel(66)`, `73: LeftStraight(82)`, `78..79: LeftOverPath/Side(87..88)`, `82..83: LeftUnderPath/Side(91..92)` |
| `SlightRightTurn(50)` | `9: RightDirection(6)`, `18..19: OverPathSide/UnderPathSide(16..17)`, `20..21: Direction1..2(18..19)`, `56: TunnelSide(65)`, `59..60: RightTunnel/Side(68..69)`, `74: RightStraight(83)`, `80..81: RightOverPath/Side(89..90)`, `84..85: RightUnderPath/Side(93..94)` |
| `SharpLeftTurn(47)` / `SharpRightTurn(48)` | `26..27: Direction7..8(24..25)` / `23..24: Direction4..5(21..22)` |
| `OffRamp(8)` / `OnRamp(9)` | `10: OutHighway(7)`, `44: OutCityway(42)` / `13..15: InHighway·LeftInHighway·RightInHighway(10..12)`, `47..49: InCityway·LeftInCityway·RightInCityway(45..47)` |
| `HighwayOffRampLeft/Right(22/23)` | `11: LeftOutHighway(8)`, `45: LeftOutCityway(43)` / `12: RightOutHighway(9)`, `46: RightOutCityway(44)` |
| `ChangeHighwayLeft/Right(52/53)` | `50: ChangeLeftHighway(48)` / `51: ChangeRightHighway(49)` |
| `EnterFerry(15)` / `ExitFerry(16)` | `52: InFerry(61)` / `53: OutFerry(62)` |
| `EnterRoundabout(6)` | `32..43: RotaryDirection1..12(30..41)`, `61..72: RoundaboutDirection1..12(70..81)` |
| `nil` (`setManeuverType:` 미호출) | `58: LeftTunnelSide(67)` (`0x1a0060` nil 플래그 `1`) |

- `setJunctionType:`(`0x18e478`, 헬퍼 `0x18e6f8`): `w0`가 `61..72`(`RoundaboutDirection1..12`, `(w0 - 61) < 12`)일 때만 `1`(`CPJunctionTypeRoundabout`)을 설정하며, `32..43`(`RotaryDirection1..12`)을 포함한 나머지 값은 `0`(`CPJunctionTypeIntersection`)입니다.
- `setJunctionExitAngle:`(`0x18e450`, 헬퍼 `0x18e4b4`): 변환된 `maneuverType`이 `6..7`(`Enter/ExitRoundabout`) 또는 `18..19`일 때 모델의 정수 각도 프로퍼티(`[x21, #0x18]`)를 `NSMeasurement<NSUnitAngle>`(degrees)로 감싸 전달합니다.
- `75: Tollgate(84)`와 `76: NonstopTollgate(85)`는 아이콘 테이블(`0x19fb10`)에서만 각각 `48`, `49`(`knu_rg_code_48/49`) 그림을 쓰며, 구조화 `CPManeuverType`은 둘 다 `StraightAhead(3)`으로 합쳐집니다. TG·IC·JC 전용 structured setter는 없습니다.

### 네이버지도

`CarNavigationUI` 프레임워크의 maneuver 빌더(`0x65314`)와 보조 리스트 maneuver 빌더(`0x7bc00`)에서 GOT 슬롯(`0x82c440..0x82c748`)에 연결된 `NMapsNaviModel.TurnPointType` enum 생성자를 역추적해 `CPManeuverType`, `CPJunctionType`, `junctionExitAngle` 변환 규칙 전체를 확정했습니다.

| `CPManeuverType` (`0x663ac`) | 네이버 `NMapsNaviModel.TurnPointType` |
|---|---|
| `NoTurn(0)` | `undefined`, `direction1·3·4·8·9·11`, 모든 `rotary*`(`rotaryStraight`, `rotaryUTurn`, `rotaryDirection1..12`), 모든 `roundabout*`(`roundaboutStraight`, `roundaboutUTurn`, `roundaboutDirection1..12`), `straightAtTurnPoint`, `laneChangeStraight·Left·Right` |
| `LeftTurn(1)` / `RightTurn(2)` | `left`, `unsafeLeft` / `right`, `pTurn` |
| `StraightAhead(3)` | `straight`, `accessTunnelHighway/Normal`, `accessBridgeHighway`, `accessBirdgeNormal`, `access/exitHighwayStraight`, `access/exitCityRoadStraight`, `accessOverpass/UnderpassStraight`, `access/exitCarOnlyStraight`, `divideAndJoin`, `rest`, `drowsinessShelter`, **`tollgate`, `hipassTollgate`, `oneTollingTollgate`** |
| `UTurn(4)` / `ContinueOnRoad(5)` | `uTurn` / `accessDivideStraight` |
| `ArriveAtDestination(12)` | `via`, `goal` |
| `KeepLeft(13)` | `leftDirection`, `accessLeft`, `accessDivideLeft`, `sideOverpassLeft`, `accessUnderpassLeft`, `sideUnderpassLeft`, `joinLeft` |
| `KeepRight(14)` | `rightDirection`, `accessRight`, `accessDivideRight`, `accessOverpassRight`, `sideOverpassRight`, `accessUnderpassRight`, `sideUnderpassRight`, `joinRight` |
| `EnterFerry(15)` / `ExitFerry(16)` | `accessFerry` / `exitFerry` |
| `HighwayOffRampLeft(22)` | `exitHighwayLeft`, `exitCityRoadLeft`, `exitCarOnlyLeft` |
| `HighwayOffRampRight(23)` | `accessRest`, `exitHighwayRight`, `exitCityRoadRight`, `exitCarOnlyRight` |
| `SlightLeftTurn(49)` | `accessOverpassLeft` |
| `ChangeHighwayLeft/Right(52/53)` | `accessHighwayLeft`, `accessCityRoadLeft`, `accessCarOnlyLeft` / `accessHighwayRight`, `accessCityRoadRight`, `accessCarOnlyRight` |

- `setTrafficSide:`(`0x65380`): 항상 `0`(`CPTrafficSideRight`)을 설정합니다.
- `setJunctionType:`(`0x653b4..0x65a9c`): 28개 로터리·회전교차로 케이스(`rotaryStraight`, `rotaryUTurn`, `rotaryDirection1..12`, `roundaboutStraight`, `roundaboutUTurn`, `roundaboutDirection1..12`)일 때만 `1`(`CPJunctionTypeRoundabout`)을 설정하고, 나머지 모든 케이스는 `0`(`CPJunctionTypeIntersection`)입니다.
- `setJunctionExitAngle:`(`0x65aa8` -> `0x65b78..0x663a8`): 별도 동적 도로 각도 필드가 아니라 `TurnPointType` 정적 분기(`0x65b78`)로 각도를 만들어 `NSMeasurement<NSUnitAngle>`(degrees)을 설정합니다.
  - 시계방향 교차로(`direction*`): `direction8` `-120°`, `direction9` `-90°`, `direction11` `-45°`, `direction1` `+45°`, `direction3` `+90°`, `direction4` `+120°`
  - 로터리·회전교차로(`rotary*` / `roundabout*` 동일): `Straight·Direction12` `0°`, `Direction1` `+30°`, `Direction2` `+60°`, `Direction3` `+90°`, `Direction4` `+120°`, `Direction5` `+150°`, `Direction6·UTurn` `+180°`, `Direction7` `-150°`, `Direction8` `-120°`, `Direction9` `-90°`, `Direction10` `-60°`, `Direction11` `-30°`
  - 그 밖의 `TurnPointType`은 `nil`(`0x0`)을 전달합니다.
- 고속도로 요약/보조 리스트용 빌더(`0x7bc00`)는 iOS 17.4 이상에서 `trafficSide = 0`, `maneuverType = 3`(`StraightAhead`), `junctionType = 0`(`Intersection`)을 고정 설정합니다. `tollgate`·`hipassTollgate`·`oneTollingTollgate`·`rest`·`drowsinessShelter` 모두 `StraightAhead(3)`(`accessRest`만 `HighwayOffRampRight(23)`)으로 축약되며 IC·JC·TG 전용 structured setter는 없습니다.

### 티맵

stripped Mach-O(`T map`)의 `__objc_stubs`와 `__swift5_fieldmd`(`0x1042cd7bc`, 143개 TBT enum 케이스 `0..142`)를 역추적해 실제 CarPlay setter 호출부(`0x100d5d68c` 및 `0x100d5e834`, 모두 `#available(iOS 17.4, *)` 가드 내부)와 변환표를 복원했습니다.

| `CPManeuverType` (`0x1000f5cb0`, 테이블 `0x103a14744`) | 티맵 iOS 내부 TBT enum (`0..142`) |
|---|---|
| `NoTurn(0)` (`nil` 반환 시 기본값 `0` 포함) | `turnPtMap(0)`, `strighit0(1)`, `turnPtTile(3)`, `hipassLeft/Right/Center(49..51)`, `dir1..dir12(73..84)`, `facility(89)` 등 그 밖의 케이스 |
| `LeftTurn(1)` / `RightTurn(2)` | `left(5)`, `leftSide(8)`, `left8(9)`, `left9(10)` / `right(6)`, `rightSide(12)`, `right2(13)`, `right3(14)` |
| `StraightAhead(3)` | `straight(4)`, `dir12(84)`, **`sa(85)`, `saIn(86)`, `tolExp(87)`, `tolNormal(88)`**, `startDir1..12(92..103)`, `dest(106)`, `underIn(123)`, `overOut(124)`, `tunnelIn(126)`, `driveWayIn(127)`, **`tollgate(140)`**, `end(141)` |
| `UTurn(4)` | `uTurn(7)` |
| `OnRamp(9)` | `icIn(109)`, `jcIn(112)`, `overIn(121)`, `SkyWayIn(129)` |
| `OffRamp(10)` | `icOut(115)`, `jcOut(118)` |
| `ArriveAtDestination(12)` | `via1..5(104, 136..139)` |
| `KeepLeft(13)` | `leftIn(21)`, `leftOut(22)`, `dir10..11(82..83)`, `icInLeft(110)`, `jcInLeft(113)`, `underInLeft(122)`, `skyWayInLeft(130)`, `left1(134)` |
| `KeepRight(14)` | `rightIn(23)`, `rightOut(24)`, `dir1..2(73..74)`, `icInRight(111)`, `jcInRight(114)`, `overInRight(120)`, `skyWayInRight(128)`, `right1(135)` |
| `HighwayOffRampLeft/Right(22/23)` | `icOutLeft(116)`, `jcOutLeft(119)` / `icOutRight(117)`, `jcOutRight(120)` |
| `SharpLeftTurn/RightTurn(47/48)` | `left10(11)` / `right4(15)` |
| `SlightLeftTurn/RightTurn(49/50)` | `left11(25)` / `right1(16)` |

- `setJunctionType:`·`setJunctionElementAngles:`·`setJunctionExitAngle:`(`0x100d5d6e8..0x100d5e830`):
  - enum 케이스가 `73..84`(`dir1..dir12`, `(tag - 0x49) < 0xc`)일 때만 `setJunctionType: 1`(`CPJunctionTypeRoundabout`)을 호출하고, `setJunctionElementAngles:`와 `setJunctionExitAngle:`(`dir1·2` `+45°`, `dir3` `+90°`, `dir4·5` `+135°`, `dir6` `+180°`, `dir7·8` `-135°`, `dir9` `-90°`, `dir10·11` `-45°`, `dir12` `0°`)을 설정합니다.
  - 그 밖의 모든 케이스는 각도 없이 `setJunctionType: 0`(`CPJunctionTypeIntersection`)만 호출하고 `setTrafficSide: 0`(`CPTrafficSideRight`, `0x100d5e7ec`)을 설정합니다.
- 구조화 차선 `CPLane`(`0x100d5e834` 및 각도 헬퍼 `0x100d5ee48`, iOS 17.4 이상):
  - 차선 방향 문자 `'1'..'6'`(`0x31..0x36`)을 `NSMeasurement<NSUnitAngle>`(degrees)로 변환합니다(`'1'` `-180°`, `'2'` `-90°`, `'3'` `-45°`, `'4'` `0°`, `'5'` `+45°`, `'6'` `+90°`).
  - 추천 여부에 따라 `setStatus:`(`1` = `Good`, `2` = `Preferred`), `setPrimaryAngle:`, `setSecondaryAngles:`를 채운 `CPLane` 배열을 `setLanes:`(`0x100d5bd7c`), `addLaneGuidances:`(`0x100d5dd00`), `setCurrentLaneGuidance:`(`0x100d5ddf4` / `0x100d5fd04`), `setLinkedLaneGuidance:`(`0x100d5dac0`)로 전달합니다.
- 휴게소(`sa(85)`, `saIn(86)`)와 톨게이트(`tolExp(87)`, `tolNormal(88)`, `tollgate(140)`)는 모두 `StraightAhead(3)` + `CPJunctionTypeIntersection(0)`으로 들어가며, 하이패스(`hipassLeft/Right/Center(49..51)`)는 `NoTurn(0)`으로 들어갑니다.

## 차량 구현 기준과 검증 경계

- **Apple `CPManeuverType` (`0..53`)과 V039 `Iap2Const$ManeuverType` (`0..53`)의 1:1 일치 및 iOS 직렬화 경계**:
  - iOS 17.4 `CarPlay.framework`의 공개 `CPManeuverType`(`0=NoTurn` ~ `53=ChangeHighwayRight`), `CPJunctionType`(`0=Intersection`, `1=Roundabout`), `CPTrafficSide`(`0=Right`, `1=Left`), `CPLaneStatus`(`0=NotGood`, `1=Good`, `2=Preferred`) 번호 정의는 V039 `com.tcc.iap2.Iap2Const$ManeuverType`(`0x0..0x35`) 및 `Iap2Const$JunctionType`(`0..1`)과 숫자까지 1:1로 동일합니다.
  - 다만 V039 `HKMC_DiPO.odex`(`com.daudio.app.dipo.e.u`, `ClusterIcon.java`)는 단순 회전(`LeftTurn(1)`, `RightTurn(2)`, `SharpLeft/Right(47/48)`, `SlightLeft/Right(49/50)`)에서도 `mJunctionElementExitAngle`(`-90°`, `+90°`, `-45°`, `+45°`, `-135°..-150°`, `+135°..+150°`)이 함께 일치해야 회전 아이콘(`0x42..0x47`)을 내보내고, 회전교차로도 `RoundaboutExit1..19`(`28..46`) 또는 `UTurnAtRoundabout(19)` 조합을 요구하며 `KeepLeft/Right(13/14)`나 `ChangeHighway*(51..53)` 분기는 갖지 않습니다. 따라서 앱이 `junctionExitAngle = nil`로 넘긴 일반 회전이나 `EnterRoundabout(6)`/`NoTurn(0)` + `junctionType=1`을 iOS `CarPlay` 데몬이 iAP2 `0x5202` 패킷으로 직렬화할 때 기본 각도·출구 타입을 합성해 주는지 여부는 iOS 내부 동작 및 실차 iAP2 캡처로만 확정됩니다.
- **Android Auto 호스트(`NavigationNextTurnEvent`)와 V039 `HKMC_GPM.odex`의 경계**:
  - V039 `HKMC_GPM.odex`의 `GalReceiver`는 네이티브 `libautoreceiver_infobank.so`를 로드하고 GAL 채널 `NAVIGATION_STATUS_SERVICE_ID = 0x9`에서 `0x8001`(`START`), `0x8002`(`STOP`), `0x8003`(`NAVIGATION_STATUS`), `0x8004`(`NAVIGATION_TURN_EVENT`), `0x8005`(`NAVIGATION_DISTANCE_EVENT`)만 처리합니다(`Protos$NavigationStatusMessageId`). C++ 네이티브 계층이 `0x8004` protobuf를 파싱해 `NavigationStatus.navigationNextTurnCallback(String road, int turnSide, int event, byte[] image, int turnNumber, int turnAngle)`을 호출하면, `GalConnectionSession$4.onNextTurn`이 `byte[] image`를 버리고 `GpmNaviTBTManager.onNextTurn(String road, int turnSide, int event, int turnNumber, int turnAngle)`으로 전달합니다.
  - `GpmNaviTBTManager`가 수신하는 Google 프로토콜 enum(`Protos$NavigationNextTurnEvent$NextTurnEnum` `0..19` + `TurnSide` `1..3`)은 AndroidX `Maneuver`(`TYPE_*` `0..50`)의 회전 종류와 좌·우 방향을 분리한 형태입니다. 특히 `NextTurnEnum`에는 `ON_RAMP(7)`와 `OFF_RAMP(8)`가 각각 하나씩만 존재하므로, AndroidX에서 `ON/OFF_RAMP_SLIGHT`(`13/14`, `21/22`)를 쓰든 `ON/OFF_RAMP_NORMAL`(`15/16`, `23/24`)을 쓰든 `GpmNaviTBTManager.setRampDisplayType`에서는 동일하게 좌·우 진입(`0xa2`/`0xa1`)·진출(`0xa5`/`0xa4`) 아이콘으로 수렴합니다. 또한 `NAME_CHANGE(2)`(`TurnSide=UNSPECIFIED`)와 `MERGE(10)`는 `GpmNaviTBTManager.setTurnDisplayType`에서 직진(`0x41` `IC_STRAIGHT`)으로 수렴합니다.
  - 순정 V039 `HKMC_GPM.odex`는 `0x8006`(`INSTRUMENT_CLUSTER_NAVIGATION_STATE`, 구조화 `NavigationStep`·`NavigationLane` 포함) 메시지 정의와 `NavigationCluster.updateLaneInfo(...)` 호출 자체가 없습니다. 즉 세 앱이 Android Auto `Step.Builder.addLane(...)`에 넣는 구조화 `Lane`은 순정 `HKMC_GPM`만으로는 계기판/HUD 차선(`LaneFrame`)에 도달하지 않으며, 헤드유닛 `libautoreceiver_infobank.so`의 채널 `0x9` 네이티브 후킹으로 `0x8006`을 추출해 `gen5wkr.aa.tbt` 소켓(`LANE:`)으로 넘겨야 표시할 수 있습니다.
- **TG · 휴게소 · 졸음쉼터 · 하이패스 요약 및 헤드유닛 텍스트 보강**:
  - 세 앱 모두 TG·하이패스·휴게소·졸음쉼터를 Android Auto 1차 Step에서는 `STRAIGHT(36)`(티맵·카카오) 또는 `NAME_CHANGE(2)`(네이버, `GpmNaviTBTManager`에서 `0x41` 직진으로 변환)로, CarPlay에서는 `StraightAhead(3)` 또는 `NoTurn(0)`으로 축약합니다. 유일한 예외는 **네이버 CarPlay의 `accessRest`(휴게소 진입)**로, `HighwayOffRampRight(23)`을 설정해 V039에서 우측 진출 램프(`0xa4` `IC_EXIT_R`)로 매핑됩니다.
  - 하이패스 차선은 **티맵 Android Auto**(`showHiPassLane`: `"0808"` -> `STRAIGHT(2), true`)와 **카카오 Android Auto**(`HipassProvider`: `first > 0` -> `STRAIGHT(2), true`, 현금 차로 -> `UNKNOWN(1), false`)가 1차 Step의 구조화 `Lane` 추천 차선 및 비트맵(`setLanesImage`)으로 넣습니다.
  - 헤드유닛 단독 환경에서 TG(`0xb2` `TOLL`)와 휴게소·졸음쉼터(`0xb7` `REST_AREA`) 아이콘을 표시하기 위해, `ClusterIcon.of(Maneuver)`와 `ClusterIcon.refineManeuver(int baseIcon, String road, String desc)`는 **비방향성 직진(`0x41`, `0xac`) 또는 CarPlay `NoTurn(0)`일 때에 한해** `afterRoad`/`road`/`desc`의 톨게이트(`"톨게이트"`, `"요금소"`, `"하이패스"`, `"원톨링"`, `"통행료"`, `"요금:"`, `"TG"` 토큰)·휴게소(`"휴게소"`, `"졸음쉼터"`) 키워드를 검사하여 `0xb2`·`0xb7`로 승격합니다(좌·우 회전 및 진출입 램프 아이콘은 절대 덮어쓰지 않음).
- 헤드유닛 단독 개발 방향과 `HKMC_GPM` 네이티브/DEX 후킹 설계는 [hud-development-direction.md](hud-development-direction.md)에 정리되어 있습니다.
