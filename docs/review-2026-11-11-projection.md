# 구조·흐름 리뷰: CarPlay·Android Auto 무선 연결 (2026-11-11)

기준 커밋 `74b3441`(feature/in-car-ui). 코드 읽기와 PC에서 재현 가능한 확인만 근거로 삼는다. "확정"은 코드·자료로 증명된 것만, 추정은 별도 표시한다. 실차 동작은 이 문서의 어떤 항목으로도 입증되지 않는다.

## 진행 상황 (중단 시 여기부터 이어서)

| 범위 | 상태 |
|---|---|
| 설계 문서 `design.md`, `bt-wireless-start.md`, `dipo-control.md`, `bridge-install.md`, `iap2-fields.md` | 읽음 |
| `WirelessBridge`, `StockProjectionSession`, `PhoneProjectionAccess`, `BluetoothCandidateScan`, `SdpRefresh` | 읽음 |
| API 19 호환성(dex 참조 대조) | 완료 |
| 순정 receiver의 extra 키·프로필 조회 대조(V039 dexdump) | 완료 |
| `V039RelayCoordinator`, `BtRelaySession`, `V039BtRelayAdapter`, `BtRelayPipe` | 읽음(확정 결함 없음) |
| `CarPlayHandoverPipe`, `WirelessSession` | 확인: 어디서도 쓰이지 않음(아래) |
| `AndroidWifiAp`, `ApBroker*`, `ApProfiles` | 읽음(확정 결함 없음) |
| `ProjectionWifiAccess`, `BridgeHostService` | 읽음(확정 결함 없음) |
| `scripts/service.sh` 실행 루프(150–248행) | 읽음(확정 결함 없음) |
| 설치·원복 스크립트 흐름 | 미완(GPM·원복은 v0.3.59에서 시험 추가됨) |
| core 길안내: iAP2 연결·등록(`CoreService` 328–429행) | 읽음(확정 결함 없음). 리스너 이름 `gen5wkr.core`가 중계의 `gen5wkr.bt`와 달라 순정 `addListener`의 같은 이름 교체에 서로 지워지지 않음 |
| core 길안내: 파서·HUD 출력, Android Auto GPM 패치 | 미완 |
| 공식 규격 대조: Apple 무선 CarPlay | 완료(WWDC 2017 세션 717) |
| 공식 규격 대조: Android Auto 무선 | 공식 공개 규격 없음(아래) |

## 조사 자료와 방법

### 대조 기준 자료 (V039 확인)
- `analysis_private/system-current.img`는 **V035**(빌드 `20250507`)이고, 그 안에서 뽑은 `analysis_private/*_dump.txt`도 V035 기준이다. 차량은 V039이므로 이 자료만으로 결론을 내지 않는다.
- V039 기준은 `D:/kona_gen5w_decrypted/system.ext4`(빌드 `eng.vmadmin.20260902.183132`, 차량 보고서의 빌드 번호와 같음). `HKMC_DiPO.odex` md5 `97f866a9…`가 차량 설치 로그의 순정 DiPO md5와 일치한다.
- 추출 방법: WSL `debugfs -f`로 읽기 전용 dump → ODEX 헤더(`dey\n036`)의 dexOffset/dexLength로 내장 DEX 분리 → class `access_flags`의 VERIFIED/OPTIMIZED 비트(0x10000/0x20000) 제거 → SHA-1·adler32 재계산 → `dexdump -d`. 추출물은 저장소 밖 scratchpad에만 두고 배포하지 않는다.
- 한계: ODEX는 가상 호출이 vtable 번호로 바뀌어(`unused-f8` 등) 메서드 이름이 사라진다. 그래서 "어떤 가상 호출이 없다"는 grep만으로 단정하지 않고, 이름이 남는 정적·인터페이스 호출과 문자열 상수로 판단한다.

### 순정 PhoneProjection 접근 가능성 (V039)
- `ContextImpl`에 `"phoneprojection"` 서비스 fetcher가 등록되어 있다(`Context.PHONEPROJECTION_SERVICE`). 일반 앱의 `getSystemService("phoneprojection")`가 PPManager를 돌려준다.
- `PPManager`에 브리지가 쓰는 `getWLDeviceInfo(String,String,int)`, `requestConnectSPP(String)`, `getWirelessConnectState()`, `getCPConnectedBTAddress()`, `getAAConnectedBTAddress()`가 같은 시그니처로 존재한다.
- 서비스 구현 `com.android.server.phoneprojection.PPService`에는 권한 문자열 상수와 `Binder.getCallingUid` 호출이 없다. 일반 앱(호스트 APK `kr.gen5w.wirelesshost`는 자체 키 서명의 비시스템 앱)의 호출을 막는 검사가 없다.
- 순정 `WirelessPhoneProjectionService.onCreate`는 `SEND_CONNECTION_PHONEPROJECTION`, `START_SPP_CONNECT_FOR_CONNECTIVITY`를 **권한 인자 없이** `registerReceiver(receiver, filter)`로 등록한다.
- V039 `framework-res.apk`의 보호 브로드캐스트 195개와 `/system/app`, `/system/priv-app`의 시스템 앱 88개 매니페스트 어디에도 이 두 동작은 보호 브로드캐스트로 선언되어 있지 않다. 비시스템 앱의 송신이 `SecurityException`으로 막히지 않는다.
- **결론: 브리지의 순정 요청 경로는 권한 때문에 막히지 않는다(문제 없음).** 순정 서비스가 요청을 받은 뒤 실제로 연결하는지는 별개이며 실차 미확인이다.

### 순정 receiver와 브리지 요청 형식 대조 (V039 `WirelessPhoneProjectionService$h.onReceive`)
- `SEND_CONNECTION_PHONEPROJECTION`: `getStringExtra("deviceAddress")` → `f.a(ctx, addr, null, d.ea())`로 프로필을 다시 읽는다. 프로필이 꺼져 있으면 순정이 `on_off`를 켠다. 이어서 연결 방식 설정이 `CONNECTIVITY`면 `service.c(addr)`·`service.g(addr)`, `HOTSPOT`이면 `service.a(type, addr, false, false)`. 브리지의 extra 키 `deviceAddress`와 일치한다.
- `START_SPP_CONNECT_FOR_CONNECTIVITY`: `getStringExtra("ADDRESS")` → `WirelessPhoneProjectionService.a(service, addr)`. 브리지의 `ADDRESS`와 일치한다.
- 참고: 순정 처리기는 `f.a`가 `null`(프로필 없음)을 돌려주면 바로 `getWLDType()`을 호출하므로 순정 앱에서 NPE가 난다. 브리지는 프로필이 `READY`일 때만 이 동작을 보내므로 이 경로를 밟지 않는다.
- 프로필 조회 인자: 순정 `f.n`은 두 번째 인자(`device_serial`)가 `null` **또는 빈 문자열**이면 `bt_address=? AND user_type=?`만 쓴다. 브리지가 넘기는 `""`는 순정의 `null`과 같은 쿼리가 된다.
- 사용자 유형: 순정 `d.ea()`는 `Feature.hasFeature("com.hkmc.software.user.profile")`일 때만 `UserProfileManager`에서 읽고, 아니면 0을 쓴다. 브리지는 항상 `UserProfileManager.getUserType()`을 쓴다. V039에는 `/system/etc/permissions/com.hkmc.software.user.profile.xml`이 있고 `onebin/oshev_kr/featurexml.cfg`의 제거 목록에도 없으므로 두 값의 출처가 같다. **문제 없음.**

