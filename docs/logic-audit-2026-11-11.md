# 로직 점검 및 NEMESIS 1.16.7 계약 대조

대상은 `74b3441`과 그 이후 작업트리의 버전 정책 변경이다. 코드 경로를 추적한 정적 점검이며 모든 실차 조건의 재현이나 전체 소스 무결함 판정이 아니다. USB는 이 점검으로 변경하지 않았다.

## 확인된 수정 대상

1. **P1 / 일반 제거의 서비스 정지 시작 누락.** `tools/integrated/remove.sh:6`은 `q_begin` 없이 `begin`으로 진입한다. `Q_ACTIVE=0`인 채 `q_barrier`가 통과하므로 동작 중인 서비스·APK·자식 프로세스가 검증되지 않는다. `common.sh`의 `safe_remove`는 native uninstall보다 먼저 설치된 `preuninstall`을 실행한다. NEMESIS가 나중에 서비스를 정지해도 앞선 복원 작업은 보호하지 못한다. 제거 전 `q_begin`, 첫 변경 직전 `Q_MUTATING=1`, 오류/종료 시 기존 보류·재개 계약을 적용할 필요가 있다. 이번 버전 정책 변경에는 섞지 않았다.

2. **P1 / OEM 무선 비활성화·자동 연결 끄기를 fallback이 우회.** `StockProjectionSession`은 `DISABLED`/`AUTO_CONNECT_DISABLED`를 BLOCKED로 만들지만 `WirelessBridge.relayEligible`은 BLOCKED 전체를 허용한다. 새 OEM 조회에서도 프로필 허용 상태를 확인하지 않고 idle이면 relay를 시작한다. 비활성화 프로필을 제외하고, 부트스트랩 실패 등 fallback을 허용할 사유를 별도로 구분해야 한다.

3. **P2 / USB 연결 해제 뒤 같은 Bluetooth 폰의 재시도 누락.** `StockProjectionSession.environment`는 유선/다른 소유자 진입 시 CANCELLED로 만들고, 차단 해제 시 그대로 return한다. CANCELLED는 terminal이며 같은 candidate 지정도 무시하므로 Bluetooth가 유지되는 동안 OEM/relay 재시도가 멈춘다. 차단 해제 시 새 generation과 fresh ownership 검사로 재진입해야 한다.

4. **P2 / OEM 무선 성공 후 연결 단절 추적 중단.** ACTIVE가 terminal이라 이후 tick에서 상태를 다시 조회하지 않는다. Wi-Fi/projection만 끊어지고 Bluetooth가 유지되면 새로운 시도나 fallback으로 전환하지 못한다. 낮은 빈도의 fresh 상태 관찰과 확인된 idle 이후의 제한된 재시도 정책이 필요하다.

5. **P2 / 여러 폰 중 첫 실패 candidate가 나머지 후보를 막음.** `BluetoothCandidateScan.offerCandidate`는 candidate가 null일 때만 고른다. BLOCKED/FAILED라도 Bluetooth가 남아 있으면 후보를 유지한다. 다른 연결된 정상 폰을 선택하지 못하는 조건이 있다. 사용자 선택/프로필 우선순위와 제한된 후보 교체가 필요하다.

6. **P2 / 순정 복구 중단 상태에서 앱 복구 버튼의 안내·가능 판정 불일치.** `uilog.sh:recovery_status`는 runner와 prior의 일부 존재 조건으로 available=yes를 표시하며 `stock-recovery-mode`는 확인하지 않는다. `recovery-lib.sh:r_check`도 이를 거르지 않지만 `common.sh:rollback_transaction`은 해당 표식이 있으면 의도적으로 거부한다. 실패한 순정복구+유효 캐시/스냅샷 조건에서는 앱 버튼이 실행 가능한 것처럼 보여도 rollback은 거부된다. 잘못된 이전 패키지 재설치는 방지되지만 UI는 순정복구 USB를 안내해야 한다. MainActivity의 recovery-prepare→rollback 안내도 이 상태에 맞춰 분기해야 한다.

## 별도 보강 후보

첫 번째 서비스 정지 누락은 앱 제거 경로에도 있다. `packages/core/scripts/uilog.sh:do_remove`는 트랜잭션 잠금을 얻지만, 서비스 정지/자식 검증 없이 `run_hook`을 native uninstall보다 먼저 호출한다. USB 제거와 앱 제거를 함께 수정해야 한다.

- relay handover custom broadcast의 송신 권한/attempt 식별 검증. 다른 일반 앱이 설치될 수 있는 환경에서 연결 해제 등 상태 이벤트 주입 표면이 있다. OEM 이벤트를 임의로 차단하지 않도록 실제 송신 UID/권한 계약부터 확인한다.
- 캐시 quarantine은 증거를 보존하지만 자동 용량/개수 제한은 없다. 원본 복구 스냅샷과 분리한 보관 정책이 필요하다.
- AA 입력은 줄 수/소켓 시간 제한이 있으나 `BufferedReader.readLine()`의 한 줄 길이 자체는 제한하지 않는다. 허용 UID의 잘못된 송신에 대비한 크기 제한은 보강 후보이며 일반 비권한 앱 접근과는 구분한다.

