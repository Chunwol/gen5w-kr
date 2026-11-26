# HUD 길안내

`core`는 CarPlay RouteGuidance의 회전·거리·차선 정보를 순정 `NavigationCluster`에 전달합니다. Android Auto는 순정 `HKMC_GPM`의 Google NavigationStatus 경로를 사용합니다. 자체 CAN 전송은 하지 않습니다.

## CarPlay 입력과 상태

- `GuidanceParser`는 V039 `com.tcc.iap2`의 알림 `0x78`(상태), `0x79`(회전), `0x7a`(차선)를 파싱합니다.
- `GuidanceSession`은 현재 회전 목록과 현재 차선 안내 index를 따로 관리합니다. 지도·component 변경, 재탐색, 도착, 연결 종료 때 이전 회전·거리·차선을 지웁니다.
- 부분 갱신은 기존 필드를 유지합니다. 필드가 누락됐다고 각도나 방향을 0으로 만들지 않습니다.
- 순정 내비가 안내 중이거나 상태를 확인할 수 없으면 CarPlay 출력을 보류합니다. 순정 안내가 끝나면 최신 CarPlay 상태를 다시 보냅니다.

## V039 회전 아이콘

`ClusterIcon`은 V039 `HKMC_DiPO.odex`의 `RouteGuidanceAnalyzer` 분기를 그대로 옮겼습니다. 입력은 `ManeuverType`, `DrivingSide`, `JunctionType`, `JunctionExitAngle` 네 구조화 필드뿐입니다. 도로명·설명·앱 이름으로 아이콘을 바꾸지 않습니다.

확인된 주요 대응은 다음과 같습니다.

| 입력 | 클러스터 아이콘 |
|---|---:|
| 직진 | `41` |
| 일반 좌·우회전 | `46` / `43` |
| 완만한 좌·우회전 | `47` / `42` |
| 급한 좌·우회전 | `45` / `44` |
| 우측통행 U턴 | `48` |
| 계속 주행 | `AC` |
| 진입 램프 | `A0` |
| 좌·우 진출 램프 | `A5` / `A4` |
| 고속도로 변경 좌·우 | `AE` / `AD` |

회전교차로는 순정이 실제 처리하는 타입과 정확한 각도 조합만 표시합니다. 일반 `OffRamp(8)`, 일반 회전교차로 진입·나가기(6·7), 출구 번호만 있고 순정 각도 조합이 없는 타입, `ChangeHighway(51)` 등 순정 DiPO가 보내지 않는 조합은 비웁니다. 모든 타입에 임의의 화살표를 만드는 대체 규칙은 없습니다.

IC·JC 글자는 경로 의미를 증명하지 못하므로 방향이나 진출입을 만들지 않습니다. 요금소·휴게소·졸음쉼터는 방향이 없는 직진(`41`·`AC`, CarPlay `NoTurn`)일 때에 한해, 시설명 문구에서 `B2`(요금소)·`B7`(휴게소)로 바꿉니다. 고가차도(`57`/`58` 진입, `51`/`52` 옆길)·지하차도/터널(`5A`/`5B` 진입, `54`/`55` 옆길)과 비보호 좌회전(`4C`, 일반 좌회전 `46`에 `"비보호 좌회전"`/`"비보호좌회전"` 포함 시)은 3사 앱이 보내는 해당 방향·문구 조합에서 V039 순정 `libExSLNavi.so` 확인 코드로 치환하고, 고가·지하차도·터널은 `LaneFrame` 차선 강조 마스크(`0x43..0x46`)도 함께 채웁니다. 일반 `90°` 좌우 회전·급회전(비보호 좌회전 제외)과 교차로명(`삼거리`/`사거리`/`오거리`/`네거리`/`교차로`/`로터리`)은 오탐 방지를 위해 고가·지하차도·터널로 치환하지 않습니다.

또한 터널(`"터널"`/`"tunnel"`, 교차로명·옆길 제외) 안내가 `1000m` 이내이거나 터널 진입 직후 `STATE_LOCATING` 유지 중일 때는 순정 `NavigationCluster.updateSTD_NAVI_PE_00_Info`(`PE_00` / `TunnelExist`) 보조 신호를 함께 보내 공조 내기순환 및 ADASIS 보조 동작을 돕고, 터널을 벗어나거나 안내 종료·연결 해제 시 해제(`0`)를 한 번 요청합니다. 폰 안내가 터널을 보낸 적이 없는 평상시에는 Core가 `PE_00`을 쓰지 않아 순정 내비의 배경 지도 기반 `PE_00`·`ISLW` 출력을 방해하지 않습니다. 이 문구 기반 치환과 `PE_00` 실차 공조 연동은 실차 검증 완료 전까지 현장 검증 예정 상태로 둡니다.