### API 19(Android 4.4) 호환성
- 빌드: `tools/build-dex.sh`는 `javac --release 8` + `d8 --min-api 18`. 인터페이스 `default` 메서드(`StockProjectionSession.Port`)는 d8이 변환하므로 Dalvik에서 문제없다.
- 컴파일 기준 jar가 android-36이라 빌드만으로는 API 19에 없는 호출을 막지 못한다. 그래서 `platforms/android-36/data/api-versions.xml`의 `since` 값과 실제 dex가 참조하는 메서드·필드·타입을 대조했다(스크립트는 scratchpad `apicheck/check.py`).
- 대상: `bridge.dex`, `wireless-host.apk`, `gen5w-core.apk`, `gen5w-probe.apk`.
- 결과: API 20 이상 참조는 `WifiConfiguration(WifiConfiguration)` 복사 생성자(공개 API 30) 하나뿐. V039 `framework.odex`(위 V039 이미지에서 추출)에서 이 생성자와 `ConnectivitySSID`, `ConnectivityPSK`, `apMode` 필드가 존재함을 확인했다. **문제 없음.**

### 공식 자료: Apple 무선 CarPlay (WWDC 2017 세션 717 "Developing Wireless CarPlay Systems")
출처: https://developer.apple.com/videos/play/wwdc2017/717/ (발표 대본). 슬라이드 PDF는 텍스트 추출이 안 돼 대본만 근거로 삼았다. MFi 사양서 원문은 비공개라 대조하지 못했다.
- 연결 순서: Bluetooth 페어링 → Bluetooth 위의 iAP2 연결 → 휴대폰이 Wi-Fi 정보를 요청, 차가 응답("The head unit must wait for the user confirmation before responding") → 휴대폰이 AP에 접속 → Bonjour로 찾은 뒤 **차가** CarPlay Control로 세션 시작 → CarPlay 위의 iAP2 연결("at this point iAP2 is also still connected over Bluetooth") → 휴대폰의 Bluetooth 끊기 요청에 차가 그 기기의 Bluetooth 연결을 모두 끊음.
- 재연결: 시동 뒤 Bluetooth와 AP가 모두 준비되면 차가 iAP2 over Bluetooth를 다시 연다. 사용자 조작이 필요 없어야 한다.
- **케이블을 뺄 때: "you should not start wireless CarPlay when the driver disconnects from USB, she might be just leaving the car."** 또 "a wireless CarPlay session will start automatically only after an ignition cycle".
- 무선 사용 중 케이블을 꽂으면 무선 유지("we do not want any interruptions"). 실행 중 세션은 사용자가 명시적으로 바꾸기 전에는 끊지 않는다.
- 휴대폰이 멀어지는 등 연결이 끊기면 차가 빠른 재연결을 먼저 시도하고, 실패하면 Bluetooth 재연결로 간다.
- AP: Wi-Fi Alliance 인증, 5 GHz·802.11ac 권장, 2.4 GHz를 쓰면 CarPlay 세션 동안 Bluetooth 스택을 완전히 꺼야 한다. 숨김 SSID는 권장하지 않음. 보안 방식(WPA2)은 대본에 언급 없음.
- Bluetooth SDP: iAP2 UUID는 차 쪽 `00000000-deca-fade-deca-deafdecacaff`, 휴대폰 쪽 `…decacafe`(Apple 공식 문서가 아니라 공개 분석 글 기준: oligo.security "Pwn My Ride", cnblogs BlueZ iAP2 글). 브리지의 `APPLE_CAFF`/`APPLE_CAFE` 값과 일치한다.

### 공식 자료: Android Auto 무선
- Google은 무선 Android Auto의 차량 쪽 프로토콜을 공개하지 않는다(파트너 전용). 공개 자료는 "Bluetooth로 처음 연결한 뒤 5 GHz Wi-Fi로 옮겨 간다" 수준의 설명뿐이다(engadget/aawireless FAQ). 오픈소스 재구현(aa-proxy-rs 등)은 공식 자료가 아니므로 대조 근거로 쓰지 않았다.
- 이 브리지는 Android Auto 무선을 직접 구현하지 않는다. 순정 PhoneProjection에 연결 요청(`SEND_CONNECTION_PHONEPROJECTION`)만 보내고, 실제 RFCOMM·Wi-Fi 교환은 순정 코드가 한다. 그래서 Android Auto는 "순정이 요청을 받는 형식"만 대조했고(위 절), 이 부분은 일치한다.

