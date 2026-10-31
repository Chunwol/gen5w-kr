# 설치와 복구 구조

사용자 설치 방법은 [설치 가이드](beginner-guide.md), 평소 사용은 [사용 안내](vehicle-use.md)를 참고하세요.

## 공개 기본형

USB 동글판과 기존 개인용 구성의 전환 기준은 [버전 사이 전환](edition-transitions.md)에 정리했습니다. 동글판은 아직 배포 전입니다.

| ZIP | 설치 구성 | 시동 동의 안내 |
|---|---|---|
| `gen5w-kr-standard.zip` | wireless·audio·hotspot·bridge·core·notice | 순정 화면 유지, 지원 타이머 3초 |
| `gen5w-kr-safe.zip` | bridge·core (유선 CarPlay·Android Auto HUD만) | 순정 그대로 (SystemUI 미변경) |

설치본과 소스는 같은 커밋에서 만듭니다. 이전 개인용 설정을 해제하는 복원 전용 검사 자료를 포함하며, 해당 기능을 새로 설치하는 파일은 포함하지 않습니다. `GEN5W-VARIANT=standard`, `GEN5W-BACKEND=builtin`만 허용합니다. 동글용 구성을 표시한 파일만 넣어도 설치되지는 않습니다. 이전 개인용 패키지의 등록이 사라진 상태라면 개인 로컬 번들로 먼저 복원해야 합니다. 원복할 수 없는 상태로 설치를 진행하지 않습니다.

USB의 `NEMESIS.data`는 `type=open`입니다. USB를 꽂으면 Manager만 열고, **Run USB NEMESIS.sh**를 선택하면 실행합니다.

## 안전판 (safe)

`gen5w-kr-safe.zip`은 부팅에 꼭 필요한 시스템 파일을 건드리지 않는 최소 구성입니다. 이전 코나 V039 부트루프의 가장 유력한 원인(한국 펌웨어에서 꺼 둔 Wi-Fi·핫스팟 기능을 다시 켬)을 설치 경로에서 뺐습니다.

- 설치: `gen5w.kr.bridge`(Iap2ServerApp·HKMC_DiPO·HKMC_GPM ODEX의 경로 정보 API)와 `gen5w.kr.core`(HUD 앱)만.
- 설치 안 함, 이미 있으면 순정 복원: 무선 기능 선언·핫스팟(`services.odex`, system_server)·무선 오디오(`libCarPlayAudio.so`)·시동 안내 타이머(`SystemUI.odex`).
- 무선 지원 검사를 아예 실행하지 않고 유선 전용으로 설치합니다.
- 부트가드는 2회 연속 부팅 실패에서 복구합니다(기본형은 3회).
- 설치하지 않은 모듈의 대상 파일(`services.odex`·`libCarPlayAudio.so`·`SystemUI.odex`)이 확인 도구로 순정임이 확인되지 않으면 설치를 끝내지 않고 원래대로 되돌립니다. 그래야 부트가드가 실제로 복구할 수 있습니다.
- 무선 CarPlay·Android Auto, 무선 오디오, 3초 자동 전환은 제공하지 않습니다.

## 작업 선택

`GEN5W-ACTION`이 없으면 설치합니다. 확장자 없는 UTF-8 BOM 없는 텍스트 파일의 첫 줄로 `update`, `status`, `rollback`, `remove`를 선택할 수도 있습니다. 완료 후 파일을 지웁니다.

`install`과 `update`는 같은 교체 절차를 사용합니다. ZIP의 ID와 검사 자료를 확인하고 기존 패키지를 기기 내부에 백업합니다. 설치 전·제거 전·설치 후 훅의 결과를 직접 검사합니다. 모듈 사이에는 `/data/nemesis/gen5wkr.noreboot`로 재부팅을 억제하고 정상 완료 후 한 번 재부팅합니다.

## 이관과 자동 복구

등록된 기존 무선 패키지는 백업 후 정상 제거하고 설치합니다. 등록 파일이 없는 흔적은 임의로 삭제하지 않고 현재 원본·API 검사로 진행 여부를 판단합니다.

미지원 기능은 자동으로 건너뛰고 나머지 기능을 설치합니다. 무선을 사용할 수 없으면 무선 설정·오디오 보정을 원복하고 핫스팟 자동 보정과 Bluetooth 자동 연결을 끕니다. 유선 HUD 기반 패치·HUD 앱·주의 안내 타이머은 각각 지원 조건에 맞으면 설치합니다. 파일 손상이나 복구 실패는 중단합니다.

중단된 설치·제거는 다음 실행에서 먼저 복구합니다. 실패하면 `recovery-required`와 백업을 유지하며 재부팅하지 않습니다. 별도 핫스팟 복구로 이 상태를 덮지 않습니다. `rollback`은 가장 최근 작업 직전 상태로 되돌립니다.

## 자동 분기

설치 시작 시 무선 지원 여부부터 확인합니다. 무선 기능이 없거나 Wi-Fi를 확인할 수 없으면 기존 무선 설정·오디오 보정을 원복하고 핫스팟 자동 보정·Bluetooth 자동 연결을 끕니다. 그 뒤 지원되는 유선 HUD·주의 안내 타이머을 설치합니다. 별도 파일 선택이나 CMD 실행은 필요하지 않습니다.

무선 원복에 실패하면 중단하고 백업을 보존합니다. 무선 지원 판정은 실제 휴대폰 연결 성공과는 다릅니다.

## 결과 파일

| 위치 | 내용 |
|---|---|
| `GEN5W-REPORT/STARTUP.txt` | 실행 작업과 종료 코드 |
| `GEN5W-REPORT/RESULT.html` | 기능별 적용·실패·원복 결과 |
| `GEN5W-REPORT/RESULT.md` | 같은 결과의 텍스트 |
| `GEN5W-REPORT/ISSUE.md` | 검토 후 이슈에 첨부할 진단 로그 |
| 기기 `/data/nemesis/gen5w-kr-integrated/report` | 설치 작업 기록 |

진단 문서는 지정한 비식별 속성·기능·파일 해시만 읽습니다. 원시 로그·인증 자료·제조사 파일을 USB로 수집하지 않습니다. 결과 경로가 심볼릭 링크이면 저장을 거부합니다.

## 빌드

`tools/build-all.sh`가 기본형 ZIP과 대응 소스, 체크섬을 만듭니다. 검사·백업 도구는 API19 ARM 정적 실행 파일입니다. 자체 ZIP 백업 도구는 패키지 디렉터리의 심볼릭 링크와 특수 파일을 거부합니다.

세부 빌드 옵션은 `python tools/integrated/build.py --help`에서 확인합니다. 전체 검증은 [CI](ci.md)에서 수행합니다.
