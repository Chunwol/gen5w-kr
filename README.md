> [!CAUTION]
> **지금은 설치하지 마세요.** 실차 검증과 문제 수정을 진행 중입니다. 검증이 끝나면 설치 가능 여부를 안내하겠습니다.

<div align="center">

# 🚗 Gen5W KR

**한국 내수용 현대·기아·제네시스 Gen5W 내비게이션을 위한 비공식 오픈소스 프로젝트**

무선 CarPlay·Android Auto를 켜고, 길안내를 계기판과 HUD에 띄웁니다.

[![Release](https://img.shields.io/github/v/release/Chunwol/gen5w-kr?label=release&color=2ea44f)](https://github.com/Chunwol/gen5w-kr/releases/latest)
[![GitHub Stars](https://img.shields.io/github/stars/Chunwol/gen5w-kr?style=social)](https://github.com/Chunwol/gen5w-kr/stargazers)
[![Build and verify](https://github.com/Chunwol/gen5w-kr/actions/workflows/ci.yml/badge.svg)](https://github.com/Chunwol/gen5w-kr/actions/workflows/ci.yml)
[![License: GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-blue)](LICENSE)
![Firmware](https://img.shields.io/badge/firmware-V039.001.260902-informational)
![Vehicle test](https://img.shields.io/badge/%EC%8B%A4%EC%B0%A8-%EA%B2%80%EC%A6%9D%20%EC%A4%91-orange)

[📖 설치 가이드](docs/beginner-guide.md) · [🚘 지원 차량](docs/porting.md) · [✅ 설치 결과 알려주기](https://github.com/Chunwol/gen5w-kr/issues/new?template=result.yml) · [🐞 문제 신고](https://github.com/Chunwol/gen5w-kr/issues/new/choose) · [⭐ 스타 누르기](https://github.com/Chunwol/gen5w-kr/stargazers) · [💖 개발 후원](https://github.com/sponsors/Chunwol)

</div>

> [!IMPORTANT]
> **실차 검증 중**입니다. 검증이 끝나면 결과와 지원 여부를 안내하겠습니다.
> 새 설치·업데이트에는 **NEMESIS 1.16.7 이상**이 필요합니다. 미만 버전은 설치를 거절합니다. 이후 숫자 버전은 허용하되 기존 안전 검사는 유지하며, 버전 확인 불가는 [명시적 확인 절차](docs/pre-install-recovery-checklist.md#버전을-읽을-수-없는-경우)가 필요합니다.
>
> 동일한 공식 5W 시스템 업데이트 패키지를 사용하는 검증 후보: 더 뉴 그랜저, 2021 베뉴, 2020 벨로스터 N, 더 뉴 싼타페, DN8 쏘나타, 올 뉴 아반떼, 더 뉴 아이오닉, 더 뉴 코나, 팰리세이드.
>
> 해당 V039 사양이 대상이며, 차종·연식·옵션에 따른 무선 연결과 계기판·HUD 지원은 확인 중입니다.

> [!CAUTION]
> **메인보드 교체 위험:** 실차에서 검증하지 않은 실험입니다. 설치 후 부팅이 조금이라도 비정상(로고/꺼짐 반복)이면 복구가 안 되어 **메인보드(헤드유닛) 교체**가 필요할 수 있습니다(실제 사례 있음). [설치 전 복구 준비 체크리스트](docs/pre-install-recovery-checklist.md)를 모두 마치고, 위험을 감수할 때만 설치하세요.

> [!TIP]
> **설치해 보셨다면 결과를 알려 주세요!** 잘 되든 안 되든 [설치 결과 공유](https://github.com/Chunwol/gen5w-kr/issues/new?template=result.yml) 이슈 하나가 다음 사람의 차를 지킵니다. 차종·연식·펌웨어와 된 기능/안 된 기능을 체크하고, USB의 `GEN5W-REPORT` 폴더 로그를 같이 올려 주세요.

## ✨ 주요 기능

| | 기능 | 설명 |
|---|---|---|
| 📱 | 무선 폰 프로젝션 | 지원 조건에 맞는 차량에서 무선 CarPlay·Android Auto를 켭니다 |
| 🧭 | 계기판·HUD 길안내 | CarPlay·Android Auto의 회전·거리 안내를 순정 규격(iAP2, NavigationStatusService)으로 전달하는 경로를 구현했습니다. 앱·운영체제별 실제 표시는 실차 검증 중입니다 |
| ⏱️ | 시동 주의 안내 빠른 전환 | 확인 버튼이 활성화되면 순정 조건을 확인해 10초를 기다리지 않고 바로 넘깁니다. 경고 화면과 안전 조건은 그대로입니다 |
| 🔕 | 블루링크 가입 안내 숨기기 | 블루링크 미가입 차에서 한 달마다 뜨는 "서비스 가입 안내"를 다시 띄우지 않습니다. 가입·서비스 기능에는 영향이 없습니다 ([안내](docs/bluelink.md)) |
| 📶 | 동글형 | 내장 Wi-Fi가 없는 차에서 USB Wi-Fi 동글(AR9271/AR7010)로 무선 연결을 씁니다 |

## 📌 프로젝트 상태

현재 실차 검증을 진행하고 있습니다. 차종별 지원 여부와 기능 동작을 확인한 뒤 결과를 안내하겠습니다. 최신 버전은 [릴리스](https://github.com/Chunwol/gen5w-kr/releases)에서, 변경 내역은 [CHANGELOG](CHANGELOG.md)에서 볼 수 있습니다.

## 📥 다운로드

**먼저 점검하고, 점검이 알려 준 버전 하나만 받으세요.**

| 순서 | 파일 | 대상 |
|---|---|---|
| **① 점검** | [⬇️ gen5w-kr-check.zip](https://github.com/Chunwol/gen5w-kr/releases/latest/download/gen5w-kr-check.zip) | 모든 차. 차에 아무것도 쓰지 않고 `GEN5W-REPORT/CHECK.md`에 설치 가능 여부와 **받을 버전**을 적습니다 |
| **② 설치 · 기본형** | [⬇️ gen5w-kr-standard.zip](https://github.com/Chunwol/gen5w-kr/releases/latest/download/gen5w-kr-standard.zip) | 내장 Wi-Fi가 있는 차 |
| **② 설치 · 동글형** | [⬇️ gen5w-kr-dongle.zip](https://github.com/Chunwol/gen5w-kr/releases/latest/download/gen5w-kr-dongle.zip) | 내장 Wi-Fi가 없는 차 + 지원 USB Wi-Fi 동글 |

> [!TIP]
> **유선(케이블) CarPlay·Android Auto만 쓸 거라면 Wi-Fi·동글과 관계없이 기본형을 쓰세요. 무선 설정은 순정으로 두고 유선 기능(HUD 길안내 등)만 설치하려면 USB 맨 바깥 `GEN5W-ACTION` 파일 첫 줄에 `wired-only`라고 적고 실행합니다.** 동글은 필요 없습니다.

릴리스 페이지의 나머지 파일(`gen5w-kr-source.zip`, `gen5w-kr-dongle-gpl-source.tar.xz`, `RELEASE-SHA256SUMS`)은 소스·라이선스·체크섬용이라 설치에는 필요 없습니다. 모든 버전이 **실차 미확인**입니다.

먼저 [차종·연식별 확인표](docs/porting.md)에서 지원 대상인지 확인하세요. [전체 릴리스](https://github.com/Chunwol/gen5w-kr/releases)에서 변경 사항, 체크섬, 대응 소스 파일도 받을 수 있습니다. 화면을 완전히 생략하는 개인용 구성은 공개 소스·CI·릴리스에 포함하지 않습니다.

<details>
<summary><b>동글형은 무엇이 다른가요?</b></summary>

<br>

동글형은 **내장 Wi-Fi가 없는 차**용입니다. 순정 Wi-Fi HAL(`libhardware_legacy.so`)은 바꾸지 않고, 순정이 Wi-Fi를 켤 때 올리는 `/system/wifi/bcmdhd.ko`만 동글 연결용 작은 모듈로 바꿉니다(부팅 중에는 쓰이지 않는 파일). 그래서 동글형을 설치한 동안에는 내장 Wi-Fi 대신 동글을 씁니다.

- V039 원본 `bcmdhd.ko`와 지원되는 `ath9k_htc`(AR9271/AR7010) 장치가 필요합니다. 모든 USB Wi-Fi 동글을 지원하지 않습니다.
- 드라이버를 올리는 중 헤드유닛이 재시작되면 다음 부팅부터 자동 로딩을 멈춥니다. 동글을 뽑았다 다시 꽂으면 한 번 더 시도합니다.
- 동글형은 설치 직전에 내장 Wi-Fi를 한 번 더 확인하고, 있으면 아무것도 바꾸지 않고 멈춘 뒤 기본형을 안내합니다. 내장 Wi-Fi가 있어도 동글을 꼭 쓰려면 USB 맨 바깥에 빈 파일 `GEN5W-FORCE-DONGLE`을 두세요.
- 동글형에서 기본형으로 바꾸면 동글용 변경을 제거하고 순정 구성을 복원합니다.
- 커널 모듈은 GPL-2.0입니다. 대응 소스는 각 릴리스의 `gen5w-kr-dongle-gpl-source.tar.xz`에 있습니다.

</details>

## 🛠️ 설치하기

> [!NOTE]
> 제조사의 승인이나 인증을 받은 제품이 아닙니다. 설치하면 시스템 파일과 설정이 바뀌며, 설치 실패·연결 불안정·표시 오류·복구 작업이 생길 수 있습니다. 설치 전에 [사용 전 안내](docs/notices.md)를 읽어 주세요.

처음이라면 **[설치 가이드](docs/beginner-guide.md)**를 따라 하세요. 엔지니어링 모드 진입부터 NEMESIS 설치, Gen5W KR 설치와 제거까지 순서대로 설명합니다.

### NEMESIS 버전

NEMESIS는 업데이트가 잦고, 버전마다 설치·제거 동작이 조금씩 다릅니다. 아래 표에서 확인된 버전을 쓰는 것을 권장합니다. 다른 버전으로 설치했다면 결과 공유 때 버전을 꼭 적어 주세요(점검·설치 로그에도 자동으로 남습니다).

| NEMESIS | 코드 대조 | 실차 확인 |
|---|---|---|
| 1.16.3 | ✅ 설치·제거·점검 흐름 대조, 모의 테스트 통과 (v0.3.18) | ⏳ 아직 없음 |
| 1.15 | ✅ 대조, 모의 테스트 통과 | ⏳ 아직 없음 |

실차에서 확인되면 차종·펌웨어와 함께 이 표에 적습니다.

NEMESIS가 이미 설치되어 있다면:

1. **점검:** `gen5w-kr-check.zip`의 압축을 풀어 **내용물을 USB 맨 바깥에 복사**하고, 차량에 꽂고 NEMESIS가 실행할지 물으면 **예**를 누릅니다. USB의 **`GEN5W-REPORT/CHECK.md`**에서 판정과 **받을 파일**을 확인합니다. "설치하지 마세요"가 나오면 설치하지 마세요.
2. **설치:** 추천된 설치 ZIP의 내용물을 같은 USB 맨 바깥에 덮어 복사하고 다시 꽂아 **예**를 누릅니다. **예**를 누르기 전에는 아무것도 실행되지 않고, 차가 완전히 켜지기 전에는 실행을 거부합니다.
3. 끝나면 USB의 **`GEN5W-REPORT/RESULT.html`**에서 기능별 결과를 확인합니다. 노란 **받을 버전 안내**가 보이면 그 안내대로 다른 버전으로 바꿔 설치하세요.
4. 결과는 잘 됐든 안 됐든 [설치 결과 공유](https://github.com/Chunwol/gen5w-kr/issues/new?template=result.yml)로 알려 주세요. **`GEN5W-REPORT` 폴더의 로그 파일도 함께 첨부**해 주세요. 성공 보고가 쌓여야 지원 차량 표를 "확인됨"으로 바꿀 수 있습니다.

> [!TIP]
> **올려 주시면 좋은 로그** — 모두 USB의 `GEN5W-REPORT` 폴더에 생깁니다.
>
> | 언제 | 파일 |
> |---|---|
> | 설치 전 점검(`check`) | `CHECK.md`, `CHECK.txt` |
> | 설치·제거·업데이트 | `ISSUE.md`, `EXEC_LOG.txt`, `STARTUP.txt` |
>
> 이 파일들은 차종·펌웨어 버전·파일 해시·단계별 결과만 기록하고 VIN·MAC·Wi-Fi 이름과 비밀번호는 기록하지 않습니다. 올리기 전에 한 번 훑어봐 주세요. `logcat`·`dmesg` 같은 원시 시스템 로그는 개인정보가 섞일 수 있어 받지 않습니다.

> [!IMPORTANT]
> **설치에 쓴 ZIP은 꼭 보관하세요.** 순정으로 되돌릴 때는 같은 ZIP으로 **제거**(`GEN5W-ACTION`에 `remove`, [사용 안내](docs/vehicle-use.md))를 실행합니다. 업데이트 없이 백업한 순정 파일로 되돌리며, 공장초기화나 시스템 재설치 뒤에도 같은 ZIP으로 제거·재설치할 수 있습니다([초기화·재설치 후 복구](docs/recovery.md)).

<details>
<summary><b>부트 안전장치와 복구의 한계</b></summary>

<br>

부트 안전장치는 실차에서 검증되지 않았습니다. 부팅이 연속으로 실패하면 백업과 현재 상태를 확인한 뒤 무선 설정을 포함해 순정으로 복구를 시도하고, 검증이나 복원에 실패하면 백업을 보존하고 멈춥니다. 복구 서비스가 시작되지 않을 정도의 부팅 장애는 처리할 수 없습니다.

- PC에서 fastboot 장치가 실제로 보이는 경우에만 쓸 수 있는 [부트로더 복구 안내](docs/bootloader-recovery.md)가 따로 있습니다.
- 기존 설치 도중 멈췄거나 핫스팟 정보가 맞지 않아 연결하지 못했다면 [기존 설치 복구 안내](docs/wireless-recovery.md)를 먼저 읽어 주세요.
- 검증된 복구 경로를 확보하기 전에는 설치하지 마세요.

</details>

## 🚘 지원 범위

Gen5W라도 차량과 소프트웨어 버전에 따라 지원 여부가 다릅니다. 설치 전에 [지원 차량과 버전](docs/porting.md)을 확인하세요. 펌웨어는 V039(`V039.001.260902`)만 지원하며, 다른 버전이면 공식 업데이트로 V039를 먼저 설치하세요.

## 🔓 공개 저장소 안내

- **비공식 프로젝트입니다.** 현대자동차·기아·제네시스·현대모비스와 관계가 없고, 이들의 승인이나 지원을 받지 않습니다. 상표는 각 소유자의 것입니다([NOTICE](NOTICE.md)).
- **제조사 파일이 없습니다.** 이 저장소와 릴리스에는 제조사의 펌웨어·앱·라이브러리·키가 들어 있지 않습니다. 패치는 차량에 있는 원본 파일의 해시를 확인한 뒤 차량 안에서만 적용합니다.
- **개인정보는 올리지 마세요.** 이슈는 누구나 볼 수 있습니다. `GEN5W-REPORT` 폴더의 로그는 개인 식별 정보 없이 만들어지니 첨부해 주시고, VIN·전화번호·MAC 주소·Wi-Fi 이름과 비밀번호·인증 자료·`logcat` 같은 원시 시스템 로그·제조사 파일은 올리지 마세요.
- **보안 문제**는 공개 이슈 대신 [보안 제보](SECURITY.md)에 적힌 비공개 경로로 알려 주세요.
- **GPL 소스 요청:** 동글형 커널 모듈의 대응 소스는 각 릴리스에 있습니다. 안내된 공식 주소를 쓸 수 없게 되면 [이슈](https://github.com/Chunwol/gen5w-kr/issues)에 "GPL source request"로 요청해 주세요([라이선스와 소스](docs/licensing.md)).

## 🤝 다른 차량 지원과 참여

**호환 결과를 기다립니다.** 아직 실차에서 확인한 차가 적습니다. 설치하거나 점검해 본 분은 결과가 좋든 나쁘든 [설치 결과 공유](https://github.com/Chunwol/gen5w-kr/issues/new?template=result.yml) 이슈로 `GEN5W-REPORT` 로그와 함께 알려 주세요. 올라온 결과는 [지원 차량 표](docs/porting.md)에 반영합니다.

다른 차량에서도 쓰고 싶다면 [차량 지원 요청](https://github.com/Chunwol/gen5w-kr/issues/new/choose)을 남겨 주세요. 필요한 정보와 절차는 [차종 추가 안내](docs/porting.md)에 있습니다. 오류나 개선 의견도 이슈로 받습니다. 먼저 [기여 안내](CONTRIBUTING.md)와 [보안 제보](SECURITY.md)를 확인해 주세요.

## ⭐ 스타를 눌러 주세요

이 프로젝트가 도움이 됐거나 응원하고 싶다면 오른쪽 위 **⭐ Star**를 눌러 주세요. 스타가 많아질수록 더 많은 Gen5W 사용자가 프로젝트를 찾을 수 있고, 실차 결과 보고도 늘어 지원 차량을 넓히는 데 큰 힘이 됩니다.

[![Star this repo](https://img.shields.io/github/stars/Chunwol/gen5w-kr?style=for-the-badge&logo=github&label=Star&color=f5c518)](https://github.com/Chunwol/gen5w-kr/stargazers)

## 💖 개발 후원

이 프로젝트가 도움이 되었다면 개발을 후원해 주세요.

<a href="https://github.com/sponsors/Chunwol"><img src="https://img.shields.io/badge/GitHub%20Sponsors-%E2%99%A5%20%ED%9B%84%EC%9B%90%ED%95%98%EA%B8%B0-ea4aaa?logo=githubsponsors&logoColor=white&style=for-the-badge" alt="GitHub Sponsors에서 후원하기"></a>

- 후원은 자발적인 지원입니다. 특정 기능, 차량별 지원, 설치 대행이나 결과 보증을 구매하는 대금이 아닙니다.
- 후원 여부와 관계없이 누구나 프로젝트를 이용하고 문제를 제보할 수 있습니다.

## 📚 개발 문서

[문서 목록](docs/README.md) · [빌드와 CI](docs/ci.md) · [변경 내역](CHANGELOG.md)

## ⚖️ 라이선스

이 프로젝트는 [GPL-3.0-only](LICENSE)로 배포합니다. 오픈소스 고지는 [NOTICE.md](NOTICE.md), 자세한 라이선스 안내는 [라이선스와 소스](docs/licensing.md)를 참고하세요.

설치에는 별도 프로젝트인 [NEMESIS](https://github.com/xwtk/hmg_nemesis)(AGPL-3.0)가 필요합니다.
# 설치가 복구 필요 상태로 중단된 경우

앱의 **정보 → 설치 복구** 또는 **관리 → 설치 복구**에서 상태와 오류 상세를 확인합니다. **이전 상태로 복구**는 설치 직전 상태로 되돌리는 동작이며 공장 초기화가 아닙니다. 주차 후 실행하고 전원을 유지하세요. 성공하면 재부팅하며, 이후 재설치를 별도로 진행합니다.

구버전 차량에 앱 복구 실행기가 없으면 새 설치 키트의 `GEN5W-ACTION`을 `recovery-prepare`로 지정해 복구 도구만 준비합니다. 이어 `rollback`으로 지정해 다시 실행합니다. 백업이 없거나 검증에 실패하면 복구를 강행하지 않습니다. 앱이 실행되지 않아도 `GEN5W-REPORT/RESULT.md`에서 다음 행동을 확인할 수 있습니다. 복구 표식이나 원본 백업을 직접 삭제하지 마세요.
