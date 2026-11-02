# 5W 패치 프로그램 안전장치 비교

이 문서는 공개적으로 확인할 수 있는 5W 관련 프로그램의 복구·검증 장치를 비교하고, gen5w-kr의 설치 기준을 정리합니다. 프로그램이 차량에서 실제로 부팅·연결·HUD 출력을 성공했다는 뜻은 아닙니다. 실차 검증 전에는 모든 패치를 미지원 상태로 취급합니다.

## 확인한 프로그램

### NEMESIS

NEMESIS는 패키지 설치·제거와 Android가 올라오지 않은 상태에서 USB 명령을 실행할 수 있는 기반입니다. 서비스 감시와 재시작, USB 실행 경로가 제공되지만, 모든 패키지에 자동 트랜잭션 롤백을 보장하는 것은 아닙니다. 각 패키지가 원본 백업·검증·복구 훅을 직접 구현해야 합니다.

- [디버깅·실행 인터페이스](https://github.com/xwtk/hmg_nemesis/blob/main/02-Debugging-Execution-Interface.md)
- [공식 패키지 목록](https://github.com/xwtk/hmg_nemesis/blob/main/Packages/README.md)

### Leafia Plus

Leafia는 패치 대상 해시를 확인하고, 시스템 파일을 교체하기 전에 원본을 보관하며, 제거 때 원본 바이트를 복원하는 구조를 공개하고 있습니다. 앱을 다시 만들면서 ODEX를 재생성하고 Dalvik 캐시를 채우는 흐름도 포함하지만, 이 절차를 ODEX 바이트 패치 패키지에 그대로 적용하면 패치가 사라질 수 있습니다. 따라서 gen5w-kr은 Leafia의 안전 원칙은 참고하되, ODEX-only 패키지에는 무조건적인 dexopt를 넣지 않습니다.

- [보안·복구 정책](https://github.com/VysseCodes/HMG-Leafia-Plus/blob/main/SECURITY.md)
- [호환성·제한 사항](https://github.com/VysseCodes/HMG-Leafia-Plus)

### LaunchPad / gen5w-preconditioning

정확한 펌웨어 프로필을 확인하고 지원되지 않는 버전은 설치 불가로 처리하며, 설치 결과와 문제 해결 절차를 안내합니다. 다만 앱 수준의 기능이라 boot-critical ODEX 전체를 복구하는 부트가드는 별도로 제공하지 않습니다.

- [gen5w-preconditioning](https://github.com/paytondevs/gen5w-preconditioning)

### Rear Dashcam

실험적 기능이며 벽돌·보증 문제 가능성을 명시합니다. 설치 로그와 제거 안내는 있지만, 공개 문서만으로는 부트루프 자동 원복을 확인할 수 없습니다.

- [gen5-RearDashcam](https://github.com/KramerTech/gen5-RearDashcam)

### Phone Assistant PTT

정확한 펌웨어·프레임워크 해시를 검사하고, 예상하지 못한 파일이면 설치와 제거를 거부합니다. 파일 교체는 임시 파일과 원자적 이름 변경을 사용하며 자동 재부팅을 하지 않습니다. 복구 USB가 항상 보장되는 것은 아니므로, 이 구조는 gen5w-kr의 “재부팅 전 검증” 기준에 참고할 수 있습니다.

- [hkmc-ptt-phone-assistant](https://github.com/dzzzy90/hkmc-ptt-phone-assistant)

### Auto-dismiss 패키지

공개 패키지는 미공개 Binder 트랜잭션과 제한된 펌웨어 시험에 의존하며, 역방향 트랜잭션이나 제거 시 모든 효과의 원복을 보장하지 않는다고 명시합니다. 따라서 안전한 기준 패키지로 간주하지 않습니다.

- [nemesis-package-builds](https://github.com/armandodollia/nemesis-package-builds)

### 분석·복호화 도구

gen5w-utils와 HKG_Gen5W_ReverseEngineer는 펌웨어 분석·복호화·개발을 돕는 도구입니다. 설치 전 원본 백업, 트랜잭션, 부트루프 복구를 제공하는 실행 패키지와는 구분합니다.

## gen5w-kr에 적용한 기준

gen5w-kr의 기존 표는 “Leafia와 안전장치가 동일하다”고 표현하기에 부정확했습니다.

| 항목 | 실제 상태 |
|---|---|
| 패키징 | 둘 다 NEMESIS 기반이지만, Leafia의 1~5 파트와 gen5w-kr의 wireless/audio/bridge/core/timer/bluelink/dongle 구조는 다름 |
| 백업·복구 | gen5w-kr은 트랜잭션 롤백을 갖지만, 이번 보강 전 부트가드가 일부 파일만 복구했음 |
| 테스트 | Leafia의 mock harness를 상속한 것이 아니라 gen5w-kr 자체 `tests/` 스위트를 사용함 |
| dexopt | Leafia처럼 앱을 재생성하는 패키지에는 의미가 있지만, gen5w-kr의 기존 ODEX 바이트 패치에는 무조건 실행하면 패치를 덮을 수 있음 |
| QuickBoot | NEMESIS의 감시·USB 실행은 기반 기능이며, gen5w-kr은 설치 직전 부트가드를 별도로 무장해야 함 |

이번 보강으로 다음을 보장하도록 했습니다.

1. 설치 완료를 기록하기 전에 `gen5wkr.bootguard`를 원자적으로 만들고 `armed/count/max`를 검증합니다. 무장 실패 시 커밋과 재부팅을 진행하지 않습니다.
2. 부트가드 복구 시 원본 백업이 있는 모든 boot-critical 패치 파일과 `libCarPlayAudio.so`를 단계 파일로 복원한 뒤 바이트 비교합니다.
3. 패치한 `Iap2ServerApp`, `HKMC_DiPO`, `HKMC_GPM`에 해당하는 Dalvik 캐시만 삭제하고(`services`·`SystemUI`는 순정이라 건드리지 않음), 삭제 실패나 잔존을 오류로 처리합니다.
4. 복구 성공 때만 `recovered`를 기록하고 재부팅합니다. 복구 실패는 `recovery-required`를 기록하고 추가 재부팅을 하지 않습니다.
5. 정상 부팅 완료 신호가 확인되면 해당 부팅의 실패 카운터만 0으로 되돌립니다. 부트가드 디렉터리와 `armed` 상태는 다음 시동까지 남겨 두어, 사용 중 재부팅된 다음 시동에서 같은 문제가 반복되어도 복구 경로를 유지합니다. 가드가 있는데 `armed`가 없으면 서비스 시작을 거부합니다.

6. PC 전용 [부트로더 복구 경로](bootloader-recovery.md)는 fastboot가 실제로 열거된 경우에만 동작합니다. 공개 설치 패키지는 LK나 부트로더를 수정하지 않으며, fastboot 열거와 순정 이미지 해시가 확인되지 않은 상태에서는 복구 성공으로 표시하지 않습니다.

이 장치들은 파일·트랜잭션 수준의 방어선입니다. eMMC 손상, 전원 차단, 부트로더 손상, 백업 자체의 변조, 실제 차량별 API 차이까지 막아 주지는 않습니다. 따라서 실차 적용 전에는 원본 USB와 탈거·정비 경로를 함께 확보해야 합니다. 다음 버전의 복구 기능도 실차 fastboot 열거와 순정 이미지 복구를 별도로 확인하기 전에는 보장 기능으로 안내하지 않습니다.