`PE_00` uses one phone owner (CarPlay route, otherwise AA), 50 m distance buckets, and a clear after a phone assertion. Successful packets are not periodically repeated. Stock parking/HVAC packets pass through the Navi adapter even during a phone lease; warning-free stock tunnel packets are suppressed during that lease. This deliberately lets genuine stock auxiliary information replace a phone tunnel rather than fighting it on a timer. A subsequent phone tunnel change/clear still writes a complete packet with zero auxiliary fields; preserving auxiliary fields across both processes is not established by this change and needs vehicle observation. No claim of verified HVAC behavior is made.

각도 필드가 없는 좌·우회전과 급·완만 회전, `KeepLeft/Right`는 타입이 방향을 말하므로 기본 아이콘(`46`/`43`, `45`/`44`, `47`/`42`)을 씁니다. 네이버 CarPlay가 `NoTurn(0) + Intersection(0)`과 시계방향 각도(`±45°`/`±90°`/`±120°`)로 보내는 교차로 회전도 같은 좌·우회전 아이콘(`42..47`)으로 표시합니다. 방향을 모르는 일반 `OffRamp(8)`는 방향을 주장하지 않는 가운데 진출(`A3`)로, `ArriveEndOfNavigation(10)`은 목적지 도착(`70`)으로 표시합니다. 회전교차로(`junctionType=1`과 `NoTurn(0)`·`EnterRoundabout(6)`·티맵 방향 타입 `1/2/3/19/47..50`, 또는 카카오 로터리 `EnterRoundabout(6) + junctionType=0 + 비영(非零) 각도`)는 순정 `45°` 간격과 3사 앱의 `30°`/`45°` 간격(`0°`/`360°`→`61`, `30°..90°`→`63`, `120°..150°`→`64`, `±180°`→`66`, `-90°`/`270°`→`69`, 좌측 대각선→`68`)을 해당 방향 아이콘으로 표시하고, 각도가 없거나 표에 없으면 비웁니다. 삼거리·사거리 등 교차로 이름은 요금소·휴게소로 바꾸지 않습니다.

## 거리와 다음 회전

상태 필드 10의 다음 회전 거리를 사용합니다. V039 `HKMC_Navi_ExSL` / `ClusterService`와 동일하게 1,000m 미만은 미터(`scale=0`, `distanceErr=-2` 소수점 미표시, `updateTBTSubInfo2C` 단위 `1`/소수 `15`), 그 이상은 km float(`scale=1`, `distanceErr=0`, `updateTBTSubInfo2C` 단위 `2`/소수 1자리)로 전달하고, 비울 때는 `updateTBTSubInfo2C(15, 15, 65535, ...)`를 보냅니다. 다음 회전이 멀리 있어도(3km 초과) 실제 회전·분기 아이콘과 거리를 그대로 표시합니다(사용자 요청으로 순정의 "3km 밖은 직진" 규칙을 쓰지 않음). Remaining distance/arrival is restored after ownership invalidation, not every three seconds. The arrival clock is anchored when the duration arrives.

`updateTBTInfo`의 `sideStreet`와 `combiSideStreet`는 V039 순정 DiPO와 동일하게 `0`을 사용하고, 첫·둘째·셋째 아이콘은 `updateTPTurnListNew`(`0xF2`)에 담습니다. 회전 접근 막대 그래프(`barGraphLevel`)는 대기 시 `barGraphErr=-1`(15), `300m` 초과 시 `-2`(숨김), `300m` 이내에서는 거리에 반비례하는 진행률(`10..100`, `ClusterService`가 `/10` 반올림해 4비트 막대 `1..10`으로 보냄, 순정처럼 빈 막대 없음)을 전달합니다. 투영 코드 `0x40`("방향 없음")은 계기판 로딩 스피너를 그리므로 어느 경로로 들어와도 직진(`41`)으로 바꿉니다. `updateTBTSubInfo2C` 정수부는 보내기 전에 `65534.9km`로 포화시켜 큰 값에서도 넘침이 없습니다. 실제 계기판·HUD의 세부 표시는 실차 확인 항목입니다.

