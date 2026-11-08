# 기능 미동작 경로 감사 — 2026-11-08

## 후속 소프트웨어 수정 (로컬 작업, 실차 미검증)

아래 본문은 v0.3.56-rc.1 감사 당시 기록이다. 후속 수정으로 동일 폰
fallback에 최대 3회/5·10초 백오프와 fresh OEM 소유권 검사를 추가했다.
정리 완료 전 재시작을 차단하고 component 4 정리 시 pipe 소유권을 함께
해제한다. 종료 시에도 소유한 AP의 STOP 작업을 버리지 않고 drain하며,
종료 후 활성화는 차단하고 정리 guard는 20초로 제한한다.

화면 요청은 최신 sequence만 기록하고 boot ID/30초 만료를 root에서
검증한다. stale 상태에서는 조작·최종 제거 확인을 차단한다. 제거는 다른
스위치 처리보다 배타적으로 실행해 완료된 제거 요청이 표식을 재생성하지
않는다. ADB 요청 결과와 실제 daemon/listener 상태를 별도 표시하며 같은
ON 요청으로 고장난 daemon을 복구할 수 있다.

HUD는 fresh 소유권 heartbeat를 별도 표시하고 provider 관찰 timeout 뒤
무한 worker 생성을 막았다. AA 소켓 bind/accept 실패는 재시도하며 종료 시
server/client를 닫는다. 호스트 준비/Wi-Fi 인터페이스 존재를 연결 성공으로
표시하지 않는다. 회귀 근거: RequestSafetyTest, request-envelope.sh,
adb-health.sh, core_recovery.py, relay_coordinator_integration.py,
relay_adapter_ownership.py 및 wireless_bridge_integration.py.

미해결 전제조건: wlan0/드라이버 기동, 순정 연결용 자격 증명, OEM 지원 및
실제 CarPlay/HUD 출력. 물리 SPP disconnect는 검토된 API가 없어 그대로
유지하고 로컬 소유권만 해제한다. CarPlay의 ADB용 AP 중단 정책은 유지한다.
이 수정은 기존 게시 릴리스/USB에 자동 반영되지 않는다.

대상: v0.3.56-rc.1 후보. UI 수정과 별개로 무선 연결, 핫스팟/ADB,
HUD, 안내창, 화면 요청, 설치/제거 흐름을 읽었다. 아래 항목은 실차
재현 결과가 아니다. 코드에서 확인한 조건과 실차에서 확인할 사실을 구분한다.
이번 릴리스는 UI 보완이며 아래 기존 기능 문제를 모두 수정한 버전은 아니다.

## 우선순위와 결론

P1은 주력 기능을 막을 수 있어 차량 진단을 먼저 확인할 항목,
P2는 조건부 오동작/복구성/표시 문제다. 이번 UI 변경에서 새로 확인한
부팅 파괴나 원복 불가의 확정 결함은 없다. 이는 차량 안전성 보장이 아니다.

### 1. P1 / 무선: Wi-Fi 인터페이스·연결용 자격 증명은 여전히 전제조건

- 근거: `ProjectionWifiAccess.inspect()`는 ConnectivitySSID/ConnectivityPSK
  존재만 관찰한다. `BtRelaySession.requestApIfReady()`는 자격 증명이 준비돼야
  START_AP를 낸다. `ApProfiles.ensure()`도 연결용 SSID/키가 없으면 거절한다.
- 영향: 블루투스 연결만으로는 Wi-Fi 비콘이나 CarPlay가 보장되지 않는다.
  드라이버가 실제로 기동 실패하거나 순정 연결용 설정이 생성되지 않으면
  AP 시작 순서 수정과 이번 체크박스 교체로 해결되지 않는다.
- 확인할 것: 같은 연결 시도의 `wifi-credentials-*`, `wifi-ap-*`,
  `wlan0` 생성/드라이버 로그와 relay 단계. 현재 차량의 상태는 새 진단 필요.
- 분류: 구조상 전제조건, 현재 실차 원인으로 단정 불가.