### V039 보조 경로(CarPlay 중계)와 AP 코드 검토 결과
- `BtRelaySession`: 단계마다 시한(SPP 10초, iAP2 15초, 전환 30초, AP 30초, 활성화 60초)이 있고, 실패·취소는 항상 `STOPPING`을 거쳐 AP 끄기 → component 5 중지 → component 4 중지 → SPP 소유 해제 순서로 정리한다. 세대 번호가 다른 콜백은 무시한다. 확정 결함 없음.
- `V039RelayCoordinator`: AP 켜기·끄기는 단일 스레드 실행기에서 순서대로 실행된다. 정리 도중 켜기가 늦게 끝나도 뒤에 줄 선 끄기가 반드시 실행된다. 같은 휴대폰에 3회까지, 5초씩 늘어나는 간격으로 재시도하고, 그 뒤에는 Bluetooth가 끊기거나 후보가 바뀔 때까지 멈춘다(설계 의도).
- `V039BtRelayAdapter`: V039 `Iap2ServerApp`의 `Iap2SvcInit`→`addListener`를 확인했다. 같은 이름(`gen5wkr.bt`)의 기존 리스너를 먼저 지우므로 호스트가 다시 시작해도 리스너가 쌓이지 않는다. `stop(4)`의 재진입(파이프 닫기→다시 `stop(4)`)은 순정 중지 명령을 한 번만 보내도록 짜여 있다. 확정 결함 없음.
- `AndroidWifiAp`/`ApProfiles`/`ApBroker`: 브로커는 uid 1000, 호스트 앱 uid만 받으며, 명령은 `E`/`D` 한 글자뿐이고 비밀번호는 소켓을 지나지 않는다. 클라이언트 연결이 끊기면 진행 중인 AP 작업이 취소된다. WPA2(auth type 4) 이외 설정은 거부한다. 확정 결함 없음.
- `service.sh`: 브로커는 V039 중계 패키지가 완전할 때(relay gate 0)만 띄운다. 호스트·브로커는 재시작 횟수 제한이 있고, 초과하면 무선을 멈추고 유선만 남긴다. 확정 결함 없음.
- OEM 라이브러리 로딩: 호스트 앱은 `com.broadcom.bt`, `com.tcc.iap2`를 `uses-library required=false`로 선언한다. V039 `/system/etc/permissions/com.broadcom.bt.xml`, `com.tcc.iap2.xml`이 각각 `/system/framework/com.broadcom.bt.jar`, `com.tcc.iap2.jar`를 라이브러리로 등록하고 두 jar가 실제로 있다. 따라서 `WirelessBridge` 생성 시 중계 어댑터 클래스가 로드되어도 클래스 없음으로 죽지 않는다. 혹시 없더라도 `BridgeHostService.onStartCommand`가 `LinkageError`를 잡아 중계만 끄고 끝낸다.
- `ProjectionWifiAccess`: 읽기 전용이며 모든 예외를 `UNKNOWN`으로 바꾼다. AP 상태 숫자(10–14)는 Android 4.4 `WIFI_AP_STATE_*` 값과 같다. 확정 결함 없음.
- `CarPlayHandoverPipe`, `WirelessSession`은 `bridge.dex`에 들어 있지 않고 소스 어디에서도 참조되지 않는다(dexdump 클래스 목록과 grep으로 확인). 동작에 영향은 없고, 남아 있는 미사용 코드다.

## 수정 내역 (2026-11-11, 미커밋)
| 문제 | 수정 | 시험 |
|---|---|---|
| P5 순정에서 무선/자동연결 꺼도 보조 경로 시작 | `StockProjectionSession.userDisabled()` 추가. `WirelessBridge.inspectRelayProjection()`이 새 관찰에서 사용자가 끈 상태면 시작하지 않고, 진행 중인 중계는 취소(`REQUESTED`) | `wireless_bridge_integration.py` `stockOffSettingBlocksAndStopsRelay`(끔·자동연결 끔 둘 다, 켜진 프로필은 여전히 허용). 수정 전 코드에서 실패 확인 |
| P2 일시 실패 1회로 재시도 없음 | 순정에 아무것도 보내기 전의 조회 실패·시한 초과만 5·15·30초 뒤 최대 3회 다시 조회. 새 세대로 바꿔 늦게 온 옛 응답은 무시. 순정에 요청을 보낸 뒤의 실패는 기존대로 끝(같은 연결에 순정 요청 1회 원칙 유지). 기록 코드 46 `retry-scheduled` 추가(`docs/drive-log.md`) | `StockProjectionSessionTest` `failedReadBeforeOemActionRetriesThenFails`, `failedReadAfterOemActionDoesNotRetry` |
| P3 중계 알림 무권한 수신 | 세 `RELAY_HANDOVER_*` 동작만 `android.permission.SHUTDOWN` 보유 송신자로 제한. 송신자인 순정 DiPO는 V039 매니페스트상 `sharedUserId="android.uid.system"`이고, Android 4.4는 system uid의 권한 검사를 항상 통과시킨다. 브리지 정지 수신기가 이미 같은 권한을 쓴다 | `relayNoticesRequireSystemSender`. 수정 전 실패 확인 |
| P4 중계 점검 `Error` 시 영구 대기 | 점검 작업을 `Throwable`까지 잡고 항상 메인 스레드로 결과(null)를 보내 대기 표시를 푼다. null 결과는 시작도 취소도 하지 않음 | `failedRelayReadNeverSticks`(서비스 조회에서 `ExceptionInInitializerError`). 수정 전 실패 확인 |
| 유선→무선 전환 순서 불일치(아래) | 케이블이 꽂힌 동안 새로 잡힌 휴대폰도 그 Bluetooth 연결 동안은 무선을 시작하지 않음(사용자 선택: Apple 지침 따름) | `unplugNeverStartsWirelessInEitherOrder` |

확인한 시험: `tests/java.sh` 전체, `wireless_bridge_integration.py`, `relay_coordinator_integration.py`, `relay_adapter_ownership.py`, `stock-projection-source.sh`, `bridge.sh`, `bridge-retry.sh`, `wireless.sh`, `relay-gate.sh` 통과. `tools/build-dex.sh`로 `bridge.dex` 빌드 성공, API 19 대조 결과 변화 없음(기존 복사 생성자 1건). 전체 회귀(`tests/run.sh`)와 실차 확인은 하지 않았다.

## 유선·무선 전환 점검
| 상황 | 브리지 동작 | 판정 |
|---|---|---|
| 순정 무선 사용 중 케이블 꽂음 | 브리지는 추적만 멈추고(`CANCELLED`) 순정 연결에는 손대지 않음. 어느 쪽으로 갈지는 순정과 휴대폰이 결정 | 문제 없음. Apple은 무선 유지를 권장하나 이는 순정 몫 |
| V039 보조 경로(중계) 무선 중 케이블 꽂음 | `refreshWired()`가 중계를 `WIRED`로 취소 → AP 끄기·iAP2 중지 → 순정 유선으로 넘어감 | 의도된 동작으로 판단. 순정 V039에는 유·무선 동시 세션을 조정하는 기능이 없어, 케이블이 꽂히면 순정 유선 CarPlay가 시작되므로 중계를 남기면 두 세션이 겹친다. Apple의 "무선 유지" 권장과는 다르다. 실차 미확인 |
| 유선 사용 중 케이블 뺌 (Bluetooth 유지) | 무선을 시작하지 않음. 다음 Bluetooth 연결(보통 다음 시동) 때 자동 연결 | Apple 지침과 일치. **수정 전에는 케이블이 Bluetooth보다 먼저 연결된 경우에만 뺄 때 무선 요청이 나갔다.** 이제 순서와 무관하게 같다 |
| 케이블 감지 방법 | USB 기기 목록의 Apple(0x05ac)·Google(0x18d1) 공급자 ID, `sys.usb.config`/`sys.usb.state`의 `carplay_connect` | Android 폰은 AOA(유선 AA) 전환 뒤에만 0x18d1로 보이므로, 충전만 하는 삼성 폰은 유선으로 보지 않아 무선 AA가 계속 가능하다. iPhone은 충전만 해도 0x05ac라 무선을 막는다(순정 유선 CarPlay가 시작되는 상황과 같음) |