## 차선

`LaneFrame`은 확인한 순정 81바이트 F1 형식을 만듭니다. 최대 8개 차선, 차선당 최대 3개 방향을 담고 highlighted angle만 추천 차선으로 표시합니다. 중복 index, index 간격, 지원하지 않는 각도, 존재하지 않는 강조 방향, 4개 이상 방향은 전체 차선을 비웁니다.

방향 표는 두 순정 native 변환표를 대조한 결과입니다. iAP2 각도에서 F1까지 동일한 의미가 유지되는지는 실차에서 확인합니다. 고가·지하 마스크(`0x43..0x46`)는 고가차도(`57`/`58`, `51`/`52`)와 지하차도·터널(`5A`/`5B`, `54`/`55`) 아이콘이 선택되고 차선 안내가 활성일 때 함께 채워집니다.

## Android Auto

V039 `HKMC_GPM.odex`에서 `onNextTurn`, `onNextTurnDistance`, `setTurnDisplayType`, `setRampDisplayType`, `setRoundAboutDisplayType`와 `NavigationCluster.updateTBTInfo` 호출을 직접 확인했습니다. GPM은 Google NavigationStatus의 구조화된 회전 종류·방향·거리 단위를 순정 아이콘으로 변환합니다. `ROUNDABOUT_ENTER`와 `FERRY_TRAIN`은 순정 코드에서도 클러스터에 보내지 않습니다.

`gpm-patch-v039`는 V039 원본 해시가 맞을 때 route 기능 제한 분기만 변경합니다. `CoreService`의 선택적 보조 입력은 송신자가 이미 준 아이콘을 그대로 사용합니다. 아이콘이 없으면 `TYPE`, `DRIVING_SIDE`, `JUNCTION_TYPE`, `EXIT_ANGLE`이 모두 순정 조합을 이룰 때만 변환합니다. 도로명으로 TG·IC·방향을 재해석하지 않습니다.

AA 신형 경로(`0x8006`, AndroidX `Maneuver` 형식)는 V039 순정 `GpmNaviTBTManager`와 같은 결과가 되도록 맞춥니다. 좌·우 분기(`FORK_LEFT/RIGHT` 25/26)는 순정 분기 `AE`/`AD`(이전의 목적지 깃발 `72`/`71` 오매핑 수정)이고, 카카오·네이버·티맵이 고가·지하차도·터널 진입/옆길을 분기로 보내므로 도로명·안내문이 이를 증명하면 순정 고가·지하 아이콘(`57`/`58`, `51`/`52`, `5A`/`5B`, `54`/`55`)을 씁니다. 합류(27~29)는 순정처럼 직진 `41`, 목적지 좌·우(41/42)는 `72`/`71`, 페리(37)는 `B0`입니다. 회전교차로(32~35)는 AndroidX 각도(돈 각도: 반시계 회전교차로에서 180 직진·90 우·270 좌·360 U턴, 3사 앱 변환표와 순정 GPM 표가 일치)를 45° 단위로 순정 출구 아이콘 `60 61 63 64 66 68 69 6B`에 대응시키고(스피너를 그리는 `67`/`6A` 계열 미사용), 시계방향은 같은 출구에 `+0x60`입니다. 출구 정보가 없는 진입·나가기(30/31)는 직전 회전교차로 출구 아이콘을 다음 회전까지 유지하고, 그것도 없으면 직진입니다. AA에는 목적지 남은 거리·도착 시각·목적지명 입력이 없으며 순정 GPM도 보내지 않습니다.

보조 입력의 회전·차선 출력이 실패하면 1초마다 다시 보냅니다(CarPlay 안내 중에는 CarPlay가 우선이라 보내지 않음). 회전 정보가 120초 동안 갱신되지 않으면 종료 신호를 놓친 것으로 보고 계기판의 보조 안내를 지웁니다. 120초는 긴 신호 대기에서도 화살표가 지워지지 않게 정한 값이며, 차선 갱신도 갱신으로 칩니다. 현재 저장소에는 이 보조 입력을 보내는 구성요소가 없습니다.

## 출력과 검증 경계

