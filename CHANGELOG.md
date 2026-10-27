# 변경 내역

## v0.2.1

### 안드로이드 오토 한국 특화 6대 도로유형 아이콘 보정 (Sec 4-1)
- `ClusterIcon.refineManeuver` 추가: 안드로이드 오토의 단순 회전 enum을 도로명 텍스트 어휘 분석을 통해 한국 도로 환경 6대 특수 아이콘(지하차도·고가차도 진입/옆길, 터널, 요금소, 휴게소, 고속도로 IC/JC)으로 100% 자동 보정 승격
- `CoreService`의 TBT 브로드캐스트 및 로컬 소켓 리시버 전반에 보정 파이프라인 직결

### HUD 미디어/음악 곡명 OSD 일시 표출 (Sec 3-4)
- 음악 재생/곡 변경 브로드캐스트(`com.android.music.metachanged`, Spotify 등) 및 `kr.gen5w.action.MEDIA_TRACK` 수신 시 HUD 상단에 `[음악] 곡명 - 아티스트`를 3초간 일시 표출
- 3초 경과 후 기존 내비게이션 도로명 및 TBT 안내 텍스트로 자연스럽게 자동 복귀하는 비간섭 OSD 스케줄러 구현

### 안드로이드 오토 차선 가이드(Lane Guidance) HUD 표출 (Sec 3-2)
- `LaneFrame.encodeSimple` 구현: 차선 수, 추천 주행 차로, 차로별 진행 방향 데이터를 81바이트 순정 F1 클러스터 프레임으로 인코딩
- `kr.gen5w.action.AA_LANE` 인텐트 및 `gen5wkr.aa.tbt` 소켓의 `LANE:` 명령어 지원을 통해 순정 계기판 및 컴바이너 HUD에 추천 차선 그래픽 표출

### 고속도로 분기 모드 / 정밀 정션 뷰 (Highway Mode) (Sec 3-3)
- `HighwayFrame` 엔진 추가: IC, JC, 요금소, 휴게소 접근 시 순정 클러스터 고속도로 분기 모드 규격(`NavigationCluster.HighwayMode`) 자동 생성 및 `updateTPHighwayMode` 연동

### 콜드 부팅 시 핫스팟/Wi-Fi 핸드셰이크 지연 단축 및 자동 재시도 가속화 (Sec 4-2)
- `packages/hotspot-match/svc/match.sh`: 콜드 부팅 시 6초 고정 슬립 대신 1~2초 프로그레시브 능동 폴링으로 전환하여 Wi-Fi 서비스 기동 즉시 AP 준비 상태 감지
- `packages/wireless-bridge/scripts/service.sh`: 초기 부팅 재시도 백오프 상한을 30초에서 5초로 단축하여 스마트폰 무선 연결 지연 해소

### 유선 ↔ 무선 전환 (Handoff)의 매끄러운 자동 천이 (Sec 4-3)
- `WirelessBridge`에 `android.hardware.usb.action.USB_STATE` 리시버 추가: USB 케이블 탈착 즉시 0초 단위 감지
- USB 분리 시 즉시 RFCOMM 블루투스 스캔 및 무선 세션 복구 트리거(`scan()`, `session.tick()`)
- 유선 연결 감지 대상에 Apple(`0x05ac`) 외 Android Auto AOA(`0x18d1`) 추가로 유선 연결 시 충돌 없는 양보 보장

### USB Wi-Fi 외장 동글 지원 (동글형 배포판 통합) (Sec 3-1)
- `tools/integrated/build.py`에 `--variant dongle` 빌드 옵션 통합: 빌드 시 `gen5w.kr.dongle.zip` 자동 패키징 및 USB 통합 설치본 구성 지원
- `tools/integrated/common.sh`에서 `VARIANT=dongle` 및 `BACKEND=dongle` 런타임 수명주기, 드라이버 모듈 백업/원복 완벽 지원

### 타 차종 바이너리 레시피 및 ccNC 플랫폼 비교 분석 (Sec 3-5)
- K5 DL3 HEV, EV6, 아이오닉 5(NE EV) 등 Gen5W 타 차종 포팅 구조, 체크섬 및 ProGuard 오프셋 매핑 분석 문서화 (`docs/porting.md`)
- 차세대 ccNC (Android Automotive OS 10/12, AAOS 표준 계기판 서비스) 아키텍처 및 Gen5W와의 차이점 정리

---

## v0.2.0

