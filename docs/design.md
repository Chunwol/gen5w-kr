# 구조

대상은 한국 내수용 현대·기아·제네시스 Android Gen5W입니다. 기준 분석 자료는 코나 OSHEV V035/V039이며 Android 4.4.2, Dalvik 환경을 사용합니다.

## 구성

| 구성 | 역할 |
|---|---|
| wireless | 순정 무선 연결·핫스팟 기능 선언과 설정 |
| audio | 알려진 원본의 AAC·Opus 형식 알림 수정 |
| hotspot | 실제 핫스팟과 CarPlay 접속 정보 일치 |
| bridge | Bluetooth 연결과 순정 iAP2·CarPlay 및 Android Auto TBT 서비스 연결 |
| core | CarPlay 및 Android Auto 길안내 수신과 계기판·HUD 출력 |
| consent | 선택한 버전에서 시동 동의 안내 생략 |

제조사 구현은 배포하지 않습니다. 원본 파일 전체 해시와 의존 파일 조합이 맞을 때만 수정하며, 원본은 기기 안에 보관합니다.

## 무선 연결

bridge는 연결된 휴대폰이 광고한 UUID를 확인해 RFCOMM을 엽니다. 인증과 투영은 순정 iAP2·DiPO 서비스를 사용합니다. 자체 제어부는 정확히 일치하는 원본의 제한된 메서드에만 적용합니다.

연결에는 세대 번호를 부여해 늦은 작업이 새 연결을 덮지 않게 합니다. 실패 시 대기 후 재시도하며, 다른 휴대폰의 주기적 발견으로 대기 시간을 초기화하지 않습니다. USB 장치·순정 USB 모드·CarPlay 알림으로 유선 연결을 감지하면 무선 시작을 멈춥니다.

핫스팟 이름과 키는 차량의 Connectivity 값을 사용합니다. 키는 메모리에서만 다루고 로그나 보고서에는 기록하지 않습니다.

## 길안내

CarPlay 길안내는 `core`가 `com.remote.service.IAP2SERVICE`에 별도 이름 `gen5wkr.core`로 등록합니다. 순정 소비자의 등록을 대체하지 않습니다. 등록된 안내 component를 조회하고 `Iap2SvcStartRouteGuidanceUpdate`를 명시적으로 요청합니다. 알림 `0x78/0x79/0x7a`를 상태·회전·차선으로 처리하며, 6대 도로 유형(지하차도·고가차도·터널·요금소·휴게소·IC/JC) 전수 어휘 매핑 엔진을 통해 순정 심볼 코드로 변환합니다.

Android Auto 길안내는 순정 Google Projection 모듈(`HKMC_GPM.odex`)의 `stepofspec == 999` 분기를 `gpm-patch`로 우회하여, Google 표준 네비게이션 채널(`NavigationStatusService`)과 순정 `GpmNaviTBTManager`를 차량 네이티브 수준에서 활성화합니다. 이를 통해 사용자 스마트폰에 별도 앱을 설치하지 않고도 Google 지도·티맵·네이버 지도·카카오내비의 TBT 정보가 전달됩니다.

출력은 순정 `NavigationCluster`의 `updateTPTurnListNew`, `updateLaneInfo`, `updateTBTInfo`를 사용합니다. 2nd TBT(차기 회전 아이콘)는 `updateTPTurnListNew`의 두 번째 슬롯과 `updateTBTInfo`의 `sideStreet`에 전달합니다. `combiSideStreet`는 V039의 0~4 범위에 맞춰 0을 사용합니다. 출력이 실패하면 최신 정보나 지움 요청을 다시 보냅니다. 자체 CAN 프레임은 만들지 않습니다. 메시지 필드와 프레임 규격은 [iAP2](iap2-fields.md), [HUD](hud.md)를 참고하세요.

## 시동 안내

기본형은 등록된 SystemUI APK/ODEX 조합에서 순정 자동 전환 타이머 상수만 10초에서 3초로 바꿉니다. 순정 표시·안전 조건·확인 처리는 유지합니다. 개인용으로 설치했던 이전 안내 설정은 소유권을 확인한 뒤 복원합니다.

## 설치와 복구

설치기는 파일·API·하드웨어를 검사하고, 이전 상태를 백업한 뒤 적용합니다. 미지원 기능은 제외하고 나머지를 설치합니다. 무선을 쓸 수 없으면 무선 변경을 원복하고 지원되는 유선 HUD·주의 안내 타이머을 설치합니다. 실제 적용 오류는 먼저 원복합니다. 원복 실패나 설치 파일 손상은 그대로 중단합니다.

결과는 USB의 `GEN5W-REPORT`에 남깁니다. [설치 구조](integrated.md), [기능 범위](completion-scope.md), [검증 범위](validation.md)를 참고하세요.
