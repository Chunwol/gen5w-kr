# 초기판 누락 및 Android Auto 비교 감사 — 2026-11-24

현재 비교 대상은 F:의 0.3.86(a8540d1e…)과 현 작업 소스다. 초기판은 kona_v6_all_in_one의 wireless.carplay.aa.zip 및 leafia_reference/참고용이다. 초기판과 현재의 완전한 기능 동등성은 확인되지 않았으며, 아래는 파일 존재가 아닌 실행 경로 차이를 조사한 결과다.

## 확인된 차이

| 항목 | 초기판 | 현재 | 판정 |
|---|---|---|---|
| 무선 CP/AA 기능 선언 | 두 XML 및 지역 featurexml 변경 | candidate/prepare가 포함·적용 | 대응 경로 있음 |
| AA Bluetooth 초기 협상 | 순정 WPP/AA RFCOMM 이용 | 순정 경로와 PhoneProjection 타입 2 요청 유지 | 순정 V039 Bluetooth에 AA UUID/수신 서버 확인; 실제 연결은 미검증 |
| CarPlay Bluetooth/iAP2 | DiPO/Iap2 재구성 | structural patch + runtime relay | 구현 방식 변경; 초기판 바이너리와 동등하다는 의미 아님 |
| CarPlay 음악 102 | AAC/PCM 광고·선택 | 0.3.86에서 광고·선택 추가 | 앞서 찾은 누락 보완 |
| 별도 AAC/Opus converter | Utils stub일 때만 libev6aac 설치 | 검증한 V039 native Utils 사용 | 해당 V039에서 누락 아님; 타 장치의 stub fallback은 현재 미지원 |
| AA 기본 TBT | GPM 재구성 | stepofspec 분기 우회로 순정 GpmNaviTBTManager 활성화 | 실제 V039 ODEX recipe 검사 통과 |
| AA 현대식 안내 확장 | native libautoreceiver patch + GPM bridge | 미적용 | **확인된 기능 누락**; 아래 상세 |
| AA 보조 안내 수신 | 초기판 GPM/native 브리지 연결 | Core의 gen5wkr.aa.tbt 텍스트 listener와 보조 broadcast | 현재 bundle에 자체 AA 텍스트 생산자를 찾지 못함; native GPM 기본 출력과 구분 필요 |
| 네트워크 ADB 충돌 회피 | adb_net_fix/restore로 두 persist 속성 이관·복원 | portable에 대응 처리 없음 | **조건부 누락**; enable=1인 차량에 영향 가능, 현재 차량 원인으로 확정 불가 |
| US/Canada 설정 메뉴 | 선택적 BtSettings patch | 동일 패치 없음; DiPO split 설정 query만 보완 | 공용 메뉴 접근성의 잔여 차이. 코나 INFO 활성화 수정과 별개 |
| Wi-Fi client/P2P | client는 선택, P2P 편집 함수는 있으나 slim 적용 경로에서 호출 안 함 | client/P2P 전역 변경 안 함 | 단순 함수/파일 부재를 누락으로 계산하지 않음 |
| 네트워크·AA 진단 | 기존 kit에 충돌 관찰 있음 | route/GPM/ADB 개별값 수집 없음 | 이번 로컬 수정으로 보완 및 회귀 PASS; USB는 아직 이전 파일 |

## AA 네이티브 확장: 원본 대조 결과

V039 libautoreceiver_infobank.so MD5는 48ee793af8b86052503b8c952b034731로 초기판 common delta의 입력과 일치한다. 원본은 읽기만 하고 delta를 private 디렉터리에 재구성한 후 결과 MD5를 검증했다. 전체 파일 또는 OEM 바이트는 이 문서/배포물에 넣지 않는다.

- Controller::sendVersionRequest의 0xb1a2e: 초기판은 minor 4를 6으로 변경(1.4 → 1.6).
- NavigationStatusEndpoint::routeMessage의 0xb6818: 초기판은 기존 미처리 경로에서 추가 코드로 분기한다. 새 handler 0x1c490c는 message 0x8006/0x8007을 구분한다.
- NavigationStatus_NavigationStatusEnum_IsValid(0x144efa): 초기판은 상태 3까지 허용한다. 현재 원본은 2까지다.
- private 재구성 코드에 navbridge1 및 S/P+길이+hex 전달이 확인된다. 로컬 HMG-API ProjectionHooks.navigationDump도 같은 전달 형식을 해석한다.
- 현재 tools/iap2/gpm_patch.py와 portable dex patch는 GPM 초기화 조건을 고칠 뿐, 위 native 프로토콜·메시지 처리를 추가하지 않는다. 따라서 basic TBT 활성화만으로 초기판의 최신 메시지/차선/다음 회전 확장을 복원했다고 표현하면 안 된다.
- **버전 숫자만 1.6으로 올려서는 안 된다.** 메시지 파서·GPM/Core 전달·HUD 출력·상태 3 처리·종료/재탐색 지우기를 한 세트로 구현하고 합성 프레임/원본 ARM 실행/콜드부팅으로 검증해야 한다. 구형 안내를 보내던 전화가 새 형식으로 전환되면 오히려 출력이 사라질 수 있다.

## 외부 구현에서 확인한 개선 방향

외부 프로젝트의 구현/작성자 보고를 확인한 것이며, 이를 코나에서 성공한 결과로 간주하지 않는다. 소스는 실행하거나 제품에 복사하지 않았다.

