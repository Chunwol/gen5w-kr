# Installation Recovery UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 순정형 앱에서 설치 복구 상태를 확인하고 사용자 동의로 검증된 이전 상태 복구를 실행한다.

**Architecture:** 기존 root collector와 앱 요청 파일을 확장한다. core 패키지 밖의 root 소유 복구 번들이 작업을 수행하며 installer/remove/recovery는 같은 잠금을 사용한다. 앱은 상태 표시와 제한된 요청만 담당한다.

**Tech Stack:** Android API18 Java, Android shell, Python 릴리스 빌더, JVM/shell 회귀 시험.

**Spec:** `docs/superpowers/specs/2026-11-09-recovery-ui-design.md`

## Global Constraints
- StockSkin/Widgets, 기존 글꼴·행 높이·구분선·사각 버튼·선택/비활성 스타일을 재사용한다.
- 상태 확인은 자동, 시스템 변경은 명시적 확인 후 수행한다.
- 공장 초기화, 표식 삭제 우회, 자동 재설치는 하지 않는다.
- 최초 설치 오류와 복구 오류를 별도 보존한다.
- 실차 성공을 추정으로 확정하지 않는다. 공개 릴리스·USB 갱신은 포함하지 않는다.

## Review Focus
- 구버전 차량에 runner가 없음: 상태 안내는 가능하되 복구 USB 준비를 안내한다(Task1/3).
- core/collector가 복구 중 제거됨: worker와 최종 기록이 살아남고 UI는 완료를 추정하지 않는다(Task2/4).
- 같은 PID 재사용 및 중복 요청: 살아 있는 타 작업 잠금을 회수하지 않는다(Task2).
- snapshot/manifest/link 변조: 시스템 쓰기 전에 거부한다(Task1/2).
- 오래된 상태/화면 유지/언어 확장: 실행 시 재검사하고 작은 화면에서도 버튼과 원인이 잘리지 않는다(Task3/4).

### Task 1: 검증 복구 번들 및 준비 진입점
**Files:** Create `tools/integrated/recovery.sh`, `tools/integrated/recovery-lib.sh`, `tests/recovery.sh`; Modify `tools/integrated/build.py`, `tools/integrated/NEMESIS.sh`, `tools/integrated/common.sh`, `tests/integrated-build.sh`, `tests/run.sh`.

**Interfaces:** `recovery.sh prepare|check|run`만 허용한다. 게시 경로 `/data/nemesis/gen5wkr.recovery`, 결과 경로 `/data/nemesis/gen5wkr.recovery-result`. `check` exit0=사용가능, exit1=거부; stdout은 허용된 reason token 한 줄이다. prepare는 시스템 파일과 TX/prior를 변경하지 않는다. manifest는 빌드 산출물의 상대경로/해시/크기만 포함한다. 경로 탈출·링크·중복 이름은 거부한다.

- [ ] shell 실패 시험 작성: absent runner는 unavailable, missing complete/hash mismatch/link/권한 오류는 거부; prepare 전후 prior SHA 동일; staging 실패 시 이전 번들 유지.
- [ ] `bash tests/recovery.sh` 실행하여 새 기능 부재로 실패 확인.
- [ ] builder가 common/rollback/errors/report/history/zipstore/필수 패키지와 선택파일을 복구 번들에 포함하도록 구현. manifest 허용 목록으로 완전성 검사. prepare는 root 고정 경로와 상위 경로/소유권/쓰기 권한 검증 후 staging 게시. 일반 설치 begin 전 prepare; 기존 required 상태에서는 명시적 `GEN5W-ACTION=recovery-prepare`로 prepare만 허용. 설치 gate는 우회하지 않는다.
- [ ] 같은 시험과 `bash tests/integrated-build.sh` 통과 확인.
- [ ] 관련 파일만 add하고 `feat: stage verified recovery bundle` 커밋.

### Task 2: 독립 worker·공통 잠금·복구 결과
**Files:** Modify Task1 shell 파일, `tools/integrated/common.sh`, `tools/integrated/rollback.sh`, `packages/core/scripts/uilog.sh`, `tests/recovery.sh`, `tests/integrated-edge.sh`, `tests/uilog.sh`.

**Interfaces:** `recovery.sh run`은 게시 번들의 위치에서 실행하고 환경을 고정한다. 요청 identity는 boot+10자리 이하 token; `recovery_request=<token>`, `recovery_result=working|restored|failed|unavailable|interrupted`, `recovery_reason=<allowlisted-token>`를 root 결과 파일에 원자 게시한다. worker는 core 서비스 밖에서 실행된다. 공통 TX/lock은 boot/PID/proc starttime/operation token으로 소유자를 구분한다.

