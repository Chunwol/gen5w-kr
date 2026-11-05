# DiPO 핸들 통화 키 보완

브리지의 무선 연결은 순정 PhoneProjection이 소유합니다. DiPO 패치는 무선 연결을 시작하지 않으며, 순정 `service/y.onReceive` receiver와 기존 무선 action 분기를 변경하지 않습니다.

이 패치는 V035·V039 순정 ODEX의 `DipoService.i(II)V`에서 통화 목록 상태가 음수(목록 없음)일 때 핸들 통화 키 처리가 그대로 종료되던 분기만 보완합니다. 음수 상태는 기존 `HookSwitch` 받기 동작으로 이어지고, 순정 0~3 상태 분기는 유지됩니다. 그 밖의 알 수 없는 양수 상태는 기존처럼 무시됩니다.

레시피는 V035·V039 순정 ODEX 전체 SHA-256과 일치할 때만 적용됩니다. 이전에 배포한 두 레시피의 수정본도 업데이트·제거 시 식별해, 저장된 순정 백업에서 새 수정본을 만들거나 순정 바이트로 복원합니다. 알 수 없는 수정본이나 손상된 백업은 덮어쓰지 않고 중단합니다.

PC 검증 명령:

```text
python tests/dipo_control.py
python tests/dipo_control.py --stock <private/V035/HKMC_DiPO.odex> --stock <private/V039/HKMC_DiPO.odex>
```

검증은 바뀐 명령 범위, ODEX 체크섬, 순정 무선 receiver 보존, 통화 키 분기를 확인합니다. 전화 수신·응답 동작과 차량 호환성은 실차에서 별도로 확인해야 합니다.

## V039 component-5 경계 조사

2026-11-05에 exact V039 `/system/app/HKMC_DiPO.odex` 입력(SHA-256 `950b5575603e50aea9894b3568e80e21b3a354a6c812c3991010ab3e0cb9fe90`, 919,848 bytes)을 읽기 전용으로 대조했습니다. 공개 저장소에는 이 바이너리나 디컴파일된 OEM 명령을 포함하지 않습니다.

DEX 경계에서 확인되는 것은 CarPlay의 native `TccCarPlayNativeMethod_iAPSendMessage([BI)I` 호출과 Java `oniAPSendMessage([BI)V` callback입니다. DiPO가 참조하는 `IIap2Service` method table에는 iAP2 초기화·세션·route/HUD 호출만 나타납니다. 반면 exact V039 `Iap2ServerApp.odex`의 추출 DEX에는 public `Iap2SvcTransportReadDone([BI)Z` 구현과 문자열이 실제로 존재합니다. 따라서 이 Binder 호출은 component 4 입력에 사용할 근거가 있지만, DiPO 프로세스 안에서 component 5의 native callback과 송신 wrapper를 연결하는 call edge는 별도로 필요합니다.

따라서 현행 고정 길이 ODEX recipe만으로 component 5를 연결하는 call edge를 만들 수 없습니다. process-local adapter를 안전하게 주입·호출하는 검증 경로가 확보되기 전에는 hook을 추정해 생성하지 않습니다. `dipo-v039.json`은 계속 통화키 fallback만 담으며 component-5 완료 산출물로 취급하지 않습니다.

`tests/dipo_relay_structure.py --stock-v039 <private/V039/HKMC_DiPO.odex>`는 exact 입력 해시, 두 native iAP 경계, Binder method table, call-key 외 코드 바이트 보존 및 전체 DEX 식별자 표 보존을 확인합니다. 현재 recipe에서는 `CarPlayService` 코드가 모두 원본과 같으므로 wired component 1의 경로도 그대로 보존됩니다. 이 구조 감사는 component-5 연결이나 차량 동작을 입증하지 않습니다.