## 추가 점검 (길안내·Android Auto·안전 장치)

### N1. 순정 경로의 AP 켜기는 "AP 켜다 재시작" 감시에 잡히지 않음 (확정, 수정함)
- **수정(2026-11-11, 미커밋)**: 새 `StockApGuard`가 순정 요청(`SEND_CONNECTION_PHONEPROJECTION`, `START_SPP_CONNECT_FOR_CONNECTIVITY`) 직전에 호스트 폴더 `files/ap-attempt`에 부팅 id를 기록한다. 연결 활성 후 45초면 `ap-ok`를 쓰고 지우고, 실패·취소면 45초 뒤 `ap-ok` 없이 지운다(순정이 우리 대기 시간 이후에도 AP를 켤 수 있어 실패도 기다림). `service.sh apguard_boot`이 이 기록을 기존 기록과 같이 세며, 한 부팅은 두 기록이 다 있어도 1회로 센다. 링크 파일이면 무선을 시작하지 않는다. `apguard_reset`(설치·제거)이 새 파일도 지운다. 시험: `StockApGuardTest`(6개), `tests/bridge.sh` 7개 항목(옛 service.sh에서 실패 확인). 남는 한계: 연결 시도 후 45초 안에 시동을 끄면 재시작 1회로 셀 수 있다(정상 연결 1회로 0이 됨, 기존 브로커 가드와 같은 성질).
- `AndroidWifiAp`의 주석과 `service.sh`의 `apguard_boot`은 "첫 AP 켜기가 곧 첫 Wi-Fi 드라이버 로드이므로, AP를 켜는 도중 장치가 재시작하면 기록이 남고 3회 연속이면 무선을 끈다"는 안전 장치다.
- 그런데 이 기록(`/data/nemesis/gen5wkr.apguard/attempt`)을 쓰는 곳은 `AndroidWifiAp.markAttempt()` 하나뿐이고, 이것은 V039 중계용 AP 브로커(uid 1000)에서만 실행된다. 기본 경로인 순정 경로에서는 브리지가 `SEND_CONNECTION_PHONEPROJECTION`을 보내면 **순정 PhoneProjection이 AP를 켜며**, 이때는 아무 기록도 남지 않는다(`wireless/*.java`에 apguard 기록 코드 없음). 호스트 앱은 일반 앱 uid라 그 폴더(1000:1000, 700)에 쓸 수도 없다.
- 부팅 감시(`bootguard-state.sh`)는 `sys.boot_completed`에 도달하면 `mark-ok`로 횟수를 0으로 되돌린다. 그래서 부팅 완료 뒤에 일어나는 재시작은 세지 않는다.
- 결과: 만약 순정 AP 켜기가 장치를 재시작시킨다면, 시동마다 "부팅 → 휴대폰 Bluetooth 연결 → 브리지 요청 → 재시작"이 자동 차단 없이 반복될 수 있다. 실제로 순정 AP 켜기가 재시작을 일으키는지는 **확인되지 않았다**(이 문서는 원인을 주장하지 않는다). 확정된 것은 "프로젝트가 스스로 정한 안전 장치가 기본 경로를 덮지 못한다"는 코드 사실이다.
- 고칠 방향(제안, 사용자 확인 필요): 호스트가 순정 요청 직전에 자기 폴더(`/data/data/kr.gen5w.wirelesshost/files/ap-attempt`)에 부팅 id를 기록하고, AP가 45초 이상 켜져 있거나 시도가 AP 없이 끝나면 지운다. `service.sh`의 `apguard_boot`이 이 파일도 같은 방식으로 센다.

### N2. 문서와 코드 불일치 (확정, 낮음, 수정함: `docs/integrated.md` 설명 교체)
- `docs/integrated.md` 77행은 "무선 시작 가드는 핫스팟이 아니라 bridge 프로세스의 반복 시작을 제한"한다고 쓰지만, 코드에서 `gen5wkr.apguard.off`는 **AP 켜기 도중 재시작 횟수**(`apguard_boot`)로 만들어진다. 호스트·브로커 반복 실패는 별도 재시도 한도로 그 부팅 동안만 무선을 멈추고 `off` 파일을 만들지 않는다.

### M1. 휴대폰 여러 대가 연결됐을 때 (동작 확정, 의도된 동작으로 유지)
- **결정(2026-11-11, 사용자)**: 지금 동작이 정상이다. 선택된 한 대만 시도하고 다른 휴대폰으로 넘어가지 않는다. 우선순위는 차량 "자동 연결 우선순위"에 맡긴다. V039 중계 경로도 같은 후보만 쓴다(`relayEligible`이 `session.candidate()`와 같은 주소만 허용)는 점을 확인했고, 그대로 둔다.
- 브리지는 한 번에 한 대(`candidate`)만 시도한다. 고르는 기준은 **후보가 없을 때 가장 먼저 Bluetooth(ACL) 연결 이벤트가 온 휴대폰**이다(`connected()` → `offerCandidate()`, `LinkedHashSet`). 1초마다 도는 `scan()`은 목록을 등록 기기 순서로 다시 만들지만, 후보가 이미 있으면 바꾸지 않는다.
- 차량의 "자동 연결 우선순위"는 V039 `PhoneProjection` 설정 화면의 `BUTTON_AUTO_CONNECTION_PRIORITY` 버튼 → `com.android.btsettings`의 `ChangeDeviceOrder` 화면이다. 즉 **Bluetooth 자동 연결 순서** 설정이다. 브리지는 이 순서를 직접 읽지 않는다. 다만 차가 우선순위 1번 휴대폰부터 연결하면 그 휴대폰의 연결 이벤트가 먼저 오므로 보통은 1번이 후보가 된다. 1번이 범위 밖이거나 다른 휴대폰이 먼저 연결되면 그 휴대폰이 후보가 된다.
- 고른 휴대폰이 그 Bluetooth 연결 동안 계속 후보로 남는다. 그 휴대폰이 무선 연결 불가(순정 설정에서 꺼짐, 프로필 불일치, 실패)로 끝나도 **다른 연결된 휴대폰으로 넘어가지 않는다**. 첫 휴대폰의 연결이 끊겨야 다음 휴대폰을 시도한다.
- 첫 휴대폰에 순정 무선 프로필이 없으면 그 휴대폰으로 순정 최초 등록(`START_SPP_CONNECT_FOR_CONNECTIVITY`)을 1회 요청한다.
- 이미 한 휴대폰이 순정 무선으로 연결 중이면(`otherActive`) 다른 휴대폰은 `foreign-active`로 막힌다. 두 대가 동시에 연결되지는 않는다.
- 순정 DB에는 `last_connection`, `auto_connection` 열이 있고 순정 코드에 `checkLastConnection`(조건 `last_connection=? AND user_type=?`)이 있다. 브리지는 이 "마지막 연결 기기" 정보를 쓰지 않는다. 순정이 이것으로 여러 대 중 하나를 고르는지는 끝까지 추적하지 않았다.
- 실사용 영향: 무선 CarPlay/AA 휴대폰을 차량 "자동 연결 우선순위" 1번으로 두면 대부분 그 휴대폰이 선택된다. 개선안(사용자 결정 필요): 선택된 휴대폰이 무선 불가로 끝나면 다음 연결된 휴대폰을 시도하거나, 순정 프로필이 준비된(READY) 휴대폰을 먼저 고른다.

