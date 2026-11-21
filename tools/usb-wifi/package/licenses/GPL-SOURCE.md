# 동글판 GPL 고지와 소스 제공

이 동글 패키지에는 다음 오픈소스 바이너리가 들어 있습니다.

| 파일 | 출처 | 라이선스 |
|---|---|---|
| `files/modules/*.ko` (21 USB WLAN drivers and their 37 kernel/helper modules) | Linux 3.18.24 + 현대모비스 Gen5W 공개 커널 소스(STD_G5_WIDE R7)를 V039 커널 설정으로 빌드. Realtek 계열 9개는 `tools/usb-wifi/targets.py`에 고정한 공개 Git 커밋으로 빌드 | GPL-2.0 (ath 계열 일부 Dual BSD/GPL) |
| `files/bcmdhd.ko` | 이 프로젝트가 작성한 대리 모듈(`tools/usb-wifi/bcmdhd_shim`) | GPL-2.0-only |
| `files/firmware/*` | ath9k HTC, Linux-firmware, Atmel, and ZD1211 firmware sources | Per-file origins, hashes, and license text are in `ath9k-htc-firmware.txt`, `usb-wifi-firmware-notices.md`, `linux-firmware-WHENCE`, and adjacent `LICENCE.*` files |

`modules.profile`는 빌드된 21개 USB WLAN 계열을 기록합니다. 펌웨어가 완비된 18개 중 순정 5GHz 핫스팟을 열 수 있는 5개만 범용판이 자동으로 고르고, 나머지 3개는 미완비로 표시됩니다. USB modalias는 21개 모두 기록해 `dongle-test.sh start auto`에서 미완비 프로필도 명시적으로 진단할 수 있지만, 설치 자동 감지와 부팅 로더는 미완비 프로필을 거부합니다.

라이선스 전문: `GPL-2.0.txt`(GPL 2판), `ath9k-htc-firmware.txt`, `usb-wifi-firmware-notices.md`, `linux-firmware-WHENCE` 및 각 `LICENCE.*` 파일.

## 대응 소스

같은 릴리스의 `gen5w-kr-dongle-gpl-source.tar.xz`에 우리가 제공하는 부분(V039 커널 설정, 빌드 스크립트,
대리 모듈 소스)과 나머지 원본의 공식 다운로드 주소·SHA-256이 있습니다.

- Linux 3.18.24: https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.18.24.tar.xz
- 현대모비스 Gen5W 공개 소스 STD_G5_WIDE R7: 현대모비스 오픈소스 공개 페이지(주소는 압축 안의 `README.md`)
- 펌웨어 소스: https://snapshot.debian.org/package/open-ath9k-htc-firmware/1.4.0-108-gd856466%2Bdfsg1-1.3%2Bdeb12u1/

이 입력으로 다시 빌드하면 동글 커널 모듈 전체를 재현할 수 있습니다(방법은 `README.md`).
이 패키지를 다른 사람에게 줄 때는 `gen5w-kr-dongle-gpl-source.tar.xz`도 함께 주세요.

## 서면 제공 약속

이 바이너리를 받은 누구에게나, 마지막 배포일로부터 최소 3년 동안, 위 대응 소스 전체를 실비 이하로 제공합니다.
평소에는 위 공식 주소에서 받으면 됩니다. 위 주소를 쓸 수 없게 되면 이 약속에 따라 요청하세요. 그때는 관리자가
보관한 원본(모비스 소스 포함)을 요청한 사람에게 개별로 전달합니다. 공개 저장소나 릴리스에는 다시 올리지 않습니다.
요청: https://github.com/Chunwol/gen5w-kr/issues (제목에 "GPL source request"; 개인정보는 쓰지 마세요)

## English summary

The kernel modules here are GPL-2.0 binaries built from Linux 3.18.24 and the Hyundai Mobis Gen5W
kernel source; `bcmdhd.ko` is our own GPL-2.0-only module; firmware sources and licenses are listed
per file in the package notices. `gen5w-kr-dongle-gpl-source.tar.xz` in the same release holds
the kernel configuration, build scripts and stand-in source, plus official download addresses and
SHA-256 for Linux 3.18.24, the Mobis R7 source and the Debian firmware source. For at least three years after the last
distribution, anyone who received these binaries may request the complete corresponding source, at no
more than the cost of providing it, via https://github.com/Chunwol/gen5w-kr/issues (title "GPL source request"). If the official addresses stop
working, the maintainer's archived originals (including the Mobis source) are sent to the requester
individually; they are not re-published in a public repository or release.