### 2. P2 / 무선: 같은 휴대폰의 실패 뒤 fallback 자동 재시도가 막힘

- 근거: `V039RelayCoordinator.start()`는 `attemptedCandidate`가 같으면 반환한다.
  이 값은 시작 전에 설정되고 실패/cleanup 완료에서는 초기화되지 않는다.
  `candidateLost()`에서만 초기화한다. `WirelessBridge.maintainRelay()`의
  반복 `start(address)`도 이 검사에 막힌다.
- 영향: AP/SPP/iAP2가 일시 실패한 뒤 휴대폰 BT 연결이 계속 유지되면,
  준비 조건이 좋아져도 같은 폰 fallback은 그대로 대기할 수 있다.
- 복구: 무선 기능 OFF/ON으로 호스트를 재시작하거나 BT 완전 재연결.
- 개선안: 무제한 반복이 아닌 제한 횟수·백오프·fresh ownership 재검사.
- 분류: 코드 경로 확인. 1회 시도 정책을 의도했는지는 별도 결정 필요.

### 3. P2 / 화면: 연속 조작 요청이 생성 순서와 다르게 저장될 수 있음

- 근거: `MainActivity.sendRequest()`는 클릭마다 새 Thread를 만들고
  `SwitchRequest.write()`를 부른다. write의 LOCK은 파일 쓰기만 직렬화한다.
  requestSeq는 실패 콜백 표시만 거르고, 오래된 요청의 쓰기를 막지 않는다.
- 영향: 먼저 생성된 작업이 늦게 실행되면 최신 요청 파일을 예전 상태로
  덮을 수 있다. 무선/타이머/블루링크 상태를 함께 저장하므로 다른 스위치를
  빠르게 연속 조작할 때도 원치 않는 상태가 요청될 수 있다.
- 확인 범위: 가능한 스케줄을 코드로 확인. 일반 UI 시험은 순차 클릭이라
  이 순서 뒤집기를 검증하지 않는다. 실차 발생률은 측정하지 않았다.
- 개선안: 단일 쓰기 executor + 최신 sequence의 요청만 반영하거나,
  파일 쓰기 잠금 안에서 요청 세대 검사. 단순 rename 원자성만으로 해결 안 됨.

### 4. P2 / 화면: 오래된 상태 파일도 스위치·관리 조작을 허용함

- 근거: `StatusModel.readable()`과 `stale()`은 별개다. `buildOnOff()`와
  관리 버튼은 주로 readable만 검사한다. stale 경고는 `buildInfo()`에서만
  보여 준다. 제거 최종 확인 버튼은 enabled=true로 생성된다.
- 영향: root 수집기가 멈춰 파일만 남으면 현재처럼 보이는 조작이 가능하다.
  적용되지 않거나, 이후 수집기가 재개되며 남아 있던 요청이 처리될 수 있다.
  최종 제거 확인을 연 뒤 서비스가 사라지는 경우도 freshness 재검사가 없다.
- 개선안: 마지막 성공 스냅샷의 freshness와 실제 서비스 응답을 조작 시점에
  재검사. 오래된 요청에는 만료/boot ID를 포함. HUD 로컬 스위치는 별도 취급.

### 5. P2 / ADB: ON은 실제 접속 성공이 아니라 포트 속성 상태

- 근거: `uilog.sh`의 `adb_state()`는 service.adb.tcp.port > 0만 본다.
  `set_adb()`는 setprop 후 adbd stop/start를 호출하지만 listen 소켓이나
  IP·인증·서비스 ready를 확인하지 않는다. token은 set_adb 전에 소비된다.
- 영향: 속성이 5555여도 adbd가 정상 기동하지 않거나 네트워크가 없으면
  ON 표시와 달리 접속 불가하다. 일시 실패한 동일 token은 자동 재실행 안 됨.
- 복구: 체크 해제 후 다시 설정하면 새 token을 만든다. 네트워크와 PC의
  키 승인도 별도로 확인해야 한다. 이 스위치는 핫스팟을 켜지 않는다.