출력은 `updateTBTInfo`, `updateTBTSubInfo`(목적지까지 남은 거리), `updateTPTurnListNew`, `updateTPCrossroadName`, `updateLaneInfo`를 사용합니다. 실패한 최신 회전·거리·차선과 지움 요청은 다시 시도합니다. 한 번도 입력받지 않은 세션이 임의 출력을 만들지는 않습니다.

### 목적지까지 남은 거리

CarPlay 상태 알림의 `DistanceRemaing`(id 7, 미터)을 `NavigationCluster.updateTBTSubInfo(거리, 오차, 단위, 시, 분, timeType, timeFormat, 방위, 방위오차)`로 전달합니다. 순정 내비(`com.mnsoft.navi.message.a.g`)의 0x4D 패킷 해석에서 확인한 규칙을 따릅니다: 단위 `0` m·`1` km, 시·분 `0xff`와 timeType `0`은 값 없음, 거리 오차 `-3`은 무효. 남은 시간(id 6)은 현재 시각에 더해 도착 예정 시각(시·분, 24시간제)으로 바꿔 같은 `updateTBTSubInfo`의 시·분에 담아 보냅니다. 도착 예정 시각 원값(id 5)은 진단용으로만 기록합니다. 재탐색·위치 확인 중에는 기존 경로 합계를 유지하고, 명시적 경로 종료·연결 종료에서 지웁니다.

남은 시간(`TimeRemaingToDestination`, id 6)은 초 단위로 읽어 현재 시각에 더한 도착 시각을 같은 `updateTBTSubInfo`의 시·분(timeType `1`, 24시간 형식 `2`)으로 전달합니다. 값이 없거나 음수이거나 99시간을 넘으면 시·분 `0xff`와 timeType `0`을 보냅니다. 같은 분 안에서는 다시 보내지 않습니다. 도착 예정 원시값(id 5)은 변환하지 않고 USB 로그에만 남깁니다(이벤트 33).

목적지 이름(`DestinationName`, id 4)은 순정 DiPO와 같이 type `0`과 이름만 담아 `updateTPFlexibleDestinationName`으로 전달하고, 경로 종료 때 빈 이름으로 지웁니다.

고속도로 전용 `updateTPHighwayMode` 경로는 앱 입력과 V039 실제 출력이 연결됐다는 증거가 없어 호출하지 않습니다. 순정 과속·카메라 경고는 별도 순정 채널이며 이 앱이 생성하지 않습니다. Android Auto 회전 정보가 갱신되면 순정 Google Projection(GPM)과 같은 "경고 없음" 트랩 패킷(`updateTBTTrapInfo`)을 회전 갱신마다 보내므로, 그 순간 순정 내비가 표시 중이던 경고는 지워질 수 있습니다(순정 내비 안내 중에는 보내지 않습니다).

JVM 검사는 파싱·상태·V039 분기표·프레임 변환을 검증하고 APK 빌드는 Android 4.4 호환 코드를 확인합니다. 네이버지도·티맵·카카오내비의 Android/iPhone 실차 표시 성공, 순정 경고와의 동시 표출, 차선의 물리적 좌우 순서, 고속도로 전용 화면은 [실차 검증](validation.md)이 끝나기 전까지 지원 확정으로 표시하지 않습니다.

## 2026-11-26 stock-source audit (source edits only)

Evidence below is relative to a private decompile of the V039 stock apps (`hud-v039/j/`, not published).
These are Java caller/packet semantics, not a time-aligned reproduction of the reported vehicle flicker.

