# 순정 내비와 HUD 우선순위

순정 내비가 경로 안내 중이면 순정 안내를 우선합니다. CarPlay 회전·차선·거리 출력과 지우기·재전송을 모두 보류하고, 순정 안내가 끝나면 최신 CarPlay 정보를 다시 보냅니다. CarPlay 안내가 그동안 끝났다면 이전 회전 정보를 다시 표시하지 않습니다.

## 안내 상태 확인

순정 서비스가 사용하는 `content://com.mnsoft.navi/State_Table`의 `State_Destination` 열만 읽습니다. 1은 안내 중, 0은 안내 없음입니다. 위치·목적지·주소·연락처는 조회하지 않습니다. 테이블 없음·빈 응답·다른 값·권한 오류는 확인 불가로 처리하고 CarPlay HUD 출력을 보류합니다.

해당 제공자는 일반 앱에 공개되어 있지 않아 NEMESIS가 `owner` 서비스를 system UID 1000으로 실행합니다. 이 서비스는 우리 APK의 UID에서 온 요청만 받고, 앱도 상대 UID가 1000인지 확인합니다. 로컬 소켓으로 안내 중·없음·확인 불가만 전달하며 외부 통신은 하지 않습니다.

출력 직전마다 상태를 다시 조회합니다. 조회 서비스가 멈추거나 응답하지 않아도 CarPlay가 순정 출력을 덮어쓰지 않도록 보류합니다. 1초 재시도로 서비스 복구와 순정 안내 종료를 확인합니다. 순정 프로세스의 상태 갱신과 화면 출력이 하나의 원자적 작업은 아니므로, 실제 전환 시점은 차량에서 확인해야 합니다.

## 과속·카메라 경고

순정의 경고·제한속도 출력 API는 회전·차선·거리와 구분됩니다. 앱은 경고 API를 쓰거나 순정 내비를 종료하지 않습니다. 이 변경은 순정 경고 경로를 유지하는 처리이며, CarPlay 중 순정 내비가 경고를 계속 제공하도록 새로 구현한 기능은 아닙니다. 해당 조합의 HUD 표시는 실차 미확인입니다.

V039의 인터페이스를 확인한 결과 카메라 종류·과속 경고·제한속도는 `updateTBTTrapInfo(17개 int)` 또는 `updateTBTTrapInfoNew(NaviTbtTrapInfo)` 경로입니다. `updateNaviWarnDist(3개 int)` / `updateNaviWarnDist2(10개 int)`는 경고 거리이고, `updateSLIFNaviInformation(5·6·11개 int)`는 별도 제한속도 정보입니다. CarPlay 회전·거리용 `updateTBTInfo(IIFFIIIII)`만으로 이 경고를 생성할 수 없습니다.

순정 내비의 Java 진입점 `NativeCall.sendClusterData`와 `sendClusterParser`에서 경고 변환기로 전달하는 구간에는 CarPlay 표시 상태나 경로 안내 여부에 따른 차단이 없습니다. 다만 이 진입점을 호출하는 native 내비 엔진이 CarPlay 사용 중·목적지 없는 주행 중에도 데이터를 계속 생성하는지는 확인되지 않았습니다. Java 경로의 존재만으로 백그라운드 경고 작동을 판단하지 않습니다.

`NavigationClusterListener.onHandleNaviSLIFInfo`와 G2/G3 콜백은 MICOM에서 내비 쪽으로 들어오는 표지 인식 응답이며, 순정 내비가 출력한 카메라 경고를 구독하는 콜백이 아닙니다. 확인한 인터페이스에는 순정 카메라 경고의 조회·구독 API가 없고, `State_Table`에도 카메라·속도 데이터 열이 없습니다. 따라서 이 콜백이나 경로 안내 플래그를 경고 입력으로 바꿔 재전송하지 않습니다. 새 경고 중계를 구현하려면 native 엔진의 실제 출력 지속 여부와 지원되는 수신 경로가 먼저 증명되어야 합니다.

앱 시작 시 경고·거리·제한속도 writer의 이름·인자·반환형만 조사하고 `hud-native-warning.status`에 다음 중 하나를 기록합니다. 조사 중 writer 호출이나 위치·속도·카메라 값 저장은 없습니다. 이 상태는 순정 내비 활성 상태나 HUD 표시 성공과 별개입니다.

| 상태 | 의미 |
| --- | --- |
| `APIS_PRESENT_SOURCE_UNOBSERVED` | 세 종류의 순정 경고 API 확인, CarPlay 중 경고 입력·표시 미확인 |
| `APIS_INCOMPLETE_SOURCE_UNOBSERVED` | 일부 API만 확인, 경고 입력·표시 미확인 |
| `APIS_UNAVAILABLE_SOURCE_UNOBSERVED` | 확인한 API 없음 또는 조회 실패, 경고 입력·표시 미확인 |

## 결과 확인

USB `GEN5W-REPORT/RESULT.html`의 **HUD 최근 출력 상태**에서 CarPlay 허용·순정 우선·확인 불가를 확인합니다. 설치 직후나 서비스 실행 전에는 아직 확인되지 않음으로 표시될 수 있습니다. 이 항목은 마지막으로 기록한 상태이며 차량의 현재 화면을 보증하지 않습니다.