- 개선안: 요청/적용 실패/리스닝/네트워크 상태를 분리하고 실패 이유 표시.

### 6. P2 / HUD: 순정 내비 소유권 확인 실패 시 의도적으로 출력 차단

- 근거: CoreService.refreshOwnership()는 StockGuidance.IDLE에서만 허용한다.
  StockGuidance는 system UID helper 소켓 응답을 읽고, StockOwner는 순정
  `com.mnsoft.navi/State_Table`의 State_Destination을 조회한다. helper 부재,
  응답 지연, provider 오류/알 수 없는 값은 UNKNOWN이다.
- 영향: 폰 길안내 데이터가 와도 계기판/HUD에 안 나올 수 있다. 순정 내비
  동작과 충돌하지 않기 위한 fail-closed 정책이지 무조건 제거할 결함은 아니다.
- 확인할 것: owner helper 실행, hud-owner.status, 경로 입력 이벤트와 출력
  이벤트를 분리해 관찰. 물리 HUD 지원/차량 설정도 별도 확인.

### 7. P2 / 무선 표시·Android Auto: 실행 중과 연결 가능은 다름

- 근거: 상태 수집기의 host=alive는 PID/프로세스명/ready 파일 검사다.
  정보 화면은 이를 `무선 사용 가능`으로 표현한다. 폰 인증·AP·세션 활성화를
  이 문자열이 보증하지 않는다. fallback은 maintainRelay()의 carPlay 조건으로
  제한돼 Android Auto에는 같은 BT-iAP2 우회가 적용되지 않는다.
- 영향: 호스트는 살아 있어도 무선 실패 가능. Android Auto의 순정 무선
  프로필 생성/연결 실패를 CarPlay fallback이 해결해 주지는 않는다.
- 개선안: 호스트 준비/AP 준비/폰 연결을 단계별 표시하고 플랫폼별 한계를 명시.

### 8. 조건부 제한 / 안내창과 블루링크 숨기기

- 타이머는 순정 ODEX 해시와 ConsentScreen 로그 형식·버튼 활성 조건이
  맞아야 동작한다. 로그를 못 읽거나 조건이 다르면 순정 10초 동작으로 남는다.
- 블루링크 모듈은 확인된 앱·원본 prefs·예상 XML 모양이 맞을 때만 쓰고
  15초 간격으로 확인한다. 가입 활성화나 인터넷 서비스를 제공하지 않는다.
- 이 조건을 무시하도록 수정하는 것은 이번 UI/배포 범위를 벗어난다.

## 정상 정책으로 유지하는 것

- CarPlay가 일반 ADB용 핫스팟을 끄고 projection AP를 우선하는 동작.
- AP의 순정 부팅 복원. 예전 감사에서 이를 결함으로 취급했던 판단은 철회됨.
- 순정 내비 active/unknown이면 HUD 출력을 막는 소유권 경계.
- 정확한 OEM 원본/백업/소유권이 확인되지 않으면 설치·제거를 중단하는 동작.

## 이번에 검증한 것과 안 한 것

- 체크박스 UI: normal/locked/unknown/compact instrumentation 통과.
- 버전업 후 로컬 전체 회귀시험·APK 빌드 통과. 실제 APK는 versionCode 12,
  versionName 0.3.56-rc.1이며 `tests/apk_version.py`로 manifest와 대조한다.
  빌드 CLI의 옛 version 인자는 manifest 값을 강제로 덮는 동작이 아니었다.
  초기 의심을 철회하고 혼동을 주는 인자/완료 문구만 정리했다.
- 기존 시험은 코드/격리 환경 검증이다. 차량 부팅·Wi-Fi·iPhone·Android Auto·
  HUD 물리 출력과 현재 설치된 NEMESIS에서의 동작을 검증한 것은 아니다.
- 위 기존 기능 이슈는 감사 결과로 기록했으며, 이번 UI 릴리스에서 전부
  수정했다고 주장하지 않는다. 차량 검증 전 안정판 대신 시험판으로 배포한다.
