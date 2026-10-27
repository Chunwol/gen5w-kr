# USB Wi-Fi 실험 빌드

2026-10-27 PC에서 V039 설정을 기준으로 `ath9k_htc` 계열과 의존 모듈 9개의 컴파일에 성공했고, 아래 도구로 새 디렉터리에서 재현했다. 설치 가능한 동글판이나 차량 지원 목록이 아니다. 제조사 파일·펌웨어·빌드한 바이너리는 저장소와 배포 ZIP에 포함하지 않는다.

## 확인한 자료

V039 순정 모듈의 vermagic은 `3.18.24-tcc SMP preempt mod_unload ARMv7 p2v8 `이다. 설정은 `ARCH_TCC897X=y`, `CFG80211=y`, `BCMDHD=m`, `BCMDHD_SDMMC=y`이며 `MAC80211`, `BRCMFMAC`, `ATH_CARDS`, `USB_ZD1201`, `USB_NET_RNDIS_WLAN`, `LIBERTAS`, `MWIFIEX`는 비활성이다. 순정 SDIO 드라이버를 USB 동글 드라이버로 간주할 수 없다.

[모비스 공식 공개 소스](https://www.mobis.com/en/tech/rnd.do)의 KONA HEV (OSE) 항목에서 R7과 R5를 확인했다. R7의 두 커널 트리 모두 루트 Makefile/Kconfig와 scripts 디렉터리가 없다. R5의 두 커널 트리에도 모듈 빌드 스크립트가 없어 이전 공개본으로 이 누락을 해결하지 못했다.

R7 두 트리의 `cfg80211.h`, `mac80211.h`, `skbuff.h`, `module.h`, ARM `module.h`는 upstream 3.18.24와 일치한다. `netdevice.h`에는 제조사 변경이 있다. 실험은 upstream 전체 소스를 먼저 풀고 R7의 `AVNT5W_DaudioKK_kerneltcc` 파일을 덮어써 제조사 변경을 보존한다. 이 복원 방식이 실제 차량 커널의 모든 구성·패치와 같다는 검증은 없다.

## 재현

Linux/WSL, Python 3.12 이상, make, 호스트 GCC/libc 개발 헤더가 필요하다. 출력은 저장소 밖의 새 디렉터리만 허용한다. 공식 입력을 별도로 다운로드한 뒤 다음을 실행한다. 입력 파일의 SHA256은 도구가 고정값과 대조한다.

```sh
python3 tools/usb-wifi/experiment.py \
  --upstream /private/linux-3.18.24.tar.xz \
  --mobis /private/mobis-stdg5-wide-r7.zip \
  --toolchain /private/arm-eabi-4.8-android-6.0.1_r81.tar.gz \
  --config /private/kernel-v039.config \
  --output /private/new-usb-wifi-experiment
```

공식 입력 주소:

- [Linux 3.18.24](https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.18.24.tar.xz), [공식 SHA256 목록](https://cdn.kernel.org/pub/linux/kernel/v3.x/sha256sums.asc).
- [모비스 R7](https://www.mobis.com/cmm/fms/FileDown.do?fileId=FILE_000000000049653&fileSn=0&fileNm=OSA_202502180203313740.zip).
- [Android GCC 4.8](https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/+archive/refs/tags/android-6.0.1_r81.tar.gz), 공식 Git commit `26e93f6af47f7bd3a9beb5c102a5f45e19bfa38a`.

`build-report.json`은 입력 해시·설정 변경·모듈 해시·vermagic을 기록한다. `mac80211`, `ath`, `ath9k_hw`, `ath9k_common`, `ath9k_htc`, `ccm`, `ctr`, `seqiv`, `gen5w-average` 9개를 빌드한다. 순정 설정에 없는 EWMA 함수는 upstream `lib/average.c`를 별도 모듈로 묶는다. 최신 호스트 GCC의 dtc 공통 심볼 오류는 호스트 빌드에만 `-fcommon`을 적용한다. 차량 커널을 빌드하거나 교체하지 않는다.

재현 빌드의 9개 모듈은 순정 vermagic과 일치했다. 별도의 비공개 읽기 전용 분석에서 V039 커널의 이름순 ARM export 테이블 두 구간(4,222개·2,998개)을 찾아, 그 심볼과 의존 모듈의 export를 합쳤을 때 9개 모듈의 미해결 외부 심볼이 없음을 확인했다. 이 검사는 심볼 이름만 다루며 구조체 레이아웃·실제 로딩·USB 동작을 검증하지 않는다. 순정 `Module.symvers`는 없고 `MODVERSIONS`는 비활성이다.

[upstream 문서](https://wireless.docs.kernel.org/en/latest/en/users/drivers/ath9k_htc.html)는 이 드라이버의 AP 모드와 별도 펌웨어 필요성을 설명한다. 이는 Gen5W에서의 AP·무선 폰 연결 성공 근거가 아니다.

## 남은 연결부

순정 `libhardware_legacy.so`는 `wifi_load_driver`에서 `/system/wifi/bcmdhd.ko`와 Broadcom 전용 인자를 사용한다. `wifi_get_fw_path`/`wifi_change_fw_path`는 netd의 AP/STA 전환 경로에도 연결된다. 모듈 로딩 우회만으로 순정 Wi-Fi 상태·언로드·모드 전환을 해결할 수 없다.

순정 hostapd에는 nl80211이 있지만 Broadcom private 초기화와 명령 처리도 함께 빌드되어 있다. nl80211 지원 문자열만으로 일반 동글 AP 호환을 판정하지 않는다. 순정 라이브러리 전체를 교체하면 다른 하드웨어 기능까지 영향을 줄 수 있어 Wi-Fi 호출만 다루는 어댑터와 정확한 원본 게이트·복원 처리가 필요하다.

현재 미완료 항목은 실제 커널 ABI와 로딩 검증, 칩셋별 USB ID·AP 기능·펌웨어 출처와 배포 조건, OEM HAL 어댑터 및 hostapd 전용 명령 처리, AP/STA 전환과 동글 탈착, 실제 폰 연결이다. 같은 vermagic과 PC 컴파일 성공만으로 이 항목들을 통과로 표시하지 않는다. 실험 모듈을 네 배포판의 가용 백엔드로 등록하지 않는다.
