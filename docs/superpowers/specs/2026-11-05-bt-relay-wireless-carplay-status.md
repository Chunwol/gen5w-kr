# 블루투스 중계 방식 무선 CarPlay: 조사 결과와 진행 상태 (2026-11-05)

상태: **V039 중계·설치·원복 코드 완성, 공개판 비활성, 실차 미검증**. 아래 초기 목록은 과거 기록이며 현재 기준은 이 상단 갱신이다.

## 2026-11-06 구현 갱신

- 순정 PhoneProjection을 먼저 사용하고, V039에서 CarPlay 프로필이 확인된 뒤 순정 요청이 BLOCKED/FAILED일 때만 중계를 시작한다.
- `V039BtRelayAdapter`가 Broadcom BTCM SPP와 iAP2 component 4를 연결하고, 생성형 DiPO process-local adapter가 component 5와 CarPlay native 경계를 연결한다. component 5 요청 방송이 대기 반환보다 먼저 실행되도록 고쳤다.
- AP broker는 완성 마커와 모든 산출물 해시가 맞는 로컬 시험판에서만 UID 1000으로 시작한다. 공개 빌드는 마커와 제조사 파생 APK가 없어 기존 순정 관찰 경로만 사용한다.
- DiPO APK·ODEX와 Iap2ServerApp ODEX를 함께 백업·적용·복원한다. mock 223개에서 설치, 제거, 중단 stage, APK/ODEX rename 사이 전원 차단 복원, dexopt 실패 롤백을 확인했다.
- exact V039 입력 빌더는 동일 SHA256 산출물을 반복 생성했고, 생성 DEX의 session·iAP2·CarPlay hook 7개를 디스어셈블해 확인했다.
- 남은 판정은 실차 연결뿐이다. 첫 페어링, 재연결, Wi-Fi AP, 30분 오디오, 통화·핸들키, 유선 CarPlay, Android Auto, HUD, 시동 재연결, 제거를 확인하기 전 성공을 표시하지 않는다.

## 2026-11-05 최종 재감사

- `BtRelaySession`, `BtRelayPipe`, `CarPlayHandoverPipe`의 순수 상태·전송 계층은 구현돼 있다.
- exact V039 Broadcom BTCM SPP와 iAP2 component 4를 사용하는 `V039BtRelayAdapter`가 빌드된다. 직접 `BluetoothSocket`이나 사설 RFCOMM 소켓은 열지 않는다.
- exact V039 `Iap2ServerApp.odex`에는 public `Iap2SvcTransportReadDone([BI)Z`가 있어 component 4 입력 경계는 확인됐다.
- exact V039 DiPO에는 native 송수신 경계가 있지만, 현재 고정 길이 recipe에는 이를 iAP2 component 5와 연결하는 process-local call edge가 없다. 별도 추출 DEX에서는 구현 가능성만 확인했으며, OEM 파생 DEX를 배포하거나 zygote/app_process를 교체하는 방식은 사용하지 않는다.
- 따라서 `V039BtRelayAdapter`는 component 4만 담당하며 component 5를 성공으로 취급하지 않는다. AP broker도 runtime에 연결하지 않았다.
- `relay-gate.sh`는 완성 마커가 없으면 기존 순정 경로를 유지하고, 마커나 필수 산출물이 일부만 있으면 host 시작 전에 실패하도록 한다. 현재 빌드는 완성 마커를 만들지 않는다.
- 결과적으로 이 변경은 실패한 직접 RFCOMM을 복원하지 않으며, 불완전한 신규 중계를 설치판에 켜지 않는다. 무선 CarPlay 해결 여부는 아직 실차에서 입증되지 않았다.

## 2026-11-05 현재 진행 상태

