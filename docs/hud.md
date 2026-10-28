# HUD 길안내 앱 (app/)

CarPlay의 회전·거리·차선 정보를 순정 `NavigationCluster`로 전달합니다. 자체 CAN 전송이나 제조사 구현 포함은 없습니다.

- `GuidanceParser`: 순정 상수의 상태 `0x78`, 회전 `0x79`, 차선 `0x7a` 알림. component 생략·배열, 부분 갱신, unsigned 거리, 중복·불완전 필드를 처리합니다.
- `GuidanceSession`: 상태의 현재 회전 목록(13)과 현재 차선 집합(16)을 별도로 선택합니다. 차선 표시(18)가 참일 때만 차선을 보냅니다. 지도 변경·component 변경·재탐색·도착·연결 해제는 양쪽 캐시와 표시를 지웁니다. 회전 목록 변경 시 차선 선택이 함께 오지 않으면 차선 캐시를 버립니다.
- `ClusterIcon`: 일반 회전, 완만/급한 회전, U턴, 진입/진출, 도착, 고가/지하, 요금소, 휴게소, 페리, 고속도로 변경과 회전교차로를 처리합니다. NoTurn(0)과 알 수 없는 타입은 비웁니다. 회전교차로 1~19 출구는 출구 번호를 방향으로 오인하지 않고 각도·통행 방향을 사용합니다. 두 값 중 하나가 없으면 비웁니다.
- `TurnFrame`: 87바이트 F2, 3개 아이콘과 UTF-16LE 도로명. 비움은 `F2,00`입니다.
- `LaneFrame`: 81바이트 F1. 1~8개 차선에 각각 최대 3개 방향과 추천을 담습니다. index는 0 또는 1부터 연속이어야 하고 프레임 슬롯은 0부터 정규화합니다. 중복·간격·지원하지 않는 각도·존재하지 않는 강조 방향·4개 이상 방향은 전체 차선을 비웁니다.
- `LaneBits`: 추천 방향이 있는 차선으로 고가/지하 마스크를 만듭니다. 도로명/설명에서 인식한 고가/지하 유형에 따라 적용합니다.
- `CoreService`: 별도 listener `gen5wkr.core`로 복사한 메시지를 전달합니다. 연결 세대가 다른 대기 알림을 버립니다. 종료 시 자기 listener만 해제합니다.
- `GuidanceRequest`: 등록 후 native count/list API에서 실제 광고된 component 이름을 얻어 `Iap2SvcStartRouteGuidanceUpdate(names,true,true)`를 요청합니다. 식별/인증/연결 알림과 5초 재시도로 준비 지연을 처리하며 성공은 연결 세대당 한 번만 요청합니다. 공용 `StopRouteGuidanceUpdate`는 호출하지 않습니다.
- `NativeWarningSupport`: 실행 중 firmware의 순정 경고·경고 거리·제한속도 writer 선언을 읽어 호환 여부를 따로 기록합니다. API 존재와 실제 경고 수신을 구분하며 경고 writer는 호출하지 않습니다. 카메라 HUD 중계 기능을 새로 구현한 것은 아닙니다.

`GuidanceSession.Sink`는 기존 회전 전용 소비자를 유지합니다. `LaneSink extends Sink`를 구현하면 `lanes(byte[])`도 호출합니다. 동일한 프레임은 성공적으로 전송된 뒤에만 중복 억제합니다. 실패한 전송은 다음 갱신에서 재시도합니다.

출력 실패는 새 길안내 메시지가 없어도 1초 간격으로 최신 목표 프레임만 재시도합니다. 회전·차선·거리의 실패한 지움도 보존하며, cluster 바인딩 오류가 나면 세 채널을 다시 전송합니다. 한 번도 안내/지움 요청을 받지 않은 세션은 재시도 타이머만으로 임의 출력을 만들지 않습니다. NoTurn과 알 수 없는 회전 유형은 도로명에 특수 도로 키워드가 있어도 비우고, 명시적 회전 방향은 도로명의 좌우 표현보다 우선합니다.

순정에서 직접 대응하지 않는 ExitFerry(16)는 직진, ChangeFerry(17)는 페리, ChangeHighway(51)는 계속 주행 아이콘을 쓰는 자체 의미 기반 대체 규칙입니다. 회전교차로의 비정확한 각도는 확인한 순정 각도 앵커 사이의 가까운 구간을 사용합니다. 이 규칙과 index 오름차순이 물리적 좌→우라는 가정은 실차 최종 확인 대상입니다.

