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

IC·JC·TG·휴게소라는 글자는 경로 의미를 증명하지 못합니다. 명시적인 램프 타입은 표시하지만, 장소명만 보고 요금소·휴게소·고속도로 전용 화면을 만들지 않습니다. 앱별 정적 분석 결과와 남은 한계는 [지도 앱 변환 계층](navigation-app-evidence.md)에 정리합니다.

## 거리와 다음 회전

상태 필드 10의 다음 회전 거리를 사용합니다. V039 `GpmNaviTBTManager.setDistanceValue`와 동일하게 1,000m 미만은 미터(`scale=0`), 그 이상은 km float(`scale=1`)로 전달합니다. 예를 들어 1,900m는 `1.9f` km입니다. 음수나 미확인 거리는 `distanceErr=-3`으로 비웁니다.

현재·다음 아이콘은 `updateTPTurnListNew`의 첫 두 슬롯과 `updateTBTInfo`의 `displayType`·`sideStreet`에 전달합니다. `combiSideStreet`는 V039 허용 범위에 맞춰 0을 사용합니다. 실제 계기판의 소수점 표시와 두 번째 아이콘은 실차 확인 항목입니다.

## 차선

`LaneFrame`은 확인한 순정 81바이트 F1 형식을 만듭니다. 최대 8개 차선, 차선당 최대 3개 방향을 담고 highlighted angle만 추천 차선으로 표시합니다. 중복 index, index 간격, 지원하지 않는 각도, 존재하지 않는 강조 방향, 4개 이상 방향은 전체 차선을 비웁니다.

방향 표는 두 순정 native 변환표를 대조한 결과입니다. iAP2 각도에서 F1까지 동일한 의미가 유지되는지는 실차에서 확인합니다. 고가·지하 마스크 형식은 확인했지만, 현재 회전 의미를 텍스트로 추정하지 않으므로 구조화된 고가·지하 유형이 없는 입력에는 마스크를 만들지 않습니다.

## Android Auto

V039 `HKMC_GPM.odex`에서 `onNextTurn`, `onNextTurnDistance`, `setTurnDisplayType`, `setRampDisplayType`, `setRoundAboutDisplayType`와 `NavigationCluster.updateTBTInfo` 호출을 직접 확인했습니다. GPM은 Google NavigationStatus의 구조화된 회전 종류·방향·거리 단위를 순정 아이콘으로 변환합니다. `ROUNDABOUT_ENTER`와 `FERRY_TRAIN`은 순정 코드에서도 클러스터에 보내지 않습니다.

`gpm-patch-v039`는 V039 원본 해시가 맞을 때 route 기능 제한 분기만 변경합니다. `CoreService`의 선택적 보조 입력은 송신자가 이미 준 아이콘을 그대로 사용합니다. 아이콘이 없으면 `TYPE`, `DRIVING_SIDE`, `JUNCTION_TYPE`, `EXIT_ANGLE`이 모두 순정 조합을 이룰 때만 변환합니다. 도로명으로 TG·IC·방향을 재해석하지 않습니다.

## 출력과 검증 경계

출력은 `updateTBTInfo`, `updateTPTurnListNew`, `updateTPCrossroadName`, `updateLaneInfo`를 사용합니다. 실패한 최신 회전·거리·차선과 지움 요청은 다시 시도합니다. 한 번도 입력받지 않은 세션이 임의 출력을 만들지는 않습니다.

고속도로 전용 `updateTPHighwayMode` 경로는 앱 입력과 V039 실제 출력이 연결됐다는 증거가 없어 호출하지 않습니다. 순정 과속·카메라 경고는 별도 순정 채널이며 이 앱이 생성하거나 음소거하지 않습니다.

JVM 검사는 파싱·상태·V039 분기표·프레임 변환을 검증하고 APK 빌드는 Android 4.4 호환 코드를 확인합니다. 네이버지도·티맵·카카오내비의 Android/iPhone 실차 표시 성공, 순정 경고와의 동시 표출, 차선의 물리적 좌우 순서, 고속도로 전용 화면은 [실차 검증](validation.md)이 끝나기 전까지 지원 확정으로 표시하지 않습니다.