## 공식 NEMESIS 1.16.7과의 대조

공식 소스 [고정 커밋 70e72d2](https://github.com/xwtk/hmg_nemesis/tree/70e72d2dce4b39795d618ce46074be96f0294185/Sources/native)를 내려받아 확인했다. 기존 `upstream_reference`는 1.15 계열로 이 판정에 사용하지 않았다. 배포 ZIP의 원본 일치 확인과 이 소스 대조는 해당 바이너리의 실차 실행 시험을 대신하지 않는다.

- `nemesis.h`는 1.16.7을 선언하고 `main.c`는 `version`, `install`, `uninstall`, `pkg-info`, `service`, `remount` 인터페이스를 제공한다.
- [svc.c](https://github.com/xwtk/hmg_nemesis/blob/70e72d2dce4b39795d618ce46074be96f0294185/Sources/native/svc.c)의 service list 출력은 `name|mode|status|pid`이며 우리 파서 계약과 맞는다. stop은 `.stopped` 표식을 먼저 만들지만 등록 PID만 TERM→200ms→KILL 처리한다. 자식/Android 컴포넌트 정지까지 보증하지 않아 우리 추가 검증이 필요하다. 관리자 재시작 시 stop 표식이 지워지는 계약 때문에 세대 검사도 유지해야 한다.
- [pkg.c](https://github.com/xwtk/hmg_nemesis/blob/70e72d2dce4b39795d618ce46074be96f0294185/Sources/native/pkg.c)는 서비스 정지 뒤 preuninstall을 실행하고, 훅/Android 제거 실패 시 등록을 남겨 실패하며 서비스를 재시작할 수 있다. `--force`는 이 실패를 무시하므로 원본 복원 검증 뒤 제한적으로만 호출하는 현 정책이 필요하다. `safe_remove`의 'native ignores hook return' 주석은 구버전 설명으로, 1.16.7 전체 동작 설명으로 읽으면 부정확하다.
- [util.c](https://github.com/xwtk/hmg_nemesis/blob/70e72d2dce4b39795d618ce46074be96f0294185/Sources/native/util.c)는 `/proc/mounts`의 system/root 후보로 remount한다. ro 명령 성공만이 최종 실제 ro 관찰을 대신하지 않으므로 stock-recover의 독립 마운트 플래그 검사는 유지한다.

## 이번에 승인받아 변경한 것

- 새 설치/update/wired-only는 숫자로 확인되는 **1.16.7 미만만 거절**, 이상은 상한 없이 허용한다.
- 버전 확인 실패/비정형 문자열은 경고 후 USB의 정확한 `GEN5W-ALLOW-UNKNOWN-NEMESIS` 확인 파일이 있어야 진행한다. 이 파일로 숫자로 확인된 구버전은 우회하지 못한다. 후속 안전 검사는 유지한다.
- 복구·삭제에는 설치 최소 버전을 적용하지 않는다. 복구 서비스 계약은 이전 기준 및 기존 legacy 경로와 분리한다.
- 확인 파일 방식/유효 기간/위험은 README 및 복구 준비 문서에 설명했다. 이는 최신 미검증 버전의 실제 호환성 보증이 아니다.

## 후속 처리 (2026-11-11, 다른 세션 이어받음)

- 위 버전 정책 변경은 그대로 두었다. 관련 시험은 모두 통과했다. `dist/`는 옛 빌드 결과라서 다시 빌드해야 반영된다.
- 1번(USB 제거와 앱 제거 모두 서비스를 멈추지 않음), 6번(순정 복구가 중단된 뒤 앱 복구 버튼이 잘못 표시됨)을 고쳤다. 앱 제거 뒤 콜드 재부팅이 빠진 것도 함께 고쳤다. 내용과 시험은 `docs/review-2026-11-11-projection.md`의 "설치·제거·원복 흐름 점검"에 있다.
- 2·3·5번은 무선 리뷰에서 처리했다. 2번은 P5로 고쳤다. 3번은 P1과 유·무선 전환으로 다뤘고, Apple 지침에 따라 결함이 아니다. 5번은 사용자가 현재 동작을 유지하기로 정했다. 4번(OEM 무선 연결 뒤 끊김을 따라가지 않음)은 고치지 않고 유지한다. 근거: V039 PhoneProjection에는 사용자가 무선 연결을 끊는 경로(`Wireless.DISCONNECT_PP`, `DISCONNECT_POPUP`)가 따로 있다. 브리지가 보는 상태로는 사용자가 끊은 것과 연결이 끊긴 것을 구분할 수 없다. 그래서 자동으로 다시 요청하면 사용자가 끊은 연결을 다시 이을 수 있다. 끊긴 연결을 다시 잇는 일은 순정(재시도 `ppRetryMax`, `connection_timeout`)과 휴대폰이 맡고, 브리지는 다음 Bluetooth 연결 때 다시 요청한다. 여러 휴대폰 문제(5번)와 같은 원칙이다. 순정이 끊긴 뒤 실제로 다시 잇는지는 실차에서 확인되지 않았다.
