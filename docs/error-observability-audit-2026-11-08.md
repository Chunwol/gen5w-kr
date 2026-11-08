# 오류 처리·로그 보강 감사

대상: 3dc8a7a 이후 로컬 변경. 실차 재설치·원래 remount errno·연결 실패 팝업은
이번 코드 시험으로 확정하지 않는다. 상태: 구현 후 최종 검증/독립 리뷰 진행 중.

## 기록 계약

- shell: `ERR attempt=... revision=... boot=... uptime=... module=... stage=... operation=... result=... rc=... reason=...`.
- Java: `Gen5wDiag ERR code=... exception=... reason=... generation=... monotonicMs=...`.
- Java 시간은 프로세스 단조 시계이며 수집 헤더의 boot/uptime과 함께 해석한다.
- 실패 명령의 stdout은 기존 파서에 그대로 전달한다. stderr는 고정 크기로 읽어
  permission/busy/missing/no-space/read-only/io/timeout/missing-class/linkage/socket-bind로
  분류하며 원시 인수·메시지를 영구 저장하지 않는다. 분류 불가는 unknown/redacted이다.
- 중요한 명령은 시작/종료가 각각 남는다. 시작만 있으면 정지·중단 가능성이지,
  성공 또는 timeout 확정이 아니다. 정상 checksum/inspect probe는 불필요하게 기록하지 않는다.
- preinstall의 명시적 미지원77은 skipped로 기록하고 원래 반환 코드는 유지한다.

## 저장·보존

- private shell journal: root-owned `gen5wkr.errors`, 64KiB 이하4세그먼트.
  고정14모듈 × 8슬롯의 최초 실패 레코드만 별도로 보존해 다른 모듈·원복이 덮지 않는다.
  레코드는 고정 토큰 필드이고 1KiB 이하; 임의 모듈명/파일명은 받지 않는다.
- 기록 잠금은 대기하지 않는다. boot/PID가 확인되는 죽은 writer 잠금은 복구하며,
  소유권을 모르는 잠금은 삭제하지 않고 stderr로 persistence=busy를 알린다.
- USB REPORT/HISTORY는 소유 표식이 있는 최근8개 슬롯만 재사용한다. 알 수 없는
  파일·심볼릭 링크가 있으면 보존하고 새 기록 준비를 거부한다. 재귀 삭제하지 않는다.
- EXEC/DIAG 스트림은 각64KiB 이하4세그먼트. 긴 줄·민감 문자열은 표시를 남기고
  잘라내거나 가린다. 이전 형식의 매우 큰 보고서를 옮길 때도 크기를 제한한다.
- report writer는 쓰기 실패 후에도 입력을 소모해 실제 작업을 SIGPIPE로 끊지 않는다.
  작업 rc와 report writer rc를 별도로 보며 쓰기 실패를 저장 완료로 표시하지 않는다.
- Android 준비 전 entry 검사는 private 저장을 하지 않는다. `ENTRY_STATUS.txt`와
  STARTUP의 operation_exit/report_exit가 부팅 조회·실제 작업·보고서 쓰기 실패를 분리한다.
- check/diag/status의 읽기 전용 계약은 유지한다. private journal을 쓰지 않고 USB에
  수집 상태를 남긴다. 설치/서비스에서는 USB가 없어도 private 오류 기록을 시도한다.
- 원시 SSID/키/토큰/MAC/VIN/폰 이름/목적지/미디어 내용은 진단 대상으로 삼지 않는다.
  자동 전송은 없다. 외부 명령 stdout을 사용하는 기존 파서는 별도 필터를 유지한다.

## 경계별 판정

