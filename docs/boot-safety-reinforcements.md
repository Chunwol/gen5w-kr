# 부트 안전장치 추가 보강 계획

현재 부트가드(`gen5wkr.bootguard`)는 **미커밋 진행 중**(`fix/dalvik-cache-wipe`)이며 소프트/파일 레벨 실패를 노린다. 아래는 그 위에 쌓을 추가 보강. **각 항목은 WSL(mksh+qemu)에서 `bash tests/run.sh` 통과 후에만 커밋/실차.** 블라인드 적용 금지.

## R1. 첫 콜드 부팅 엄격화 (max 튜닝) — 바로 구현 가능

- **지금**: `tools/integrated/common.sh`의 `bootguard_arm`이 `IT_BOOTGUARD_MAX:-3` → 복구까지 **3회 실패** 필요.
- **보강**: 설치 직후 **첫 콜드 부팅은 max=1~2**로 무장(첫 실패에 바로 복구), `boot_completed` 확인되면 평상시 값으로 완화.
- **트레이드오프**: max=1이면 일시적 부팅 딸꾹질 1회에도 전체 순정 복원(안전하지만 불필요할 수 있음). **권장 max=2** 또는 "첫 부팅만 1, 이후 3".
- **테스트**: `tests/bootguard-runtime.sh`에 엄격 임계에서 rc=2(복구 요청) 단언 추가.
- **상태**: 구현+mock 테스트 가능. 단 **부트가드 미커밋 코드 위에 작업**이라 그 변경과 함께 검증.

## R2. 실패 카운트를 더 이른 훅으로 (가장 큰 보강) — NEMESIS 능력 확인 필요

- **문제**: 카운트(`begin`)가 `wireless-bridge`의 **background 서비스(service.sh)**에서 일어남. system_server가 그 서비스 기동 **전에** 죽으면 카운트가 안 올라 **max를 영영 못 넘음 → 자동복구 안 됨**("못 세는" 구멍).
- **확인된 것**: 이 저장소 패키지의 NEMESIS 서비스 모드는 `background`/`once`/`restart`뿐. 명시적 "조기 부팅 단계/Android 꺼진 중" 카운트 훅은 안 보임.
- **조사 결과 (NEMESIS 공개 문서 2026-10-30)**:
  - NEMESIS의 **가장 이른 per-boot 실행점 = init의 `flash_recovery` → `/system/etc/install-recovery.sh`** (watchdog 시작). 이게 Android 프레임워크(system_server/SystemUI)보다 **먼저** 돈다.
  - watchdog가 `svcmgr`를 띄우고, `svcmgr`가 **등록된 패키지 서비스를 시작**. 즉 현재 카운트하는 bridge `background` 서비스는 watchdog/svcmgr **이후**라, system_server가 그 전에 죽으면 못 셈 ← 바로 그 구멍.
  - 일반 서비스엔 **5-strike 재시작 한도**가 있는 듯(문서: USB 핸들러만 "5-strike 한도 없이" 재시작이라 명시 → 일반 서비스는 한도 있음 암시). 이게 부트가드 카운트와 상호작용하므로 확인 필요.
- **보강 후보(구체화)**:
  - **`begin`(카운트만) 초경량 스크립트를 install-recovery/watchdog 단계로** 올려, system_server가 죽어도 매 부팅 카운트가 오르게. → 조기 크래시도 max 도달 → 자동복구.
  - 단 `install-recovery.sh`는 `/system` 파일(부팅 크리티컬)이라 **백업·원자적·검증·복원** 필요. NEMESIS가 이미 여기서 watchdog를 띄우므로, **패키지가 이 단계에 훅을 등록할 수 있는지**가 관건.
- **상태**: **부분 해소** — 이른 훅의 위치는 확인됨(install-recovery/watchdog). 남은 확인: **패키지 매니페스트로 그 단계에 등록 가능한지**(NEMESIS 소스 `Sources/tools/make_nemesis_package.py`/매니페스트 파서) + 5-strike 한도 상호작용. 이것만 확인되면 최우선 구현.
- **솔직한 한계**: install-recovery 단계보다도 이른(초기 init/커널 패닉 즉시 재부팅) 실패는 여전히 소프트웨어로 못 셈 → 물리 복구가 백스톱.

## R3. 확정 보류(첫 콜드 부팅 confirm) — R1에 흡수

- 부트가드 arm/count가 이미 메커니즘. 핵심은 **설치의 warm 재부팅이 아니라 "다음 콜드 시동"을 provisional로** 다루는 것(벽돌이 난 지점).
- **보강**: `begin`이 boot-id로 **첫 콜드 부팅을 식별**해 그 부팅에 한해 엄격 임계(R1) 적용. 성공(`boot_completed`) 시 확정.
- **상태**: R1 + boot-id 로직으로 구현. mock 테스트 가능.

## R4. boot-critical 패치 표면 줄이기 (설계) — 장기

- notice 기능이 **SystemUI.odex를 직접 패치**(boot-critical). SystemUI class load 실패 = logo→꺼짐 벡터.
- **보강**: 월간 안내/동의 억제를 **boot-critical odex를 안 건드리는 방식**(부팅 후 런타임 처리 등)으로 할 수 있는지 설계 평가. boot-critical 패치가 적을수록 logo→꺼짐 원인이 줄어듦.
- **상태**: 설계 평가(블라인드 재작성 금지). 별도 검토.

## R5. 설치 전 물리복구 체크리스트 — 완료

- `docs/pre-install-recovery-checklist.md`로 작성. 부트가드가 못 막는 경우(조기 사망/HW)의 실질 백스톱.

## 실행 순서(권장)

1. **R5** (완료, 제로 리스크) — 실질 백스톱.
2. **R2 조사** (읽기 전용) — NEMESIS 조기 실행 지원 여부. 이게 "못 세는" 구멍을 메울 수 있는지가 전체 보강의 상한을 정함.
3. **R1+R3** (구현+mock 테스트, WSL) — 첫 콜드 부팅 엄격화.
4. **R4** (설계 평가) — 장기.

## 변하지 않는 원칙

이 전부는 **파일/트랜잭션 레벨 방어선**. eMMC/전원/부트로더/백업 변조/차량별 API 차이는 못 막는다. 실차엔 항상 물리 복구 경로(공식 SW USB + recovery 진입 확인 + fastboot/UART)를 함께 확보한다.