### T1. 시동 안내창 자동 닫기(`consent-timer`)가 USB 연결·다른 창이 있을 때 안 닫힘 (사용자 제보, 원인 미확정)
- V039 SystemUI(`/priv-app/SystemUI.odex`, baksmali)에서 확인: 순정 10초 타이머는 `dQ()` 조건이 모두 맞을 때만 돈다. 조건은 화면 활성, 후방카메라·후진 아님, 전원/통화/비상/DiPO 통화 중 하나, `mAccStatus==0`, 언어 선택창·업데이트 완료창·발레 아님, 운전자 프로필(기능이 있을 때만)이다. **USB 상태는 조건에 없다.**
- `CLOSE_CONSENTSCREEN_FORCE` 수신 시 SystemUI는 조건 없이 닫는다. 순정은 전원·ACC·통화·후진·발레 등 여러 이벤트마다 같은 검사를 다시 하고 상태 줄을 다시 쓴다.
- 우리 타이머는 이 상태 줄이 순정 조건을 통과할 때만 닫는다. 즉 순정이 "아직 닫지 않음"으로 판단하면 우리도 닫지 않고 순정 10초 타이머도 돌지 않으므로, 확인 버튼을 눌러야 닫힌다. 이것은 설계대로다.
- `mAccStatus`는 SystemUI 로그상 `Received PowerStatus`(`ACTION_ACC_STATUS_CHANGED` / `android.ibox.mode.EXTRA_ACC_STATUS`)로, 전원(ACC) 상태다. 우리 로그의 거부 사유 이름 `accessory`는 USB 액세서리로 오해될 수 있는 잘못된 이름이다(확정, 낮음).
- 저장된 실차 timer 로그(중복 포함): 거부 사유 `screen-off` 315, `screen` 172, `accessory` 80, `reverse` 40. "sending close request" 251회 대비 "completed" 85회지만, 로그에 시각이 없고 같은 로그가 여러 USB 사본에 중복돼 있어 결론을 내릴 수 없다.
- 저장된 어떤 보고서에도 SystemUI 자신의 ConsentScreen 로그 줄은 없다. 그래서 USB가 꽂혀 있을 때 어느 조건이 막는지는 **확인할 수 없다**.
- "USB 연결중" 상단 바 가설 확인: V039 SystemUI `usb/l.smali`(StorageNotification)의 `showUsbReadingNotification`이 USB 저장장치를 읽는 동안(`MEDIA_CHECKING` 등) 띄우는 **알림**이다. 이 코드는 안내창(consentscreen)을 참조하지 않는다. 우리 닫기 신호 `CLOSE_CONSENTSCREEN_FORCE`는 SystemUI 안에서 안내창 수신기(`consentscreen/d.1`)만 받는다. 버튼 누르기나 뒤로 키가 아니라서 상단 바를 대신 닫을 수 없다. 코드상 근거는 없음. 실행 중 영향(부팅 지연 등)은 로그 없이 판단 불가.
- 다음 단계(제안): timer 로그에 SystemUI 상태 줄의 시각과 실패 조건 이름, 그 순간 맨 위 창 이름을 남기고, USB를 꽂은 상태로 실차 1회 확인한다. 거부 사유 이름 `accessory`는 `power-status`로 바꾼다.

### 나머지 부분 순차 점검 (2026-11-11)
확정 결함 없음. 확인 근거:
- `bluelink-quiet`: V039 `HKMC_TAppVRM`이 서비스 설정 파일을 `createPackageContext(...,7)` + `getSharedPreferences(...,7)`(다중 프로세스 포함)로 읽어 파일 변경을 다시 읽는다. VRM·Service 모두 `android.uid.system`이라 `660 1000:1000` 권한으로 충분하다.
- `drive-log`: 앱 기록 코드(bridge 1–2, core 20–35)가 수집기 허용 목록과 일치한다. USB 마운트·장치 번호 재확인, 32×1MiB 순환 기록, 여유 공간 64MiB 하한.
- `wireless-enable`: 원본·적용본 해시 기록, 봉인 후에만 적용, 복원 재개 가능. 하드웨어 확인 실패(unknown)는 설치 제외(77)나 기존 유지(78)이다(예전 "unknown 통과" 구멍은 막혀 있음).
- `audio-format`: 원본·패치본 해시 일치할 때만 교체, 원본을 /system·/data 두 곳에 보관한다.
- `core`: `recovery-launch.sh`의 `PIPESTATUS`는 V039 mksh(R43 2013/02/19)에 있다(바이너리 문자열로 확인). `uilog.sh` 요청 처리는 고정 단어, 부팅 id, 30초 만료, 링크 거부, 3초 읽기 제한. `StockOwner`/`StockGuidance`는 실패 시 출력 차단.
- 차 화면 앱(`MainActivity`, `SwitchRequest`): 요청 순번·만료·부팅 id가 `uilog.sh` 형식과 일치한다. 만료 기준 `elapsedRealtime`과 `/proc/uptime`은 둘 다 부팅 후 경과 시간이다.
- 제외: 설치·제거·원복(`tools/integrated`, 차 화면 제거·복구 실행 경로)은 다른 세션 담당.
- T1 확인 도구: `probe` 패키지의 `collect.sh`가 SystemUI 자신의 안내창 로그(`logcat -b system -s ConsentScreen`)를 `consent.log`로 USB에 저장한다. USB를 꽂은 채 시동 후 이 키트로 수집하면 막힌 조건을 확인할 수 있다.

### 설치·제거·원복 흐름 점검 (2026-11-11, 코드 읽기만, 수정 없음)
대상: `tools/integrated/{NEMESIS,install,update,wired-only,remove,rollback,stock-recover,recovery,common,services,recovery-lib}.sh`, `packages/core/scripts/{uilog,recovery-launch}.sh`. 다른 세션의 미커밋 변경이 있는 파일이라 고치지 않았다.