| 영역 | 판정 | 조치/근거 |
|---|---|---|
| 통합 설치/업데이트 gate | changed | 패키지ID·hook 단계·반환 코드, 누락 metadata/unsafe path/missing hook 기록 |
| snapshot/무결성 | changed | zipstore/pkg-info/digest 실패를 분리하고 stdout 파싱 유지 |
| 제거/원복 | changed | uninstall/force 경계 및 이전 패키지 재설치 결과 분리, 최초 실패 불변 |
| reboot | changed | d_audio/force_normal/fallback 명령 단계 기록; 실제 재부팅 성공과 구분 |
| 무선 선언/원복 | changed | rw/ro errno 분류; legacy install log 크기 제한; 기존 byte journal 유지 |
| 오디오 패치/원복 | changed | rw/ro 원문 폐기 대신 구조화 진단; 일반 오류를 busy로 단정하던 문구 수정 |
| 브리지 패치/원복 | changed | rw/ro 진단; 기존 exact APK/ODEX/relay 식별 및 복구 조건 유지 |
| bootguard | changed | rw/ro 복구 경계 기록; 기존 restore_one 검증·실패 시 recovery-required 유지 |
| 동글 | changed | mount 단계 분리; 기존 드라이버 log 제한·로드 거부/재시도 상태 유지 |
| 핫스팟 | changed | 승인된 busy 재시도/검증 경고, rw 복구 진단, durable helper 복사 |
| AP broker supervisor | changed | 실제 child PID 보존한 FIFO stderr 분류, 종료 rc와 재시도 구분; 저장 불가 명시 |
| AP Java/라디오 rollback | changed | ensure/stop/executor/transition/rollback/profile 복원/boot marker 실패 코드 |
| BT/iAP2 | changed | connect/start/write/read/stop 실패 예외·generation 기록, 결과/cleanup 계약 유지 |
| HUD provider/IPC | changed | timeout/worker/query/socket 오류 분리; 늦은 결과를 허용하는 변경 없음 |
| HUD 출력/상태 저장 | changed | 출력 실패 및 owner/config/heartbeat 쓰기 원인, 반복 로그 제한 |
| UI 요청/설정/읽기 | changed | rename/write/permission/settings 실패 코드, 실패 결과와 기존 파일 유지 |
| ADB | changed | 포트 설정/daemon stop/start rc; 기존 health 및 one-shot ack 유지 |
| 타이머 | changed | close broadcast 경계 rc/원인, 기존 수신 상태·정상 미지원/거부 이유 유지 |
| 블루링크 | changed | prefs 교체·권한 설정 경계, 기존 reminder 원본/지원 버전 검증 유지 |
| USB 주행 로그 | audited | mount/FUSE/공간/쓰기/EOF/탈착별 고정 사유와 상태 변경 로그 및 토스트 존재; diag 수집 시험 유지 |
| 진단·체크 수집 | changed | 중요 kernel/logcat/service/package/property 수집 실패를 empty와 구분; 최초 실패 journal 포함 |
| 패키지 배포 구성 | changed | standalone helper를 각 패키지에 포함하고 canonical byte identity 검사; NEMESIS entry 중복 템플릿 제거 |

## 의도적으로 조용히 유지한 경로

1. 지원 원본/후보 verifier 탐색의 개별 불일치: 여러 후보 중 하나를 고르는 정상 probe다.
   최종 미지원·무결성 실패·preinstall rc는 상위 gate에 남는다. 모든 probe를 장애로 찍지 않는다.
2. symlink/잘못된 UI 요청/미등록 기능 입력/파서 validation 거부: 고정 허용값만 수용하는
   보안 경계다. 공격자가 통제하는 경로·본문을 오류 원문으로 복사하지 않는다.
3. 사용하지 않는 OEM API·UI 리소스 fallback: StockSkin/PhoneProjection 후보 선택,
   지원 변형 판별은 정상 대안 선택이다. terminal 상태는 기존 Result/UNKNOWN/UNAVAILABLE로 남는다.
4. socket close/unregister/취소 reader EOF/짧은 socket poll timeout: 정상 종료·취소에서도
   발생한다. 최초 작업 실패 또는 최종 cleanup 상태를 기록하고 종료를 막지 않는다.
5. 숫자 guidance 입력 파싱 및 numeric diagnostics callback 예외: 잘못된 값은 기존
   invalid/unknown 정책으로 거부한다. 경로·목적지·페이로드를 기록하지 않는다.
