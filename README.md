# Gen5W KR

한국 내수용 현대·기아·제네시스 Gen5W 내비게이션을 위한 비공식 오픈소스 프로젝트입니다. 지원 조건에 맞는 차량에서 무선 폰 프로젝션을 활성화하고, CarPlay 길안내를 계기판과 HUD에 연결합니다.

[설치 가이드](docs/beginner-guide.md) · [지원 차량과 버전](docs/porting.md) · [문제 신고](https://github.com/Chunwol/gen5w-kr/issues) · [개발 후원](https://github.com/sponsors/Chunwol)

## 다운로드

공개 배포판은 **기본형** 하나입니다. 지원되는 순정 자동 전환 타이머를 10초에서 3초로 조정합니다. 경고 화면과 순정 안전 조건은 유지하며, 자동 전환 조건이 맞지 않으면 수동 확인이 필요합니다. 화면을 완전히 생략하는 개인용 구성은 공개 소스·CI·릴리스에 포함하지 않습니다.

| 버전 | 시동 주의 안내 | 다운로드 | 상태 |
|---|---|---|---|
| **기본형 (내장 Wi-Fi)** | 지원 사양에서 3초 자동 전환 | [기본형 ZIP 받기](https://github.com/Chunwol/gen5w-kr/releases/latest/download/gen5w-kr-standard.zip) | 릴리스 |
| 동글형 (USB Wi-Fi) | 지원 사양에서 3초 자동 전환 | - | 개발 중 (배포 전) |

[차종·연식별 확인표](docs/porting.md)에서 지원 대상을 먼저 확인하세요. [전체 릴리스](https://github.com/Chunwol/gen5w-kr/releases)에서 변경 사항과 체크섬, 대응 소스 파일도 받을 수 있습니다.

## 설치하기

제조사의 승인이나 인증을 받은 제품이 아닙니다. 설치하면 시스템 파일과 설정이 변경되며, 설치 실패·연결 불안정·표시 오류·복구 작업이 발생할 수 있습니다. 모든 차량에서의 정상 동작을 보증하지 않습니다. 설치 전에 [사용 전 안내](docs/notices.md)를 읽어 주세요.

처음 설치한다면 **[설치 가이드](docs/beginner-guide.md)**를 따라 진행하세요. 엔지니어링 모드 진입, NEMESIS 설치, Gen5W KR 설치와 제거 방법을 순서대로 설명합니다.

NEMESIS가 이미 설치되어 있다면 받은 ZIP의 압축을 풀고 **내용물을 USB 맨 바깥에 복사**하세요. 차량에 USB를 꽂은 뒤 NEMESIS Manager에서 **Run USB NEMESIS.sh**를 선택하면 설치합니다. USB를 꽂는 것만으로 설치되지는 않습니다.

작업이 끝나면 USB의 **GEN5W-REPORT/RESULT.html**에서 기능별 결과를 확인하세요. 오류가 있으면 같은 폴더의 **ISSUE.md** 로그를 확인하고 [이슈에 첨부](https://github.com/Chunwol/gen5w-kr/issues/new/choose)해 주세요.

기존 설치 도중 멈췄거나 핫스팟 정보가 맞지 않아 연결하지 못했다면 [기존 설치 복구 안내](docs/wireless-recovery.md)를 먼저 읽어 주세요.

## 지원 범위

Gen5W라도 차량과 소프트웨어 버전에 따라 지원 여부가 다릅니다. 설치 전에 [지원 차량과 버전](docs/porting.md)을 확인하세요.

HUD 길안내는 CarPlay용입니다. 표시되는 정보는 사용하는 지도 앱과 차량에 따라 다르며, Android Auto의 HUD 지원과는 별개입니다.

## 다른 차량 지원과 참여

다른 차량에서도 사용하고 싶다면 [차량 지원 요청](https://github.com/Chunwol/gen5w-kr/issues/new/choose)을 남겨 주세요. 필요한 정보와 진행 절차는 [차종 추가 안내](docs/porting.md)에 있습니다.

오류나 개선 의견은 이슈로 남겨 주세요. [기여 안내](CONTRIBUTING.md)와 [보안 문제 제보](SECURITY.md)를 먼저 확인해 주세요. 차량 개인정보나 제조사 파일은 이슈에 첨부하지 마세요.

## 개발 후원

[♥ GitHub Sponsors에서 후원하기](https://github.com/sponsors/Chunwol)

후원은 자발적인 개발 지원이며, 특정 기능 제공이나 차량별 지원을 구매하는 대금이 아닙니다. 후원 여부와 관계없이 프로젝트를 이용하고 문제를 제보할 수 있습니다.

## 개발 문서

[문서 목록](docs/README.md) · [빌드와 CI](docs/ci.md) · [변경 내역](CHANGELOG.md)

## 라이선스

이 프로젝트는 [GPL-3.0-only](LICENSE)로 배포합니다. 오픈소스 고지는 [NOTICE.md](NOTICE.md), 상세 라이선스 안내는 [라이선스와 소스](docs/licensing.md)를 참고하세요.

설치에는 별도 프로젝트인 [NEMESIS](https://github.com/xwtk/hmg_nemesis)가 필요합니다. NEMESIS의 라이선스는 AGPL-3.0입니다.