### 안드로이드 오토(Android Auto) 순정 계기판·HUD TBT 연동 (P3 완료)
- 스마트폰에 별도 보조 앱 설치 없이 순정 네이티브 프로젝션 규격(NavigationStatusService)을 통한 TBT 연동
- 순정 Google Projection 모듈(`/system/app/HKMC_GPM.odex`)의 `stepofspec == 999` 분기를 `gpm-patch-v039`로 우회하여 순정 `GpmNaviTBTManager` 활성화
- Google 지도, 티맵, 네이버 지도, 카카오내비의 회전 아이콘, 2nd TBT 및 남은 거리를 순정 계기판과 HUD에 직결 표출
- `CoreService`에 안드로이드 오토 보조 브로드캐스트(`kr.gen5w.action.AA_TBT`) 및 로컬 추상 소켓(`gen5wkr.aa.tbt`) 인터페이스 추가

### 2nd TBT(다음 연속 회전 안내) 지원 (P2 완료)
- `GuidanceSession`에서 차기 회전(current[1])을 파싱하여 2nd TBT 아이콘 생성
- `NavigationCluster.updateTBTInfo`의 2번째 및 6번째 파라미터(`sideStreet`, `combiSideStreet`)에 2차 회전 아이콘 코드 전달
- 계기판 및 컴바이너 HUD의 2차 분기 안내 슬롯 지원

### 6대 도로 유형 매핑 및 내비 3사(네이버·티맵·카카오) 100% 매핑 고도화
- 지하차도, 고가차도, 터널, 요금소(TG), 휴게소/졸음쉼터, 고속도로 IC/JC 어휘 전수 지원
- 네이버 지도 공백 분리형, 티맵 붙여쓰기형, 카카오내비 방향 지시형 어휘 및 축약어(`TG`, `IC`, `JC`) 완벽 대응
- 일반 교차로 회전과 고속도로 램프 진입 간의 키워드 충돌 방지 로직 적용
- `Maneuver.appSource` 주입을 통한 앱별 커스텀 매핑 파이프라인 구축

### 안전 및 안정성 강화
- `HKMC_GPM.odex` 원본을 `/system/etc/gen5w-kr-backup/bridge/gpmoriginal` 및 `/data/nemesis/backup/gen5w.kr.bridge/gpmoriginal`에 영구 보존
- 원자적 교체(`mv`), 언인스톨 시 원본 100% 복원, 비정상 중단 시 자동 롤백 라이프사이클 구현
- 순정 안전운전 안내 모드(SOUND_ON, opcode 0xfa5) 연동으로 과속/카메라 경고와 HUD TBT 동시 표출 유지
- 회전교차로 미확인 각도 시 안전을 위한 클리어 처리 보장

## v0.1.2

- 꺼진 Wi-Fi를 없는 장치로 오판하지 않도록 감지와 일시 활성화·복원 처리 수정
- 기본형에 지원 사양의 순정 안내 타이머 10초→3초 적용, 완전 생략 기능은 로컬 전용으로 분리
- 일반 핫스팟 설정을 보존하고 CarPlay 모드에서 별도 접속 정보를 선택
- 지원 원본·WPA2·재부팅 완료를 확인한 뒤 무선 AP 시작
- 핫스팟 실행 경로 수정, 부팅 시 자동 설정 덮어쓰기 제거
- HUD 순정 경고 API 확인 상태 표시, 실제 카메라 정보 표시는 미확인
- USB 동글 드라이버 재현 빌드 도구 추가, 차량 Wi-Fi 연동은 개발 중

## v0.1.1

- 순정 내비 경로 안내 중 CarPlay HUD 출력·지우기·재시도 보류
- 순정 안내 종료 후 최신 CarPlay 안내 복귀, 조회 실패 시 순정 우선
- 결과 문서에 HUD 최근 출력 상태 표시

- 미지원 기능을 제외하고 지원 기능만 자동 설치
- 무선 변경을 원복하고 유선 HUD·독립 기능을 유지하는 유선 전용 전환 추가

- 차량 셸에서 무선 기능을 잘못 판정할 수 있는 검사식 수정
- 실행 초기에 실패해도 USB에 실행 상태 기록
- 차량에 없는 dirname 명령 의존 제거

- 설치·사용·지원 요청 안내 정리
- 현재 코드에 맞춰 설계·설치·검증 문서 갱신
- 문서 목록과 공개 전 확인 사항 추가

## v0.1.0

- 기본형과 시동 안내 생략형 배포
- 무선 연결, 핫스팟 정보 맞춤, CarPlay HUD 길안내
- 기존 설치 이관과 자동 복구
- 기능별 적용 결과와 진단 로그 생성
- 한국 내수용 차종 지원 요청과 GitHub Sponsors 연결
