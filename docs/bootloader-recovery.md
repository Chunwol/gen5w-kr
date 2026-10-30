# 부트로더 복구 경로

이 문서는 다음 부팅 루프에 대비한 **PC 쪽 준비 절차**입니다. 차량에서 실제 fastboot가 열리고 USB 포트가 그 장치로 열거되는지는 이 저장소만으로 확인할 수 없습니다.

## 두 USB 경로를 구분하기

- `fastboot`: 차량이 USB **장치(device)**로 동작하고 PC가 fastboot 장치를 발견해야 합니다.
- U-Boot `update.fai`: 차량이 USB **호스트(host)**로 동작해 USB 메모리를 읽는 별도 경로입니다.

USB 메모리를 꽂았는데 반응이 없다는 사실만으로 fastboot가 지원되지 않는다고 단정할 수 없습니다. 반대로 LK 소스에 fastboot 코드가 있다는 것만으로 차량 전면 USB 포트에서 실제로 쓸 수 있다고 보장할 수도 없습니다.

## 읽기 전용 확인

PC에 Android platform-tools의 `fastboot`를 준비하고, 차량이 이미 fastboot 장치로 열거된 상태에서 다음을 실행합니다.

```text
python tools/recovery/fastboot_recovery.py probe \
  --fastboot fastboot \
  --expected-product kona-gen5w \
  --report fastboot-report.json
```

이 명령은 `fastboot devices`와 제품 식별자만 읽습니다. 장치가 없거나 제품명이 다르면 중단하고, 플래시 명령을 실행하지 않습니다. 보고서에는 일련번호를 저장하지 않습니다.

USB에 넣을 수 있는 `recovery-usb` 번들은 이 읽기 전용 확인 파일만 담습니다. `GEN5W-ACTION`, NEMESIS 설치기, 부트 이미지, 자동 플래시 파일은 포함하지 않으므로 차량에 꽂아도 자동 복구가 시작되지는 않습니다.

## 외부 순정 이미지로 복구할 때

순정 이미지와 SHA-256 목록은 사용자가 별도로 확보해야 합니다. 제조사 이미지·키·차량 식별자는 이 저장소와 공개 ZIP에 넣지 않습니다. 매니페스트의 제품명이 연결 장치와 일치하고, 각 파일의 해시가 맞아야 합니다.

```json
{
  "product": "kona-gen5w",
  "partitions": [
    {"name": "boot", "file": "boot.img", "sha256": "64자리 SHA-256"},
    {"name": "system", "file": "system.img", "sha256": "64자리 SHA-256"}
  ]
}
```

플래시는 읽기 전용 확인을 통과하고 `--confirm-stock`를 직접 지정한 경우에만 가능합니다.

```text
python tools/recovery/fastboot_recovery.py flash \
  --fastboot fastboot \
  --expected-product kona-gen5w \
  --manifest stock-manifest.json \
  --images-root stock-images \
  --confirm-stock
```

허용 대상은 `boot`, `system`, `recovery`, `dtb`뿐입니다. `erase`, `oem unlock`, 부트로더, modem, MICOM 파티션 명령은 도구에 없습니다. 이미지 검증이나 장치 확인이 하나라도 실패하면 쓰지 않고 종료합니다.

## 이 저장소에서 확인하지 못한 것

V039 LK 소스에는 fastboot 초기화와 USB VBUS 제어 코드가 있지만, 코나 실차의 어떤 커넥터가 OTG 장치 포트인지, ID 핀이 어떻게 연결되는지, 서명된 순정 이미지가 무엇인지까지는 확인되지 않았습니다. 따라서 이 문서와 도구는 **실차 복구 성공을 보증하지 않습니다**. fastboot 열거가 되지 않으면 이 도구로 해결할 수 없으며, 그 경우에는 UART·GDS·서비스 지그·보드 수리 같은 별도 경로가 필요합니다.

공개 설치 패키지는 LK·부트로더·modem·MICOM을 수정하지 않습니다. 이 도구도 차량 USB 설치기에 포함되지 않는 PC 전용 복구 보조 도구입니다.