파싱·상태 처리·프레임 변환은 JVM에서 검증하고, APK/DEX 구성과 서명은 CI에서 검사합니다. 실제 차량 확인 항목은 [검증 범위](validation.md)에 정리합니다.

KR step 110 순정 DiPO는 route listener 등록을 step 999 이상에서만 켜므로 순정 요청에 의존하지 않습니다. Core의 자체 요청만으로 순정의 꺼진 route capability를 켤 수는 없습니다. 이 환경에서는 bridge의 해시 검증된 route capability shim이 함께 설치되어야 하며, capability가 광고되지 않으면 성공으로 표시하지 않고 기다립니다. wired HUD도 동일한 route capability 조건이 적용됩니다.

좌측 통행 회전교차로는 순정에서 확인한 일반 원형 `C0`를 사용합니다. 좌측 통행 방향별 코드가 증명되지 않아 출구 방향 세부 표시는 제공하지 않습니다.

거리 출력은 status 필드10의 미터 값을 별도 보존하여 `NavigationCluster.updateTBTInfo(IIFFIIIII)`로 전달합니다. 순정 `GpmNaviTBTManager.setDistanceValue` 및 `ClusterService.getFloatToShort` 규격에 맞춰 1,000m 미만은 미터(`scale=0`), 1,000m 이상은 킬로미터(`scale=1`, 최대 `32767.9`km 클램핑)로 변환하여 16비트 정수 변환 시 장거리 잘림을 방지합니다. 거리가 생략된 부분 갱신은 유지하고, 회전 선택·지도·연결이 바뀌면 비웁니다. 미확인 거리에는 `distanceErr=-3`을 사용하며 정적인 회전 구간 길이를 현재 남은 거리로 대신하지 않습니다. 2nd TBT(다음 연속 회전 아이콘)는 `updateTPTurnListNew`의 2번째 슬롯과 `updateTBTInfo`의 2번째 파라미터(`sideStreet`)로 전달하며, 6번째 파라미터(`combiSideStreet`)는 V039 순정 범위 검사(`0~4`)에 맞춰 `0`을 전달합니다. V039 `ClusterService$NaviCluster.sendTPHighWay()`는 펌웨어 내 빈 메서드(`return-void`)이므로 고속도로 IC/JC/TG/휴게소 안내는 1차 회전 아이콘과 `TurnFrame`/`CrossroadName`으로 표출합니다.

또한 Android Auto(AA)는 순정 Google Projection 모듈(`/system/app/HKMC_GPM.odex`)의 `stepofspec == 999` 분기를 `wireless-bridge`의 `gpm-patch-v039`로 우회하여, Google 표준 계기판 턴바이턴 채널(`NavigationStatusService`)과 순정 `GpmNaviTBTManager`를 차량 네이티브 수준에서 활성화합니다. 순정 `GpmNaviTBTManager`는 회전 이벤트(`onNextTurn`)와 거리 이벤트(`onNextTurnDistance`)를 직접 `NavigationCluster`로 전달합니다. 이와 별개로 `CoreService`는 보조 외부 입력 인터페이스(`kr.gen5w.action.AA_TBT`, `kr.gen5w.action.AA_LANE`, `gen5wkr.aa.tbt` 로컬 소켓)를 제공하여, 외부 브리지나 보조 송신기가 연결된 경우 한국 도로 어휘 보정(`ClusterIcon.refineManeuver`)과 단순 차선 프레임(`LaneFrame.encodeSimple`)을 렌더링할 수 있습니다(순정 `HKMC_GPM` 단독 실행 시에는 `GpmNaviTBTManager`의 기본 TBT 경로로 동작합니다).

순정 내비 안내 중에는 CarPlay HUD 출력을 양보합니다. 상태 조회가 실패해도 출력·지우기를 보류하고, 안내 종료 후 최신 CarPlay 정보를 다시 전송합니다. 앱은 순정 내비의 음소거를 변경하지 않습니다. 과속·카메라 경고의 동시 표출은 실차 확인 대상입니다. [HUD 우선순위](hud-ownership.md)와 [V039 코드 대조 결과](v039-cluster-review.md)를 참고하세요.

핸들 통화 버튼의 보완 범위와 확인 항목은 [CarPlay 핸들 통화 버튼](wireless-call-button.md)을 참고하세요.