**R1 (확정, 다른 세션 logic-audit 1번과 같음) 제거할 때 서비스를 먼저 멈추지 않음.**
- USB 제거: `remove.sh`는 `q_begin` 없이 `begin`으로 들어간다. `Q_ACTIVE=0`이라 `safe_remove`의 `q_barrier`가 바로 통과하고, 패키지 자체의 preuninstall(원본 복원)이 서비스가 도는 중에 먼저 실행된다. NEMESIS는 훅 다음에야 서비스를 멈춘다.
- 차 화면 제거: `uilog.sh do_remove`의 `run_hook`도 서비스 정지 없이 훅을 먼저 실행한다.
- 설치(`install_transaction`), 복원(`rollback_transaction`), 순정 복구(`stock-recover.sh`)는 `q_begin`을 쓴다.

**R2 (확정, 새로 찾음) 차 화면 제거는 시스템 앱 파일을 되돌린 뒤 콜드 재부팅을 하지 않음.**
- bridge 제거는 `HKMC_DiPO`와 `HKMC_GPM`의 APK·ODEX를 원본으로 되돌린다(`wireless-bridge/scripts/common.sh:443`, `gpm-relay.sh:123`).
- USB 제거·복원·순정 복구는 끝에 `cold_reboot`(`force_normal`)를 부른다. 이유는 `rollback.sh` 주석에 "ODEX를 바꾸면 콜드 부팅"으로 적혀 있다.
- 차 화면 제거(`do_remove`)는 `done`만 기록하고 재부팅하지 않는다. 화면 안내도 "Manager에서 core 제거"뿐이다.
- 프로젝트의 안전 규칙과 맞지 않는다. QuickBoot와 바뀐 ODEX가 어긋났을 때 실제로 문제가 되는지는 확인되지 않았다(`cold_reboot` 주석도 원인 미확정이라고 적고 있음).

**R3 (확정, 다른 세션 logic-audit 6번과 같음) 순정 복구가 중간에 실패하면 차 화면 "이전 상태로 복구" 버튼이 쓸 수 있는 것처럼 보임.**
- 순정 복구가 실패하면 `state=recovery-required`가 되고 `stock-recovery-mode`가 남으며 `prior/complete`도 그대로 있다.
- `uilog.sh recovery_status`와 `recovery-lib.sh r_check`는 `stock-recovery-mode`를 보지 않는다. 그래서 `available=yes`·`ready`가 된다.
- 버튼을 누르면 `rollback_transaction` 첫 줄이 거부해서 결과가 `rollback-failed`로 나온다. 순정 복구 USB로 안내해야 한다.
- 시스템은 바뀌지 않는다. 거부가 `q_begin`보다 앞이다.

**수정 (사용자 "고치던거 있는지 보고 고쳐", "그 변경 이어서 작업")**
- 먼저 다른 세션의 미커밋 변경을 확인했다. NEMESIS 버전 정책(1.16.7 미만 거절, 모르는 버전은 확인 파일 필요)뿐이었고, 관련 시험(nemesis-minimum, service-quiescence, service-install-hold, stock-recover, entry-errors)은 모두 통과했다. R1–R3를 고치던 흔적은 없었다. 그 변경 위에 이어서 고쳤다.
- R1 USB: `remove.sh`가 `begin` 전에 `q_begin`으로 서비스를 멈추고 정지를 확인한다. 첫 변경 전에 `Q_MUTATING=1`을 둔다. 옛 런타임(1.15–1.16.3)은 rollback과 같이 경고만 하고 진행한다.
- R1 차 화면: `do_remove`가 패키지마다 훅을 실행하기 전에 그 패키지의 NEMESIS 서비스를 멈추고 `.stopped` 표식을 확인한다. bridge는 `kr.gen5w.wirelesshost`도 강제 종료한다. 멈추지 못하면 그 단계에서 실패로 멈춘다. core 서비스는 건드리지 않는다(이 작업 자신이 core 아래에서 돈다). USB 경로의 자식 프로세스 증명(`q_barrier`)보다는 약하다.
- R2: 차 화면 제거가 하나라도 지웠으면 `done`을 기록하고 잠금을 푼 뒤 USB와 같은 콜드 재부팅(`d_audio force_normal`, 실패 시 `reboot force_normal`)을 한다. 재부팅 뒤에는 화면이 토큰을 잊으므로, bridge가 없고 결과가 `done`이면 마지막 단계(Manager에서 core 제거) 안내를 계속 보여 준다. 확인 문구에 "차가 한 번 재부팅됩니다"를 넣었다.
- R3: `uilog.sh recovery_status`와 `recovery-lib.sh r_check`가 `stock-recovery-mode`를 보면 `stock-recovery-required`(복구 버튼 끔)를 낸다. 차 화면은 "순정 복구 USB(GEN5W-ACTION=stock-recover)를 다시 꽂으세요"로 안내한다(영문 포함).
- 시험: 수정 전 코드에서 실패하는 것을 확인한 새 시험은 integrated 1개(USB 제거의 서비스 확인 순서), uilog 2개(R3), installation-recovery 1개(R3)다. 차 화면 제거의 서비스 정지·재부팅 시험은 수정 전 코드로는 돌려 보지 않았다.
- 다른 세션 변경 마무리: `NEMESIS.sh`가 `services.sh`를 읽게 바뀌었는데 `tests/diagnostic_concurrency.py`는 그 파일을 복사하지 않아 매번 실패했다. 복사 목록에 넣었다.
- 전체 회귀(`tests/run.sh`): ALL TESTS PASSED.
- 확인 안 한 것: 차 화면 제거 후 콜드 재부팅을 실차에서 확인하지 않았다(`cold_reboot`와 같은 명령, VEHICLE-UNVERIFIED).

**다른 세션 4번(순정 무선 연결 뒤 끊김을 따라가지 않음): 유지.** `StockProjectionSession`은 ACTIVE를 끝 상태로 두어 그 Bluetooth 연결 동안 다시 요청하지 않는다. V039 PhoneProjection에는 사용자가 끊는 경로(`Wireless.DISCONNECT_PP`, `DISCONNECT_POPUP`)가 있다. 브리지가 보는 상태로는 사용자가 끊은 것과 연결이 끊긴 것을 구분할 수 없어서, 다시 요청하면 사용자의 선택을 거스를 수 있다. 다시 잇는 일은 순정(`ppRetryMax`, `connection_timeout`)과 휴대폰이 맡고, 브리지는 다음 Bluetooth 연결 때 요청한다. 순정이 실제로 다시 잇는지는 실차에서 확인되지 않았다.

