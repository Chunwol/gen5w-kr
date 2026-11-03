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
