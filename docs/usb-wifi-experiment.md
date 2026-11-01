# USB Wi-Fi 실험 빌드

2026-10-27 PC에서 V039 설정을 기준으로 `ath9k_htc` 계열과 의존 모듈 9개의 컴파일에 성공했고, 아래 도구로 새 디렉터리에서 재현했다. 현재 동글형 설치 ZIP에는 모듈 9개, ath9k_htc용 펌웨어 2개, `bcmdhd` 이름의 대리 모듈 1개가 포함된다. 이는 실차 동작이나 모든 동글 지원을 뜻하지 않는다. 순정 HAL은 포함하지도 바꾸지도 않는다(2026-11-01부터, 이전 HAL 어댑터 방식은 제거).

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

2026-11-01부터 순정 `libhardware_legacy.so`(zygote·system_server가 올리는 라이브러리)는 바꾸지 않는다. V039 순정 `wifi_load_driver`를 분석한 결과, 이 함수가 드라이버 쪽에 요구하는 것은 다음뿐이다: `/system/wifi/bcmdhd.ko` insmod 성공, `/proc/modules`의 `bcmdhd` 항목, `/sys/module/bcmdhd/parameters/mac_address_read`. `wifi_change_fw_path`는 `/data/misc/wifi/firmware_path` 파일에 쓰고, 언로드는 `bcmdhd` 모듈 제거다. 그래서 `tools/usb-wifi/bcmdhd_shim/bcmdhd.c`(대리 모듈)를 순정 `bcmdhd.ko` 자리에 둔다. 이 모듈은 하드웨어를 다루지 않고, 동글 서비스가 올린 `ath9k_htc`의 `wlan0`이 생길 때까지 최대 15초 기다린 뒤 성공한다. 언로드해도 동글 드라이버는 그대로 둔다. 빌드는 `bcmdhd_shim/build.sh <실험 출력 디렉터리>`로 재현하며 vermagic이 순정과 같고, 쓰는 커널 심볼 7개가 V039 export 목록에 모두 있음을 확인했다. 순정 `bcmdhd.ko`(md5 `c19ed2e2d065c6c406d0ba95945caebf`)는 `/system/etc/gen5w-kr-backup/dongle/original`과 `/data` 백업에 두고 제거 시 그대로 되돌린다. KR 순정은 부팅 중 이 모듈을 올리지 않으므로 부팅 경로 밖이다. 설치한 동안 내장 Wi-Fi는 쓰지 않는다.

순정 hostapd에는 nl80211이 있지만 Broadcom private 초기화와 명령 처리도 함께 빌드되어 있다. nl80211 지원 문자열만으로 일반 동글 AP 호환을 판정하지 않는다. 순정 라이브러리를 교체하면 다른 하드웨어 기능과 부팅까지 영향을 줄 수 있어, 현재 방식은 라이브러리를 그대로 두고 드라이버 모듈 자리만 바꾼다.

남은 실차 확인 항목은 실제 커널 ABI와 모듈 로딩, AP/STA 전환과 hostapd 호환, 동글 탈착, 휴대폰 연결이다. 같은 vermagic과 PC 컴파일 성공만으로 차량 지원을 확정하지 않는다. 펌웨어와 모듈의 출처·배포 조건은 별도로 확인해야 한다.

동글 설치기는 기존 파일과 경로가 겹치면 설치를 중단한다. 새 설치에서는 파일별 해시를 기록하고, 제거할 때 기록된 파일이 바뀌지 않았는지 확인한다. 다른 파일이 들어 있는 모듈 디렉터리는 지우지 않는다. 파일별 기록이 없는 이전 설치는 안전하게 자동 전환하거나 제거할 근거가 부족해 중단한다. 이 경우 기존 백업을 보존하고 지원을 요청한다.

## 로딩 대기와 로그

root 서비스는 부팅과 동글 연결 때 모듈을 미리 올리고, 대리 모듈은 `wlan0`을 최대 15초 기다린다. root 서비스는 같은 USB 연결마다 최대 3회 시도하며, 로더의 인터페이스 대기는 회당 5초다. 로그는 `wc` 없이 파일 크기를 확인해 32KB를 넘으면 이전 파일 하나로 교체한다. PC 테스트는 이 대기·재시도·로그 회전을 확인하며 실제 동글 연결 시험을 대신하지 않는다.