6. 진단 writer 자체의 실패·잠금 경쟁: 재귀 로그/무한 대기를 하지 않는다. 안전한
   stderr fallback과 persistence 상태를 남긴다. 이미 죽은 root PID만 근거가 있으면 정리한다.
7. NEMESIS가 관리하는 앱/owner exec의 프로세스 생명주기: exec/PID 계약을 바꾸는
   임의 wrapper를 넣지 않는다. NEMESIS service log·Java 안전 진단·상태 수집으로 관찰한다.

## 회귀 근거

- `tests/error-journal.sh`: rc/stdout/최초 실패/모듈 격리/export/256KiB stderr/청크 경계/
  4세그먼트/symlink/죽은 writer 잠금. 결함별 RED→GREEN 관찰.
- `tests/error-boundaries.sh`: 실제 module common의 remount 권한 오류와 기존 반환 정책.
- `tests/local-hotspot-remount.sh`: install/remove/already-stock/busy/retry/unknown/손상 원복.
- `tests/report-history.sh`: 과거 실패 보존/8슬롯/미소유 파일 보존/민감 문자열/긴 줄/용량/symlink.
- `tests/entry-errors.sh`: 준비 전 내부 쓰기 금지/boot 조회 권한13/작업17과 저장1 분리/
  writer 실패 후 producer 완료/최초 작업 실패 보존/비식별화.
- `tests/broker_diagnostics.py`: 실제 launch/exit 코드의 native child PID·stderr·rc·정리·비식별화.
- `SafeDiagnosticTest`, `DiagnosticConsumersTest`: rate/capacity/예외 분류/비식별화,
  실제 요청 rename 실패의 false 반환과 기존 파일 보존.
- `tests/core_recovery.py`: 실제 provider timeout·heartbeat 쓰기 실패를 원인별로 기록하고
  UNKNOWN/원자적 마지막 상태를 유지하는지 확인.
- `tests/relay_adapter_ownership.py`: 실제 iAP read 예외는 false 반환과 진단을 함께 유지.
- `tests/diag.sh`, `tests/uilog.sh`: 수집 권한 오류를 empty와 구분하고 stderr secret을 제외.
- 그 밖의 기존 설치/원복/부팅 복구/드라이버/타이머/블루링크/무선 회귀는 전체 suite로 검증한다.
- bounded `read -n`과 `PIPESTATUS`는 대상 R43 이전 Android4.1.2의 R40에서도 제공된다.
  [AOSP funcs.c](https://android.googlesource.com/platform/external/mksh/+/android-4.1.2_r1/src/funcs.c),
  [sh.h](https://android.googlesource.com/platform/external/mksh/+/android-4.1.2_r1/src/sh.h),
  [main.c](https://android.googlesource.com/platform/external/mksh/+/android-4.1.2_r1/src/main.c)의
  원본을 대조했다. 이 소스 호환 확인은 실제 차량 실행을 대체하지 않는다.

## 남는 한계

- 원래 USB 설치의 remount 원문은 이미 버려져 복원할 수 없다. 이번 보강은 다음 실패의
  관측성을 높이며 그때의 모든 문제를 이미 고쳤다는 뜻은 아니다.
- 오류 원문을 무제한 보관하지 않는다. 알 수 없는 원문은 unknown/redacted로 남을 수 있다.
- 전원 강제 차단, 저장장치 전체 고장, 초기 Android/커널이 서비스 전에 멈춘 경우에는
  앱 로그가 생성되지 않을 수 있다. 외부 NEMESIS/커널의 내부 원인을 전부 관측하지 못한다.
- 소유권 없는 lock/보고서 슬롯은 자동 삭제하지 않는다. 안전한 거부·저장 불가 결과로 남는다.
- 일치하는 private V039 fixture가 없는 exact-stock 시험과 실제 차량 설치·CarPlay/HUD는
  미검증이다. Wi-Fi 드라이버/자격 증명/물리 SPP API 제약은 이번 범위에서 바꾸지 않는다.
