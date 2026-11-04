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
| `ON_RAMP_SLIGHT_LEFT/RIGHT(15/16)` | 좌·우 고속도로/도시고속도로 진입 및 차로 변경 |
| `OFF_RAMP_SLIGHT_LEFT/RIGHT(23/24)` | 좌·우 고속도로/도시고속도로 진출 |
| `FORK_LEFT/RIGHT(25/26)` | 방향 분기, 고가·지하·터널 진입/측도 |
| `ROUNDABOUT_CCW_WITH_ANGLE(35)` | Rotary 30~41, Roundabout 70~81 |
| `DEPART/DESTINATION/FERRY(1/39/37)` | Start / Goal·Via / In·OutFerry |

회전교차로 suffix 1~12는 각각 150°, 120°, 90°, 60°, 30°, 360°, 330°, 300°, 270°, 240°, 210°, 180°로 변환됩니다. 차선은 구조화된 `Lane` 목록과 bitmap을 함께 Step에 넣습니다.

SA·TG·IC·JC·RA는 별도 사용자 정의 그림과 안내문으로 구성되지만 구조화된 시설 type으로 전달되지는 않습니다. 특히 Tollgate와 NonstopTollgate는 `STRAIGHT(36)`으로 합쳐집니다. 차량이 시설명이나 그림을 보고 TG 의미를 새로 만들 근거가 없습니다.

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

TG·IC·JC·휴게소는 전용 AndroidX 시설 필드가 아니라 `NAME_CHANGE`, ramp, merge, fork, Step 문자열 또는 CarIcon으로 축약됩니다. 이 입력만으로 V039의 TG·휴게소 전용 아이콘을 선택하지 않습니다.

### 티맵

`base.apk/classes30.dex`의 실제 TBT observer가 `TBTInfo.nTBTTurnType`을 `com.skt.tmap.car.y.c`로 변환해 `Maneuver.Builder`에 넣고, Step/Trip을 만든 뒤 AndroidX `NavigationManager`의 Binder `updateTrip`까지 호출합니다.

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

티맵 전용 Lane/HiPass bitmap 모델은 확인했지만 AndroidX `Lane`을 만들어 Step에 넣는 앱 호출은 찾지 못했습니다. 따라서 티맵 Android Auto의 구조화 차선 지원을 확정하지 않습니다.

## CarPlay

iOS 앱은 `CPNavigationSession`, `CPManeuver`, `CPTravelEstimates`, `CPLane` 계층을 사용합니다. 앱 바이너리에는 iOS의 iAP2 직렬화 구현이 포함되지 않으므로 setter 값과 V039 iAP2 wire 숫자가 같다고 가정하지 않습니다.

### 카카오내비

`KNUCarPlaySDK.framework`의 converter에서 `setManeuverType:`, `setJunctionExitAngle:`, `setJunctionType:`, junction image, instruction/dashboard/road-following variants를 실제로 설정합니다. `CPLane` angles·highlighted angle·preferred를 만들고 `setLanes:`, `addLaneGuidances:`, `setCurrentLaneGuidance:`에 전달하며, travel estimate도 갱신합니다.

내부 raw 1~85에서 Apple maneuver type으로 바꾸는 표는 추출했지만 바이너리에 내부 enum 이름이 남지 않아 숫자에 시설 이름을 붙이지 않습니다. junction type은 다른 내부 raw 값 61~72 여부에서 만든 bool이고, junction image는 별도 속성입니다. TG·IC·JC 전용 structured setter는 확인되지 않았습니다.

### 네이버지도

`CarNavigationUI` 실행 코드에서 `setJunctionType:`, `setJunctionExitAngle:`, `setUpcomingManeuvers:`, `addLaneGuidances:`, `setCurrentLaneGuidance:`, `setLinkedLaneGuidance:`, maneuver/trip travel estimate 갱신 호출을 확인했습니다. 내부 모델에는 turnPoints, lane, overlayLane, junction, roadName, junction info/image가 있습니다.

정확한 Naver TurnPointType에서 `CPJunctionType` raw 값으로 가는 case와 angle 원본 속성은 stripped Swift 코드에서 확정하지 못했습니다. IC·JC·TG 전용 structured setter도 찾지 못했습니다.

### 티맵

Mach-O의 ObjC 메타데이터에서 `CarPlayNavigationManager`, `CPManeuver`, lane/junction 모델과 `setJunctionType:`, `setJunctionExitAngle:`, `setJunctionElementAngles:`, `setDistance:`, `addLaneGuidances:`, `addManeuvers:` selector가 확인됩니다. 그러나 stripped·동적 dispatch 코드에서 이 setter의 실제 caller와 raw 입력 대입을 복원하지 못했습니다. API 이름의 존재만으로 티맵의 실제 CarPlay 전송값을 확정하지 않습니다.

## 차량 구현 기준과 검증 경계

- CarPlay는 V039 `HKMC_DiPO.odex`에서 확인한 iAP2 type·driving side·junction type·exit angle의 정확한 조합만 클러스터 아이콘으로 바꿉니다.
- Android Auto의 기본 경로는 V039 `HKMC_GPM.odex`의 NavigationStatus 변환을 그대로 사용합니다. 선택적 보조 입력도 송신자가 준 클러스터 아이콘을 보존하며 도로명으로 시설 의미를 만들지 않습니다.
- 일반 회전·명시적 램프·회전교차로·거리 경로는 정적으로 확인했습니다. 네이버와 카카오는 Android 구조화 차선, 카카오는 iOS 구조화 차선도 확인했습니다. 티맵 차선은 미확정입니다.
- TG·IC·JC·휴게소의 사용자 정의 그림이나 문구가 V039의 전용 HUD 의미까지 유지된다는 증거는 세 앱 모두 없습니다. 명시적 ramp/fork/merge는 해당 일반 회전 아이콘으로 표시하고, 시설명만 있는 경우 추정하지 않습니다.
- V039가 허용하는 TG·휴게소 아이콘은 보조 송신자가 검증된 클러스터 아이콘을 명시적으로 제공할 때 그대로 통과할 수 있지만, 앱 텍스트에서 생성하지 않습니다.
- Android Auto 호스트와 iOS의 비공개 직렬화, iAP2 wire 값, 실제 계기판/HUD 출력은 장기 로그와 실차 검증 대상으로 남습니다.
