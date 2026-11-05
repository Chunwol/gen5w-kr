# 블루투스 중계 방식 무선 CarPlay: 조사 결과와 진행 상태 (2026-11-05)

상태: **중단** (일부만 구현, 실차 미검증). 다음에 이어서 볼 사람을 위한 기록이다.

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
