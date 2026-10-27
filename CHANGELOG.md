# 변경 내역

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
