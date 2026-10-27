# DiPO 무선 세션 시작 제어

자체 코드는 순정 `service/y.onReceive`의 기존 `com.daudio.app.dipo.carplaymagiccode.wireless` 액션 비교 다음 내부 본문만 교체합니다. 액션 비교·receiver 등록·다른 액션·순정 세션 생성/시작 구현은 그대로 유지합니다. 원래 이 액션은 임시 무선 기능 플래그를 바꾸고 iAP2 서비스를 다시 bind했습니다. 변경 후에는 receiver가 가진 DipoService에 `I(false)`를 호출하고 반환합니다. 기능 플래그는 별도 설정 패키지에서 준비해야 합니다.

`DipoService.I(Z)V`는 순정 startCarPlaySession 경로입니다. 기존 생성/시작 상태를 확인하고 필요한 생성·모드 초기화·시작을 순정 메서드로 수행합니다. 인자는 해당 폰의 Bluetooth 오디오 재생 여부이며 이 제어 경로에서는 false를 전달합니다. 첫 생성에서 CarPlayService bind가 비동기로 진행될 수 있어 호출 전달만으로 시작 성공을 판단하면 안 됩니다. 상위 bridge는 서비스 준비 후 재시도와 실제 연결 상태 검증을 담당합니다.

V035/V039 모두 frame 11 registers/3 inputs/4 outputs, 예외 테이블 없는 receiver를 확인했습니다. 무선 액션의 고유 위치, String.equals의 inline 번호, 결과 레지스터, mismatch 분기와 다음 routeguidance 액션, 외부 분기의 내부 진입 여부를 생성 시 검사합니다. 내부 66 code units에 자체 작성한 iget-object/const/invoke-virtual/return와 NOP만 넣습니다. 전체 ODEX 중 이 132바이트와 DEX SHA-1/Adler32 24바이트만 바뀝니다.

`tools/iap2/dipo-v035.json`, `dipo-v039.json`에는 자체 작성 바이트와 전체 원본/수정 해시만 있습니다. 제조사 구현은 저장하지 않습니다. 설치기는 버전별 원본 전체 해시를 확인하고 소유 원본을 보존하며 제거 시 정확히 복원해야 합니다.

2026-10-27 PC 확인: 자체 Dalvik 명령 해석/영역 거부 시험 4개와 V035/V039 비공개 원본의 전체 차이 범위·체크섬·고정 프로필 대조를 통과했습니다. 두 결과를 각 순정 framework로 baksmali 3.0.10/API18 deodex하여 receiver 클래스 전체를 해석했고 stderr는 모두 비어 있었습니다. OEM 결과는 저장소 밖 비공개 경로에만 두었습니다. 실차 시작·재시도·유선 우선·종료는 아직 미확인입니다.

```text
python tests/dipo_control.py
python tests/dipo_control.py --stock <private/V035/HKMC_DiPO.odex> --stock <private/V039/HKMC_DiPO.odex>
```

변경된 클래스의 이전 GC 레지스터 맵은 다시 사용하지 않습니다. ODEX RegisterMapClassPool의 해당 클래스 오프셋만0으로 만들고 deps/opt Adler 체크섬도 다시 계산합니다. [AOSP RegisterMap 구조](https://android.googlesource.com/platform/dalvik/+/3740ab6c5b5544e26acb257bc092415b48bdef63/vm/analysis/RegisterMap.h), [최적화 체크섬](https://android.googlesource.com/platform/dalvik2/+/refs/heads/main/libdex/DexOptData.cpp). 실제 차량 Dalvik 구동은 별도 최종 확인 대상입니다.