**문제 없음으로 확인한 것**
- 순서: 설치는 모든 입력 패키지의 신원과 해시를 확인하고, 이전 패키지 전체 스냅샷을 만든 뒤에 처음 변경한다.
- 실패 처리: 실패하면 그 트랜잭션의 `attempt.*`만 제거하고 스냅샷에서 다시 설치한다.
- 잠금: `acquire`는 부팅별 가드와 죽은 잠금을 확인하고, 링크를 거부한다.
- NEMESIS.sh: 상태가 중단(`applying`/`removing`/`recovering`/`recovery-required`)이면 설치 요청을 순정 복구로 돌리고, 다음 동작을 USB에 남긴다. 순정 복구 뒤에는 같은 부팅에서 설치를 거부한다.
- 순정 복구: 이전 ZIP을 다시 설치하지 않는다. 마운트가 ro인지 따로 확인한 뒤에만 재부팅한다.
- `q_resume`: 순정 복구 뒤에는 서비스를 다시 켜지 않는다(`1:committed`).
- 차 화면 복구(`r_run`): core에 있는 검증 스크립트가 번들 해시를 확인한 뒤에만 실행하고, 같은 토큰은 다시 실행하지 않는다.

### 확인했고 문제 없는 것
- `CoreService` 종료 시 `Iap2SvcStopMain(listener)`: V039 `Iap2Service`에서 `removeListener`만 호출한다. iAP2 서비스나 CarPlay를 멈추지 않는다.
- iAP2 길안내 해석(`GuidanceParser`)·표시 상태(`GuidanceSession`): 필드 수·문자열 길이·배열 크기·값 범위를 모두 제한하고, 잘못된 입력은 화면을 지우는 쪽으로 처리한다. 확정 결함 없음(실제 iPhone 메시지로의 검증은 아님).
- Android Auto: 순정 `HKMC_GPM`이 계기판에 직접 쓴다. 이 프로젝트의 GPM 패치(`GpmUsbGuard`)는 저장 장치(USB 클래스 8·9)만 달린 USB 기기에서 Android Auto 시작을 막는 한 가지 일만 한다. 확정 결함 없음.
- Core의 Android Auto 보조 입력(방송·로컬 소켓): `signatureOrSystem` 권한과 uid(0·1000·자기) 검사가 있다. 저장소 안에는 이 입력을 보내는 쪽이 없어 평소에는 쓰이지 않는다.
- 설치·제거·원복 흐름: 다른 세션이 같은 날 `docs/logic-audit-2026-11-11.md`에서 점검했고 수정 중이어서 중복 점검하지 않았다(제거 경로의 서비스 정지 누락, 순정복구 중단 상태의 앱 버튼 안내 불일치 등).

## 확정된 문제

아래 P2–P5는 위 "수정 내역"에서 고쳤다. 기록은 발견 당시 그대로 둔다.

### P5(가장 중요). 순정 설정에서 무선 CarPlay나 자동 연결을 꺼도 V039 보조 경로가 연결을 시작함
- 조건: V039 중계 패키지가 설치되어 relay gate가 0일 때(`service.sh`가 `--ez relay_v039 true`로 호스트를 시작).
- 흐름: `PhoneProjectionAccess.inspect()` 101–107행은 꺼진 프로필도 `INVOKED`, 서비스 정상, `profileType = CarPlay(1)`, 대기 상태로 돌려준다. `StockProjectionSession.inspected()`는 249행에서 `observedProfileType`을 먼저 기록한 뒤 266–272행에서 `BLOCKED`로 멈춘다(순정 요청은 보내지 않음, 올바름). 그런데 `WirelessBridge.relayEligible()`(306–311행)은 `BLOCKED` 전체를 허용하고, `inspectRelayProjection()`의 시작 조건(339–341행)은 서비스 정상·대기 상태만 보고 프로필의 켜짐/자동 연결 값을 보지 않는다. 결과적으로 `relay.start()`가 호출되어 SPP → iAP2 → AP 켜기까지 진행한다.
- 실행 재현(scratchpad `repro/ReproP5.java`, 실제 `StockProjectionSession.java`와 `WirelessBridge`의 두 조건식을 그대로 옮김): `DISABLED: phase=BLOCKED stockRequests=0 relayEligible=true relayStart=true`, `AUTO_CONNECT_DISABLED`도 같음.
- 영향: 사용자가 그 휴대폰의 무선 연결을 꺼 둔 의사를 무시하고 차의 AP를 켜고 CarPlay 연결을 시도한다. 시험 공백: 이 조합을 다루는 시험이 없다.
- 고칠 방향(제안): 중계 허용을 "부트스트랩 실패·순정 요청 무응답" 같은 사유로 한정하고, 시작 직전의 새 관찰에서 `profileState == READY`를 요구한다.
- 같은 날 다른 세션의 `docs/logic-audit-2026-11-11.md` 2번 항목과 같은 내용이다. 이 문서는 실행 재현으로 그 판정을 확인했다.

### 다른 세션 점검과의 차이
- `logic-audit-2026-11-11.md` 3번(케이블 뺀 뒤 재시도 누락)을 그 문서는 P2 결함으로 분류했지만, Apple 지침이 케이블을 뺄 때 무선 CarPlay를 시작하지 말라고 하므로 CarPlay에 대해서는 결함이 아니다(아래 P1). 고치면 오히려 지침에 어긋난다.
- 같은 문서 4번(무선 성공 뒤 끊김 추적 중단)은 Apple 지침상 "휴대폰이 멀어져 끊기면 차가 빠른 재연결 → Bluetooth 재연결"을 해야 한다. 다만 무선 성공 뒤 재연결은 순정 PhoneProjection의 몫이고, 순정이 그 재연결을 하는지는 확인하지 못했다. 그래서 이 문서에서는 확정 결함으로 올리지 않는다.