| Item | Stock evidence | Decision |
| --- | --- | --- |
| Remaining distance / clock | `HKMC_Navi_ExSL/sources/com/mnsoft/navi/message/a.java:359-360,719-729` forwards engine 0x4D; `automotive-service/sources/com/hkmc/micom/ClusterService.java:3829-3858,5000-5001` stores the complete distance+clock packet and schedules one send. No reset/periodic resend is present. | The local lease used a non-clear turn frame: an empty turn list could release it while a route continued. Session dedupe then retained the old sent value after a competing writer. Lease/arbitration now uses route lifetime, including rerouting/locating. Reacquisition or a renewal gap >=15 s invalidates all outputs. Source/component changes and explicit end/disconnect reset totals; transient invalid estimates do not. A clock-only packet before known distance stays pending so it cannot send an invalid distance. Remove the 3 s SubInfo timer. |
| Transient totals | `HKMC_DiPO/sources/com/daudio/app/dipo/e/c.java:212-235` stores time and route state as separate fields; state is not a distance-invalid command. The analyzer is disabled on this car, so this supports input interpretation only. | Preserve route totals independently of maneuver rendering, including expiry of a held locating turn. States 4/5 retain only an already established route; they do not manufacture one from idle. This is a conservative local state policy, not proof of the vehicle symptom. |
| PE_00 | `HKMC_Navi_ExSL/sources/com/mnsoft/navi/message/a.java:1146-1164` forwards all six fields without a route-state guard; `automotive-service/sources/com/hkmc/micom/ClusterService.java:4158-4170,5280-5281` replaces/sends one complete packet. `automotive/sources/com/hkmc/cluster/NavigationCluster.java:1693,1696-1724` delegates the four-argument API and swallows RemoteException. | Remove 3 s active reassertion, two 1 s clear repeats, and shutdown sleep/retry. Hook the six-argument stock API in the navi process only. Suppress warning-free stock tunnel packets while leased; pass any nonzero parking/HVAC field unchanged. Java does not establish whether the native engine emits this while idle, nor its frequency: the previous claim that it does was unsupported. A swallowed Binder exception is not evidence for retries or an acknowledgement of delivery. Keep one stop clear. |
| AA lanes | `HKMC_GPM/sources/com/google/android/projection/sink/navigation/GpmNaviTBTManager.java:309-333` and `.../navigation/a.java:45-106` update turn/distance/text with no lane-clear command. | Remove the invented icon-change/no-lanes clear. Explicit lane data (including a clear) and route-end clear remain; modern AA structured lane snapshots are independent input, not inferred from an icon change. |
| AA trap | `HKMC_GPM/sources/com/google/android/projection/sink/navigation/GpmNaviTBTManager.java:529-532`; `.../navigation/a.java:50-51,62-63,70-71,81-82,94-95`. | Reset after each accepted AA turn update, not once per guidance. GPM handler cases 6/7 do not send it; those are separate stock destination/distance events, not these accepted turn events. |

Timer/retry inventory in CoreService / GuidanceSession:

- Removed: SubInfo 3 s reassertion; PE_00 3 s reassertion; PE_00 clear repeats and shutdown sleeps; `refreshActive()` successful TBT resend every second. ClusterService has no corresponding expiry. `emitTime()` retry dedupe now uses the source minute, so merely elapsed time does not resend an unchanged arrival clock.
- Kept: one-second worker polls ownership and health and retries pending/invalidated outputs only. `GuidanceSession` records success per channel; `AaRouteCache` records route/lane pending state. `outputError()` invalidates on a visible local exception. No claim that this detects NavigationCluster's swallowed RemoteException; no blind successful packet retry was added.
- Kept: 5 s IAP2 bind/register/request and AA socket bind/accept recovery. Each is conditional on an observed missing service, failed request, or socket exception (Core `bind`, `register`, `requestGuidance`, `startAaSocket`); they are transport lifecycle recovery, not cluster packet reassertion. The interval is local backoff policy, not an OEM timing requirement.
- Kept: PHONE_GUIDING lease renewal (2 s / 15 s expiry in NaviAdapters), a local process-death fail-open protocol. The stock wrapper immediately yields on a real stock turn. Reacquisition invalidates sent caches; asynchronous receiver installation/broadcast delivery still needs vehicle logging.
- Kept: media OSD 3 s restore, scheduled only after this app deliberately replaced navigation text. This is a bounded UI duration, not delivery retry; it restores output the app itself overwrote. The duration is local UI policy, not an OEM requirement.
- Kept: 60 s locating maneuver hold and 120 s AA input expiry. These are explicit stale-guidance safety policies, not stock resend periods. Locating expiry clears maneuver/tunnel output but preserves route totals/lease until explicit route end/disconnect.

DriveLog events 36 (requested full SubInfo values), 37 (lease transitions), and 39 (requested PE_00 values; repeat count field now zero) remain. A void framework call does not prove MICOM delivery. Vehicle validation must correlate these with adapter event 38 and actual distance/clock/HVAC behavior, including route gaps, reroutes, warning packets, ownership changes, and stop. No package, USB update, or vehicle verification is part of this audit.
