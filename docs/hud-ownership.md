# 순정 내비와 HUD 우선순위

순정 내비가 경로 안내 중이면 순정 안내를 우선합니다. CarPlay 회전·차선·거리 출력과 지우기·재전송을 모두 보류하고, 순정 안내가 끝나면 최신 CarPlay 정보를 다시 보냅니다. CarPlay 안내가 그동안 끝났다면 이전 회전 정보를 다시 표시하지 않습니다.

## 안내 상태 확인

순정 서비스가 사용하는 `content://com.mnsoft.navi/State_Table`의 `State_Destination` 열만 읽습니다. 1은 안내 중, 0은 안내 없음입니다. 위치·목적지·주소·연락처는 조회하지 않습니다. 테이블 없음·빈 응답·다른 값·권한 오류는 확인 불가로 처리하고 CarPlay HUD 출력을 보류합니다.

해당 제공자는 일반 앱에 공개되어 있지 않아 NEMESIS가 `owner` 서비스를 system UID 1000으로 실행합니다. 이 서비스는 우리 APK의 UID에서 온 요청만 받고, 앱도 상대 UID가 1000인지 확인합니다. 로컬 소켓으로 안내 중·없음·확인 불가만 전달하며 외부 통신은 하지 않습니다.

출력 직전마다 상태를 다시 조회합니다. 조회 서비스가 멈추거나 응답하지 않아도 CarPlay가 순정 출력을 덮어쓰지 않도록 보류합니다. 1초 재시도로 서비스 복구와 순정 안내 종료를 확인합니다. 순정 프로세스의 상태 갱신과 화면 출력이 하나의 원자적 작업은 아니므로, 실제 전환 시점은 차량에서 확인해야 합니다.

## 과속·카메라 경고

순정의 경고·제한속도 출력 API는 회전·차선·거리와 완전히 분리된 독립 채널입니다:
- 회전·거리: `NavigationCluster.updateTBTInfo(IIFFIIIII)` 및 차선 프레임 (우리 앱이 CarPlay/Android Auto에서 수신하여 전송)
- 과속·카메라: `NavigationCluster.updateTBTTrapInfo(17개 int)` 및 경고 거리 `updateNaviWarnDist(3개 int)` (순정 내비 엔진이 안전운전 모드에서 전송)

### 순정 카메라 억제 원인 및 생존 메커니즘
1. **억제 원인 (리버스 엔지니어링 확인)**:
   CarPlay 또는 Android Auto 길안내가 시작되면, 프로젝션 시스템이 `com.mnsoft.navi.action.Route_Guide_ACTION` 또는 `SOUND_OFF`를 순정 내비(`NaviETCReceiver`)로 전송합니다. 이를 수신한 순정 내비는 C++ 네이티브 엔진에 opcode `0x836` ("Carplay route is set" / "AA route is set")을 내려보내며, 네이티브 엔진은 즉시 클러스터/HUD 단속카메라 패킷(`updateTBTTrapInfo`) 생성을 전면 중단(Mute)합니다.
2. **생존 처리 (안전운전 모드 유지)**:
   네이티브 엔진은 opcode `0xfa5` ("Carplay route is not set" / "AA route is not set")를 받으면 정상 백그라운드 안전운전 안내 모드로 복귀하여 단속카메라 패킷을 다시 송출합니다. 이 신호는 `com.mnsoft.navi.action.SOUND_ON` 브로드캐스트를 통해 트리거됩니다.
3. **CoreService 감시 및 공존 구현**:
   `CoreService`는 순정 내비가 목적지 안내 중이 아닐 때(`StockGuidance.IDLE`) 주기적으로 및 연결/상태 전환 시 `com.mnsoft.navi.action.SOUND_ON`을 유지합니다. 이를 통해 순정 내비의 안전운전 안내 엔진이 셧다운(`0x836`)되는 것을 차단하고 `0xfa5` 모드를 유지시킴으로써, **HUD에 CarPlay/Android Auto TBT 길안내 화살표와 순정 과속·카메라 경고가 동시에 정상 표출**되도록 동작합니다. 순정 내비에서 목적지를 직접 설정한 경우(`StockGuidance.ACTIVE`)에는 순정 안내에 모든 제어권을 양보합니다.

앱 시작 시 경고·거리·제한속도 writer의 이름·인자·반환형만 조사하고 `hud-native-warning.status`에 다음 중 하나를 기록합니다. 조사 중 writer 호출이나 위치·속도·카메라 값 저장은 없습니다. 이 상태는 순정 내비 활성 상태나 HUD 표시 성공과 별개입니다.

| 상태 | 의미 |
| --- | --- |
| `APIS_PRESENT_SOURCE_UNOBSERVED` | 세 종류의 순정 경고 API 확인, CarPlay 중 경고 입력·표시 미확인 |
| `APIS_INCOMPLETE_SOURCE_UNOBSERVED` | 일부 API만 확인, 경고 입력·표시 미확인 |
| `APIS_UNAVAILABLE_SOURCE_UNOBSERVED` | 확인한 API 없음 또는 조회 실패, 경고 입력·표시 미확인 |

## 결과 확인

USB `GEN5W-REPORT/RESULT.html`의 **HUD 최근 출력 상태**에서 CarPlay 허용·순정 우선·확인 불가를 확인합니다. 설치 직후나 서비스 실행 전에는 아직 확인되지 않음으로 표시될 수 있습니다. 이 항목은 마지막으로 기록한 상태이며 차량의 현재 화면을 보증하지 않습니다.