- [ ] 실패 시험 작성: install/remove/recovery 경합, double tap/replayed token, boot/만료 불일치, 동일 PID 다른 starttime, worker 중단, 결과 기록 실패, core 제거, snapshot 손상, bootguard 실패. 실패 시 suppression 유지·재부팅0회; 성공 시 최종 검증 후 재부팅1회 확인.
- [ ] `bash tests/recovery.sh`와 `bash tests/uilog.sh`에서 실패 확인.
- [ ] 기존 rollback을 재사용하되 잠금/최종 결과를 공통화한다. rollback의 상태 변경 중간에 worker가 죽으면 다음 조회에서 interrupted로 판정하고 자동 재실행하지 않는다. 앱 제거에도 같은 잠금을 적용한다. uilog는 recovery 요청과 remove/설정 혼합을 거부하고 시작 요청을 먼저 기록한다. 신뢰되지 않은 인자를 명령/경로로 쓰지 않는다. worker는 stdin을 닫고 고정 root 로그로 출력하여 collector 종료와 분리한다.
- [ ] 위 시험 및 `bash tests/integrated-edge.sh` 통과 확인.
- [ ] `feat: run serialized independent recovery worker` 커밋.

### Task 3: 상태 모델·요청·순정형 화면
**Files:** Create `app/src/kr/gen5w/ui/RecoveryStatus.java`, `app/test/RecoveryStatusTest.java`; Modify `StatusModel.java`, `SwitchRequest.java`, `MainActivity.java`, `I18n.java`(동일 ui 디렉터리), `packages/core/scripts/uilog.sh`, `tests/uilog.sh`, `tests/run.sh`.

**Interfaces:** `RecoveryStatus.parse(List<String>)`, `state()`, `reason()`, `stage()`, `request()`, `result()`, `canRequest(boolean fresh)`; state는 none|required|working|restored|unknown, 누락/잘못된 값은 unknown. `SwitchRequest.Writer.write`에 recovery token 지원을 추가하되 기존 호출 호환 overload 유지. collector는 spec의 recovery_* 6필드를 bounded status에 게시한다.

- [ ] JVM 시험 작성: unknown/malformed/freshness/required+unavailable/working/오래된 restored; recovery 요청만 전달되며 임의 문자열/혼합 명령이 거부되는지 확인. shell 시험에는 오래된 transaction 원인과 새로운 복구 오류 분리 확인 추가.
- [ ] `bash tests/run.sh`에서 해당 새 시험 실패 확인.
- [ ] 모델과 collector 매핑 구현. MainActivity 정보 상단 그룹 및 관리 복구 그룹, 상세/기존 진단 연결, 화면 내 확인/취소, request pending/result 표시 구현. 실행 클릭 시 freshness 재검사. 기존 StockSkin/Widgets만 재사용하고 checkbox는 설정에만 유지; 복구는 동작 버튼으로 표시. core 소실/collector stale은 완료로 추정하지 않는다. 한국어·영어 모두 추가.
- [ ] JVM/shell 회귀 통과, 기존 switch/remove 진단 동작 유지 확인.
- [ ] `feat: show stock-styled installation recovery controls` 커밋.

### Task 4: 앱 불가 안내·UI 검증·최종 회귀
**Files:** Modify `tools/integrated/report.sh`, `tests/integrated.sh`, `tests/ui-preview/UiProbe.java`, `tests/ui_preview.py`, `README.md`; tests/recovery.sh 보강.

**Interfaces:** report는 required/unknown/runner unavailable을 구분하고 recovery-prepare와 rollback의 역할 및 재부팅을 설명한다. USB 저장 실패와 차량 내 작업 실패는 독립 결과다. 문서는 설치 전 상태 복구와 순정 초기화를 구분한다.

- [ ] 실패 시험: 앱 미설치/collector 종료에서도 결과 문서에 다음 행동 존재; USB 분리/쓰기 실패가 복구 성공으로 변조되지 않음; 복구 후 재설치 가능; 잘린 원문은 unknown으로 표시.
- [ ] 관련 시험 실패 확인 후 report/문서 구현.
- [ ] 실제 preview 도구 사용법을 읽고 한국어/영어·정보/관리/확인/진행/실패/unknown·기존 해상도/800x480 화면 캡처. 기존 화면과 비교해 글꼴·간격·사각 버튼·체크박스 유지와 스크롤/클릭 영역 확인. 스크린샷만으로 실차 외관 검증이라 주장하지 않는다.
- [ ] 전체 `bash tests/run.sh`, clean `bash tools/build-all.sh`, `python tools/audit-artifacts.py dist` 실행. skip 사유와 exit 기록.
- [ ] `test: cover recovery reports and stock UI states` 커밋 후 전체 변경 독립 리뷰를 1회 요청하고 중요 지적은 실패 시험부터 수정·재검증.
- [ ] KnowledgeHub 세션/브리프 갱신, 완료·실차 미확인·미발행·USB 미변경을 구분하여 보고.

## 자체 검토
설계의 UI/계약/runner/구버전/core 소실/오류 보존/시험 요구를 Task1–4에 매핑했다. 상태는 unknown 기본값, result와 state는 구분하며 요청이 runner 경로를 선택하지 않는다. 실제 구현 전 preview 및 기존 shell harness 호출 규약을 읽고 그 규약에 맞춰 시험을 등록한다. 실행 방식은 Native를 권장한다: 네 작업의 잠금·상태 계약 의존성이 크므로 같은 구현자가 연결하고 마지막 독립 리뷰로 확인한다.