- 기준 브랜치: `codex/stock-first-wireless`, 안전 토대 기준 커밋 `1ab9eca` 이후 작업.
- v0.3.35 OEM bootstrap·Wi-Fi 관찰·HUD/진단 코드는 이미 포함돼 있다.
- 순정 경로는 실차에서 Broadcom SPP 뒤 `isPossibleWCP=false`로 막혔고 iAP2가 시작되지 않았다.
- `bt_patch.py`는 component 4/5 진입점만 만들며 SPP 데이터 중계, DiPO component-5 인계, AP 시작은 하지 않는다. 따라서 단독 설치하지 않는다.
- BT recipe와 기존 route recipe는 같은 순정 Iap2ServerApp ODEX를 대상으로 하는 대체 산출물이다. 순차 적용하지 않는다.
- 새 설계와 구현 계획은 `2026-11-05-v039-bt-relay-integration-design.md`, `../plans/2026-11-05-v039-bt-relay-integration.md`에 정리했다.
- Task 1로 순수 `BtRelaySession`을 추가했다. SPP → iAP2 component 4 → DiPO handover/component 5 → AP → projection 활성 순서, 단계별 timeout, 세대 검사, 역순 정리, 정리 완료 전 새 owner 차단을 JVM 테스트로 고정했다.
- Task 2 기반으로 순수 `BtRelayPipe`를 추가했다. 한 세대만 SPP↔iAP2 component 4를 소유하고, 양방향 프레임 복사·쓰기 실패·연결 해제·비밀값 없는 고정 진단 범주를 테스트했다. 외부 전송 호출 중에도 소유권 잠금은 잡지 않는다.
- Task 3 검증으로 BT recipe를 V039 전용으로 제한하고, component 4/5 시작·종료, route recipe와의 대체 관계, 정확한 순정 V039 ODEX 재생성 및 DEX/ODEX 무결성을 검사했다. 빌드·설치에는 아직 연결하지 않았다.
- Task 4 기반으로 순수 `CarPlayHandoverPipe`를 추가했다. DiPO process-local 경계와 iAP2 component 5 사이 양방향 프레임, 단일 owner, 연결 해제·쓰기 실패·차단된 전송 중 취소를 JVM 테스트로 고정했다.
- 아직 Android/BTCM/iAP2/DiPO/AP runtime adapter에 연결하지 않았으며 설치 ZIP에도 포함하지 않았다.
- AP helper 소스는 남아 있지만 UID 1000 실행 경로가 증명되지 않았다. 이 조건을 해결하기 전에는 runtime에 연결하지 않는다.

## 왜 이 방식을 검토했나

v0.3.35(순정 PhoneProjection 경로) 실차 진단(DIAG-2, 09:37~09:40) 결과:

- PhoneProjection이 SPP 연결까지는 한다(`START_SPP_CONNECT_FOR_CONNECTIVITY` → BTCM SPP 연결).
- 그 뒤 iAP2가 전혀 시작되지 않고, BTCM이 `[WPP] isPossibleWCP result=false`로 막는다.
- `isPossibleWCP`는 무선 프로필이 등록된 기기만 허용한다. 한국 V039는 프로필 등록 화면이 막혀 있어 순정 경로만으로는 진행할 수 없다.
- Wi-Fi 드라이버가 올라오지 않아(`wlan.driver.status=unloading`, `wlan0` 없음) 아이폰 Wi-Fi 목록에 차가 보이지 않았다.

10/26에는 Leafia 이식 + 핫스팟 이름 맞추기(KonaApFix)로 무선 CarPlay가 실제로 연결됐다. 이때 결정적인 요인은 실제 핫스팟 SSID/PSK와 iAP2가 아이폰에 보내는 CarPlay용 값(`ConnectivitySSID/PSK`)을 일치시킨 것이었다.

## 확인한 사실 (정적 분석)

- 순정 `Iap2Service.onStartCommand`는 intent를 무시하고 1을 반환한다. 예전 gen5w-kr(≤v0.3.26)의 `startService(... component=3)` 요청은 실제로 아무 일도 하지 않았다.
- 순정 iAP2 서버는 USB attach 수신기에서만 세션을 시작한다(`setDeviceSerial` + `receiveConnect`). 바인더(IIap2Service)에도 블루투스 세션 시작 메서드가 없다.
- 예전 gen5w-kr 브리지는 자체 RFCOMM 소켓을 열다가 `socket-connect`에서 실패했다. Leafia/HMG-API는 순정 Broadcom BTCM SPP(`IbtcmSppConnect`, SPP 콜백)를 쓴다.
- `com.broadcom.bt`, `com.tcc.iap2` 라이브러리는 `/system/etc/permissions`에 공개 선언돼 있다. `HfDeviceBTCMService`는 exported이고 권한 속성이 없다. 일반 앱에서 SPP 중계가 가능할 가능성이 높지만 실차 확인은 안 했다.
- `Iap2Service`는 intent-filter가 있어 기본 exported이며 권한이 없다. 서버 자신은 component extra를 붙여 자기 서비스를 시작하는 곳이 없다. 같은 extra 키는 상태 broadcast에만 쓴다.
- `persist.sys.iap2.wifi=t`(WiFiInformation 기능 광고)와 `persist.iap2.iden.wireless=t`(WirelessCarPlayTransportComponent)는 Leafia가 켜던 속성이다. 우리 차에는 설정돼 있지 않다.
- 무선 세션이 끝나면 순정 DiPO가 `android.intent.action.telechips.carplay.over.wireless.disconnected`를 broadcast한다. 우리 앱이 상태 정리에 쓸 수 있다.
- 10/26 기준 코나의 `libCarPlayCore.so`는 Wi-Fi 세션을 기본 허용하는 빌드였다(네이티브 패치 불필요).
- Leafia 방식은 DiPO에도 코드 변경이 필요하다: iAP2 리스너가 블루투스 세션을 받아들이게 하고, CarPlay 채널의 iAP2 데이터를 중계한다.

