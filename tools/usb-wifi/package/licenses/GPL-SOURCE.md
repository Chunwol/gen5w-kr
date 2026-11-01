# 동글판 GPL 고지와 소스 제공

이 동글 패키지에는 다음 오픈소스 바이너리가 들어 있습니다.

| 파일 | 출처 | 라이선스 |
|---|---|---|
| `files/modules/*.ko` (mac80211, ath, ath9k_hw, ath9k_common, ath9k_htc, ccm, ctr, seqiv, gen5w-average) | Linux 3.18.24 + 현대모비스 Gen5W 공개 커널 소스(STD_G5_WIDE R7)를 V039 커널 설정으로 빌드 | GPL-2.0 (ath 계열 일부 Dual BSD/GPL) |
| `files/bcmdhd.ko` | 이 프로젝트가 작성한 대리 모듈(`tools/usb-wifi/bcmdhd_shim`) | GPL-2.0-only |
| `files/firmware/htc_9271.fw`, `htc_7010.fw` | Debian `open-ath9k-htc-firmware` 1.4.0-108-gd856466+dfsg1-1.3+deb12u1의 `htc_9271-1.4.0.fw`, `htc_7010-1.4.0.fw` (변경 없음) | 주로 BSD-3-Clause-Clear, `ath9k-htc-firmware.txt` 참고 |

라이선스 전문: `GPL-2.0.txt`(GPL 2판), `ath9k-htc-firmware.txt`(펌웨어 저작권·라이선스).

## 대응 소스

위 바이너리의 전체 대응 소스(커널 소스, 사용한 모비스 커널 소스, 커널 설정, 빌드 스크립트, 펌웨어 소스)는
같은 릴리스의 `gen5w-kr-dongle-gpl-source.tar.xz`에 있습니다. 이 소스로 다시 빌드하면 모듈 9개가
배포 파일과 바이트 단위로 같게 나옵니다(방법은 압축 안의 `README.md`).

이 패키지를 다른 사람에게 줄 때는 `gen5w-kr-dongle-gpl-source.tar.xz`도 함께 주세요.

## 서면 제공 약속

이 바이너리를 받은 누구에게나, 마지막 배포일로부터 최소 3년 동안, 위 대응 소스 전체를 실비 이하로
제공합니다. 요청: https://github.com/Chunwol

## English summary

The kernel modules here are GPL-2.0 binaries built from Linux 3.18.24 and the Hyundai Mobis Gen5W
kernel source; `bcmdhd.ko` is our own GPL-2.0-only module; the firmware is the unmodified Debian
open-ath9k-htc-firmware 1.4.0 build. The complete corresponding source is
`gen5w-kr-dongle-gpl-source.tar.xz` in the same release. For at least three years after the last
distribution, anyone who received these binaries may request that source, at no more than the cost
of providing it, via https://github.com/Chunwol.