### (재분류) P1. 유선 연결 뒤 케이블을 빼면 같은 Bluetooth 연결 동안 무선 요청이 다시 일어나지 않음
**판정 변경: CarPlay에 대해서는 결함이 아니다.** 아래 동작 자체는 코드와 실행으로 확정이지만, Apple 지침(위 WWDC 717)이 "USB를 뺄 때 무선 CarPlay를 시작하지 말라"고 명시하므로 이 동작은 지침과 일치한다. Android Auto는 공개 지침이 없어 판정하지 않는다. 시험이 이 동작을 고정하고 있지 않으므로, 의도라면 시험으로 고정해 두는 것이 좋다(제안, 결함 아님).
- 위치: `StockProjectionSession.environment()` 148–161행, `tick()` 170–171행, `candidate()` 128행, `BluetoothCandidateScan.offerCandidate()`.
- 흐름: 케이블 감지(`WirelessBridge.refreshWired`) → `environment(true, …)`가 `phase = CANCELLED`로 만들고 `candidate`는 그대로 둔다. 케이블을 빼면 `environment(false, …)`는 `if (!blocked) return;`으로 아무것도 하지 않는다. `tick()`은 `terminal()`(CANCELLED 포함)이면 바로 반환한다. 새 시도는 `candidate()`에 **다른** 주소가 들어오거나(`address.equals(candidate)`면 반환), `lost()`로 candidate가 null이 된 뒤에만 시작된다. Bluetooth가 끊기지 않으면 둘 다 일어나지 않는다.
- V039 보조 경로도 같은 이유로 시작되지 않는다. `WirelessBridge.relayEligible()`은 `BLOCKED` 또는 `FAILED`만 허용하고 `CANCELLED`는 제외한다.
- 결과: "케이블로 CarPlay를 쓰다가 뺀 뒤, 휴대폰 Bluetooth는 계속 연결된 상태"에서 브리지는 무선 연결을 다시 요청하지 않는다. 순정 PhoneProjection이 스스로 재연결하는지는 이 코드와 무관하며 확인되지 않았다.
- 시험 공백: `StockProjectionSessionTest`는 `environment(true, …)`만 시험하고, 이어서 `environment(false, …)` 뒤 재시도를 기대하는 시나리오가 없다.
- 실행 재현(scratchpad `repro/ReproP1.java`, 실제 `StockProjectionSession.java` 그대로 컴파일): 시작 → 유선 → 해제 → 120초 tick. 결과 `phase=CANCELLED candidate=true inspects=1 requests=0`. 같은 주소로 `candidate()`를 다시 불러도 `CANCELLED` 유지.

### P2. 한 번의 일시적 실패가 같은 Bluetooth 연결 전체의 시도를 끝냄
- 위치: `StockProjectionSession.inspected()` 242–246행(`fail("unavailable")`), `tick()`의 `terminal()` 조기 반환, 각종 `fail("timeout")`.
- 흐름: 점검 1회가 `SERVICE_UNAVAILABLE`, `INVOCATION`, 5초 점검 시한 초과 중 하나로 끝나면 `phase = FAILED`가 된다. 이후 `tick()`은 아무것도 하지 않으며, P1과 같은 이유로 Bluetooth가 끊겼다 다시 붙기 전까지 재점검·재요청이 없다.
- 실행 재현(`repro/ReproP2.java` A): `SERVICE_UNAVAILABLE` 1회 후 5분 tick → `phase=FAILED inspects=1 requests=0`.
- 확정 범위: "재시도가 없다"는 코드와 실행으로 확정. 실제 차에서 순정 서비스 조회가 일시적으로 실패하는 경우(예: 부팅 직후 서비스 미등록)가 있는지는 **미확인**이다. 다만 브리지는 `sys.boot_completed=1` 이후 시작하고, 휴대폰 Bluetooth는 그보다 먼저 붙을 수 있다.
- 참고(설계상 의도로 보이는 동작, 결함으로 분류하지 않음): 연결이 `ACTIVE`가 된 뒤 CarPlay 세션만 끊기고 Bluetooth가 유지되면, 같은 연결 세대에서는 다시 요청하지 않는다(`ReproP2` B: 5분 후 `requests=1`). `design.md`의 "같은 연결 세대에는 순정 요청을 한 번만" 원칙과 일치하고, Apple 지침의 "사용자가 직접 끊으면 재연결할 필요 없음"과도 맞는다.
- Apple 지침과의 관계: Apple은 차가 시동 뒤 사용자 조작 없이 자동으로 다시 연결하길 요구한다. P2가 실제로 일어나면(첫 점검이 일시 실패) 그 Bluetooth 연결 동안 자동 연결이 일어나지 않으므로 이 요구에 어긋난다. 단, 일시 실패가 실차에서 생기는지는 여전히 미확인이다.

### P3(낮음). 중계 전환 알림 수신기가 권한 없이 등록됨
- 위치: `WirelessBridge`의 `registerAction()`(97행)이 `RELAY_HANDOVER_REQUESTED/CONNECTED/DISCONNECTED`를 포함한 모든 동작을 `registerReceiver(events, filter, null, main)`로 등록한다. 권한 인자가 `null`이다.
- 결과: 차에 설치된 어떤 앱이든 이 브로드캐스트를 보낼 수 있다. `RELAY_HANDOVER_DISCONNECTED`를 보내면 진행 중인 중계 연결이 취소되고, `REQUESTED`를 보내면 `CARPLAY_HANDOVER` 단계에서 component 5 시작이 앞당겨진다. 다른 앱이 비밀번호를 얻거나 AP를 켜게 할 수는 없다(AP 켜기는 브로커의 uid 검사를 거침).
- 심각도: 낮음. 순정 차에는 제3자 앱 설치 경로가 사실상 없다. 고치려면 DiPO 패치가 보내는 쪽에 맞춰 서명 권한을 두거나, 송신자 확인이 가능한 방식으로 바꿔야 한다.

### P4(낮음). 중계용 점검 작업이 `Error`로 끝나면 중계 점검이 다시 시작되지 않음
- 위치: `WirelessBridge.inspectRelayProjection()` 314–345행. `relayInspectPending = true` 뒤 실행기 작업 안에서 `PhoneProjectionAccess.inspect()`가 `RuntimeException`이 아닌 `Error`(예: `NoClassDefFoundError`, `ExceptionInInitializerError`)를 던지면 `main.post(...)`에 닿지 못해 `relayInspectPending`이 영원히 `true`로 남는다. 이후 같은 프로세스에서는 중계 경로가 시작되지 않는다.
- `PhoneProjectionAccess`는 `SecurityException`·`RuntimeException`과 리플렉션 예외만 잡는다. 순정 메서드 안에서 난 `Error`는 `InvocationTargetException`으로 감싸져 잡히므로, 빠져나가는 것은 브리지 자신의 코드(클래스 초기화 등)에서 난 `Error`뿐이다.
- 같은 상황에서 순정 요청 경로(`inspect(generation, …)`)는 5초 점검 시한으로 `FAILED`가 되어 멈추지 않는다(P2와 같은 결과). 영구히 걸리는 것은 중계 경로뿐이다.
- 확정 범위: 코드 경로는 확정. V039에서 이런 `Error`가 실제로 나는지는 미확인(앞서 V039 API 대조에서는 없는 클래스·메서드가 없었다).

## 이어서 할 일
- core 길안내(CarPlay iAP2 RouteGuidance, Android Auto GPM 패치) 검토.
- 설치·원복 스크립트 흐름 전체 검토.
- P2를 실차에서 판정하려면 부팅 직후 차량 보고서에서 `path=stock` 점검 결과(`unavailable`/`timeout`)가 나오는지 확인한다.