## 구현된 것 (커밋 안 됨, 빌드·설치에 연결 안 됨)

- `tools/iap2/bt_patch.py`, `tools/iap2/bt-v039.json`, `tools/iap2/bt-v035.json`
  - 기존 control shim과 같은 방식이다. 순정 메타데이터만 쓰고, 레시피에는 직접 작성한 명령과 오프셋, 파일 해시만 담는다.
  - 내용: `onStartCommand`에 블루투스 세션 진입점을 둔다. component 4/5이면 `setDeviceSerial(serial)` + `receiveConnect`, -4/-5이면 `receiveDisconnect`, 그 밖의 값은 무시한다.
  - Wi-Fi 정보와 경로 안내 기능 플래그 2개를 함께 켠다.
  - 디컴파일로 핸들러가 설계대로 나오는 것까지만 확인했다. 테스트와 설치 스크립트에서는 아직 쓰지 않는다.

## 구현 안 된 것

- DiPO 쪽 변경: **진행 중단.** 이 작업 도중 응답이 자동 안전 필터에 의해 중단돼 같은 방식으로 이어가지 않았다.
- 우리 앱(wirelesshost)의 BTCM SPP ↔ iAP2 중계, 상태 관리
- 핫스팟 이름 맞추기용 ApBroker(uid 1000) 재가동. 코드는 `src/kr/gen5w/hotspot/`에 남아 있고, `6795ea2^`의 service.sh에 실행 방식이 있다.
- iAP2 속성 설정과 원복
- 설치·제거·서비스 스크립트 상태 추가, 테스트, 버전, 변경 기록

## 위험 메모

순정 앱 ODEX를 바꾸는 작업이다. 브릭 원인은 확정되지 않았지만 10/28 브릭 차량에도 같은 종류의 변경이 있었다. 진행한다면 기존의 해시 확인, 백업, 부트가드, 자동 원복을 유지해야 한다.

## 남은 일 정리 (2026-11-05 추가)

### A. 이 저장소에서 계속 진행할 수 있는 일

1. 현재 HEAD 전체 검증: `tests/run.sh`, JVM 테스트, `tools/build-all.sh`, `tools/audit-artifacts.py dist`
   - 이전 실행에서 실패한 통합 테스트 4개(`lib/libCarPlayAudio.so is not a recognised stock file`)의 원인 확인
2. `1b64288` 주행 로그·토스트 실차 확인
   - DEBUG-ON USB로 기록 시작 토스트, `GEN5W-DRIVELOG/` 생성, 진단 시작·완료 토스트
3. core 서비스 `kind=instance` 시작 오류(`Activity class does not exist`) 원인 확인
4. 버전 정리와 변경 기록(한국어), 필요한 경우 릴리스

### B. 목록만 남기는 일 (구현 방법 미기재)

아래 항목은 개발 도중 응답이 자동 안전 필터로 중단돼 진행하지 않았다. 이 문서에는 구현 방법을 적지 않는다.

- DiPO 쪽 변경 (블루투스 세션 수용, CarPlay 채널 iAP2 처리)
- 우리 앱(wirelesshost)의 SPP ↔ iAP2 중계
- 핫스팟 도우미(ApBroker) 재가동과 핫스팟 이름 맞추기
- iAP2 속성(`persist.sys.iap2.wifi`, `persist.iap2.iden.wireless`) 설정과 원복
- 위 항목을 설치·제거·서비스 스크립트와 테스트에 연결
- `tools/iap2/bt_patch.py` 레시피를 설치 과정에 연결

참고 자료(공개 저장소, 직접 확인 필요): Leafia(아카이브), HMG-API(AGPL-3.0, 코드 복사 금지)의 무선 브리지 설명과 구조.

### C. 원칙 (계속 유지)

- MICOM·부트로더·모뎀 플래시 금지, 부팅 핵심 파일은 순정 유지
- 차량별 비밀 정보(/data, 인증서, VIN, 일련번호 등) 저장 금지
- 제조사 앱·라이브러리 전체를 저장소에 넣지 않음, Mobis 소스 재배포 금지
- 변경은 해시 확인, 백업, 부트가드, 자동 원복을 유지하고 실차 확인 전에는 성공을 주장하지 않음