1. [WirelessAndroidAutoDongle Bluetooth](https://github.com/nisargjhaveri/WirelessAndroidAutoDongle/blob/main/aa_wireless_dongle/package/aawg/src/bluetoothHandler.cpp): AA UUID 서버와 연결 재시도. 현재 V039에도 같은 UUID가 있으므로 중복 서버보다 기존 WPP 경로의 성공/실패 경계를 관찰한다.
2. [aa-proxy-rs](https://github.com/aa-proxy/aa-proxy-rs): 연결 복구와 정지 감지. 현재 StockProjectionSession은 요청 이후 terminal FAILED에서 같은 연결의 재시도가 없다. fresh idle 상태, 기존 세션 종료, 사용자 해제/다른 기기 점유 확인을 요구하는 제한적 재시도 설계가 개선 후보다.
3. [Open Headunit wireless](https://github.com/andreknieriem/open-headunit/wiki/Wireless): native Bluetooth→Wi-Fi 경로와 helper/server 모드를 구분하고 AA 17.4 이후 legacy helper 제한을 명시한다. 현재 OEM 경로를 helper로 교체할 근거는 없다.
4. [oem-aa-mod](https://github.com/VitaliyKurokhtin/oem-aa-mod): Mazda 구현도 protocol 1.6 광고와 rich navigation parser/relay를 함께 사용한다. 플랫폼이 다르므로 바이너리/주소를 가져오지 않고 구현 결합 조건만 참고한다.
5. [AA navigation protocol reference](https://github.com/mrmees/open-android-auto/blob/main/docs/channels/nav.md): 0x8006 rich notification, 0x8007 distance 메시지 구조와 legacy 경로 구분. 초기판에서 발견한 누락과 부합한다.
6. [HMG-API hook points](https://github.com/Open-HMG/HMG-API/blob/main/docs/hook-points.md): GPM native callback 및 차종별 매핑을 공개한다. 현재 소스 비교의 참조이며 지도 목록은 해당 차량 전체 기능 성공 증명이 아니다.

## 이번 검증과 변경

- tests/gpm_control.py --stock <V039 HKMC_GPM.odex>: 실제 원본 recipe/범위/체크섬 PASS.
- tests/portable_patcher.py: 5종 differential, truncation 25, metadata/layout 20, 미래/미지원 형태 32 거부 PASS.
- tests/gpm_usb_guard_runtime.py: 전체 케이스 PASS.
- tests/portable_diagnostics.sh: route/GPM/ADB 수집 요구가 기존 코드에서 실패(RED), 추가 후 전체 PASS(GREEN). 로컬 read-only 진단만 수정. 네트워크·오디오·BT 설정은 변경하지 않는다.
- USB 0.3.86과 이번 로컬 진단 소스는 다르다. 이 감사에서는 USB를 갱신하지 않았다. AA native 확장과 ADB 이관은 **아직 수정하지 않았다**.

## 우선순위

1. AA 1.6 + 0x8006/0x8007 parser/relay/state 3/수신 생산자 연결을 한 묶음으로 복원·검증.
2. ADB enable=1과 실제 eth0/AP 경로 충돌을 확인한 뒤, 사용자 기존 값/업데이트/실패/독립 복구까지 포함하는 소유권 기반 이관 설계. 무조건 5555 열기나 eth0 내리기는 하지 않는다.
3. OEM 재시도/다른 기기 점유/사용자 수동해제와 충돌하지 않는 AA 한정 재연결과 실제 데이터 정지 관찰.
4. 모델별 설정 메뉴에서 분할화면 선택 접근 확인; 선택적 메뉴 패치는 현재 INFO 렌더링 조건 수정과 별개다.

CarPlay 수정 후 실제 차량 소리·INFO·HUD, AA 연결/소리/마이크/안내, 신규 콜드부팅은 이번 감사에서 검증하지 않았다.


## 후속 구현: 0.3.87 준비

앞의 표와 미적용 판단은 구현 전 감사 시점의 기록이다. 후속 변경으로 다음을 복원했다.

- Hash가 확인된 V039 native 원본에만 AA 1.6, 현대식 0x8006/0x8007 생산자, 상태 3 처리를 함께 적용한다. 원본의 공유 enum 검증 함수를 바꾸지 않고 navigation 호출부만 분리한다. OEM 실행 바이트를 배포물에 넣지 않는다.
- Core에 bounded GAN1 프레임, protobuf 해석, 회전·거리·차선 snapshot을 연결했다. 재탐색·종료·소유권 변경 때 오래된 안내를 지우며, 확인되지 않은 maneuver는 추정하지 않는다.
- 설치된 Core APK의 실제 바이트 일치를 시스템 적용 전에 확인하고 앱 소스 digest를 검증해 오래된 입력 재사용을 차단한다.
- 레거시 네트워크 ADB가 enable=1인 경우만 소유권 journal로 이관한다. 기존 사용자 port, 외부 변경, 실패·제거·독립 USB 복원을 보존한다. 현재 인터페이스나 라우팅을 바꾸지 않는다.
- 독립 복구와 모든 system allowlist에 native 원본 및 ADB journal 복원을 포함했다.

ARM 두 ASLR 주소의 실제 hook 실행, syscall/peer UID/길이/부분 전송, protobuf·상태 JVM, 설치 사전검사, 원본 준비 및 독립 복구 fixture를 검증했다. 실제 Android APK 설치와 최종 USB 결과는 릴리스 세션 기록에서 별도로 확정한다. 실제 전화 AA/CarPlay, 차량 오디오·마이크·INFO·HUD는 여전히 실차 확인 대상이다. 위 자동 재연결과 지역별 선택적 메뉴 패치의 잔여 차이를 완료로 바꾸지 않는다.
