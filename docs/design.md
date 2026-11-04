# 구조

대상은 한국 내수용 현대·기아·제네시스 Android Gen5W입니다. 기준 분석 자료는 코나 OSHEV V035/V039이며 Android 4.4.2, Dalvik 환경을 사용합니다.

## 구성

| 구성 | 역할 |
|---|---|
| wireless | 순정 무선 연결·핫스팟 기능 선언과 설정 |
| audio | 알려진 원본의 AAC·Opus 형식 알림 수정 |
| bridge | 순정 PhoneProjection에 무선 CarPlay 연결을 요청하고 결과 상태 관찰 |
| core | CarPlay 및 Android Auto 길안내 수신과 계기판·HUD 출력 |
| timer | 순정 조건 통과 시 시동 주의 안내를 버튼 활성화 즉시 닫는 서비스 |
| bluelink | 블루링크 미가입 차의 월간 가입 안내 다시 보기 시각을 2100년으로 유지 |
| dongle | 동글형 전용, `bcmdhd.ko` 자리에 USB 동글 연결용 대리 모듈 |

제조사 구현은 배포하지 않습니다. 원본 파일 전체 해시와 의존 파일 조합이 맞을 때만 수정하며, 원본은 기기 안에 보관합니다.

## 무선 연결

bridge는 연결된 Bluetooth 장치를 확인한 뒤 V039 순정 PhoneProjection API에 연결을 요청합니다. 자체 RFCOMM·iAP2·핫스팟 연결 경로는 실행하지 않습니다. 순정 서비스의 접근 권한이 없거나 연결이 진행되지 않으면 직접 연결로 우회하지 않고 실패를 기록합니다.

연결에는 세대 번호를 부여해 늦은 작업이 새 연결 상태를 덮지 않게 합니다. 같은 연결 세대에는 순정 요청을 한 번만 보내고, 완료는 순정 PhoneProjection의 연결 상태로만 판정합니다. USB 연결·Bluetooth 종료·서비스 종료 때 대기를 취소합니다.

bridge는 핫스팟 SSID·암호를 읽거나 수정하지 않습니다. 순정 PhoneProjection이 저장된 접속 정보를 AP 시작과 CarPlay 연결에 일치시켜 쓰는지는 실차 확인 전이며, SSID·암호는 로그나 보고서에 기록하지 않습니다.

## 길안내

CarPlay 길안내는 `core`가 `com.remote.service.IAP2SERVICE`에 별도 이름 `gen5wkr.core`로 등록합니다. 순정 소비자의 등록을 대체하지 않습니다. 등록된 안내 component를 조회하고 `Iap2SvcStartRouteGuidanceUpdate`를 명시적으로 요청합니다. 알림 `0x78/0x79/0x7a`를 상태·회전·차선으로 처리하며, 6대 도로 유형(지하차도·고가차도·터널·요금소·휴게소·IC/JC) 전수 어휘 매핑 엔진을 통해 순정 심볼 코드로 변환합니다.

Android Auto 길안내는 순정 Google Projection 모듈(`HKMC_GPM.odex`)의 `stepofspec == 999` 분기를 `gpm-patch`로 우회하여, Google 표준 네비게이션 채널(`NavigationStatusService`)과 순정 `GpmNaviTBTManager`를 활성화하도록 구성합니다. 사용자 스마트폰에 별도 앱을 설치하지 않는 경로지만, Google 지도·티맵·네이버 지도·카카오내비의 실제 TBT 수신과 차량 표시는 앱·운영체제별 실차 검증 전까지 확정하지 않습니다.

출력은 순정 `NavigationCluster`의 `updateTPTurnListNew`, `updateLaneInfo`, `updateTBTInfo`를 사용합니다. 2nd TBT(차기 회전 아이콘)는 `updateTPTurnListNew`의 두 번째 슬롯과 `updateTBTInfo`의 `sideStreet`에 전달합니다. `combiSideStreet`는 V039의 0~4 범위에 맞춰 0을 사용합니다. 출력이 실패하면 최신 정보나 지움 요청을 다시 보냅니다. 자체 CAN 프레임은 만들지 않습니다. 메시지 필드와 프레임 규격은 [iAP2](iap2-fields.md), [HUD](hud.md)를 참고하세요.

## 시동 안내

기본형은 SystemUI를 바꾸지 않고 서비스(`gen5w.kr.timer`)로 확인 버튼이 활성화되자마자 자동 전환합니다. 버튼을 활성화하는 순정 `enableScreen()`이 끝에서 타이머 판단을 하며 상태 줄을 남기므로, 그 줄이 순정 조건을 통과하면 바로 닫습니다(운전자 프로필 미선택 `mInitDriverIdx : -1`은 직접 거부). SystemUI가 시스템 로그에 남기는 자기 타이머 판단(`mScreenEnabled : …` 상태 줄, 실패 줄, 언어 버튼, 확인 줄)을 따라가서, 순정 조건을 통과했고 취소되지 않았을 때만 즉시 순정 닫기 요청(`CLOSE_CONSENTSCREEN_FORCE`, 순정 타이머와 같은 `confirm()` 실행)을 보냅니다. 확인된 순정 SystemUI(V039·V035)에서만 동작하고, 로그 형식이 다르거나 서비스가 멈추면 순정 10초 타이머가 그대로 적용됩니다.

## 설치와 복구

설치기는 파일·API·하드웨어를 검사하고, 이전 상태를 백업한 뒤 적용합니다. 미지원 기능은 제외하고 나머지를 설치합니다. 무선을 쓸 수 없으면 무선 변경을 원복하고 지원되는 유선 HUD·주의 안내 타이머을 설치합니다. 실제 적용 오류는 먼저 원복합니다. 원복 실패나 설치 파일 손상은 그대로 중단합니다.

결과는 USB의 `GEN5W-REPORT`에 남깁니다. [설치 구조](integrated.md), [기능 범위](completion-scope.md), [검증 범위](validation.md)를 참고하세요.
