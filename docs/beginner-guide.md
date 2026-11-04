# 처음부터 설치하기

엔지니어링 모드 진입부터 **Gen5W KR** 설치까지의 안내입니다. NEMESIS Manager가 이미 열리면 **5단계부터** 시작하세요.

비공식 프로젝트이며 제조사의 승인·인증을 받은 제품이 아닙니다. 설치하면 시스템 파일과 설정이 변경됩니다. 설치 실패, 연결 불안정, 표시 오류 또는 복구 작업이 발생할 수 있으며 모든 차량에서의 정상 동작을 보증하지 않습니다. 설치와 설정은 정차 상태에서 진행하세요. HUD는 보조 정보이므로 실제 도로 상황과 교통 표지를 우선하세요. 소프트웨어는 관련 법령이 허용하는 범위에서 무보증으로 제공되며, 법률상 배제할 수 없는 책임을 제한하지 않습니다.

> ## ⚠️ 메인보드 교체 위험 — 반드시 읽으세요
> **설치 후 조금이라도 부팅이 비정상(현대 로고 반복·꺼짐 반복 등)이면, 자동 복구·공식 SW 업데이트로도 되돌릴 수 없는 경우 메인보드(헤드유닛) 교체 외에 방법이 없을 수 있습니다. 실제로 통교체한 사례가 있었습니다.** 교체 비용·위험을 전부 감수할 수 있고 [설치 전 복구 준비 체크리스트](pre-install-recovery-checklist.md)를 **모두** 마친 경우에만 진행하세요. 조금이라도 불안하면 설치하지 마세요.

## 1. 내 차가 대상인지 확인

차량 화면에서 **설정 → 일반 → SW 정보/업데이트**를 엽니다. 소프트웨어 버전 전체를 개인적으로 기록합니다. NEMESIS 공식 안내의 대상은 버전에 `S5W_M`이 들어가는 Android Gen5W입니다. `S5W_L`, ccNC, 다른 세대에는 이 안내를 적용하지 않습니다.

설치 전에 [지원 차량과 버전](porting.md)을 확인하세요. 같은 V039라도 차종과 원본 파일에 따라 적용 여부가 다릅니다.

준비물은 Windows PC, 데이터 전송용 USB, 데이터 USB 포트가 있는 차량입니다. USB 자료를 먼저 백업하세요. 주차하고 P와 주차 브레이크를 적용한 상태에서 전원을 안정적으로 유지합니다. 하이브리드 READY 상태 작업은 엔진이 켜질 수 있으므로 실외에서 합니다.

## 2. 엔지니어링 모드에 들어가기

한국 코나 Gen5W에서 사용자가 직접 진입한 방법입니다. 설치 USB를 꽂기 전에 메뉴부터 확인하세요.

1. FM 라디오를 켜고 볼륨을 2로 맞춥니다.
2. **설정 → 일반 → SW 정보/업데이트**로 이동합니다.
3. 업데이트 버튼의 **왼쪽 빈 공간 5회 → 오른쪽 빈 공간 1회**를 빠르게 누릅니다. 버튼 자체는 누르지 않습니다.
4. PIN 창에 **`19500625`**를 입력합니다. (차종·연식·펌웨어 버전에 따라 PIN이 다를 수 있습니다. 이 번호로 열리지 않으면 해당 펌웨어용 PIN을 확인해야 합니다.)
5. **Engineering Mode → USB Copy → DSP/Update DSP → Update OTA** 메뉴를 확인합니다.

다른 차량이나 버전에서 화면이 다르면 모델과 소프트웨어 버전을 적어 지원을 요청해 주세요.

## 3. NEMESIS 설치 USB 만들기

1. [NEMESIS 공식 저장소](https://github.com/xwtk/hmg_nemesis)에서 `ota_package.tar`를 받습니다. 우리 앱 설치 ZIP과는 다른 파일입니다. 어느 NEMESIS 버전에서 확인했는지는 [README의 NEMESIS 버전 표](https://github.com/Chunwol/gen5w-kr#nemesis-버전)를 보세요. 표에 없는 버전이면 결과 공유 때 버전을 꼭 적어 주세요.
2. 비어 있는 FAT32 또는 exFAT USB를 준비합니다. 포맷은 기존 자료를 지우므로 백업 후 수행합니다.
3. `ota_package.tar`는 **압축을 풀지 않고 이름 그대로** USB 맨 바깥에 복사합니다. 일반 내비 업데이트 `NaU` 파일과 섞지 않습니다.

```text
USB 드라이브
└─ ota_package.tar
```

공식 저장소의 최신 파일은 바뀔 수 있습니다. 예전 안내의 해시를 다른 버전 파일에 적용하지 말고, 내려받은 커밋과 파일 SHA256을 함께 보관합니다. Windows에서는 파일 우클릭으로 경로를 확인한 뒤 PowerShell의 `Get-FileHash -Algorithm SHA256 -LiteralPath 'E:\ota_package.tar'`로 확인할 수 있습니다. E:는 실제 USB 문자로 바꿉니다.

## 4. 차량에 NEMESIS 설치하고 Manager 열기

1. 차량의 **데이터 전송/내비 업데이트용 USB 포트**에 준비한 USB를 꽂습니다. 충전 전용 포트는 사용할 수 없습니다.
2. 앞서 확인한 **Engineering Mode → USB Copy → DSP/Update DSP → Update OTA**에서 설치를 시작합니다. 이 버튼을 누르면 실제 시스템 변경이 시작됩니다.
3. 진행 표시와 재부팅을 기다립니다. 설치 중 전원을 끄거나 USB를 빼지 않습니다. 미디어의 “지원 파일 없음” 메시지만으로 설치 실패를 판정하지 않습니다.
4. 설치 화면이 끝나고 정상 재부팅되면 USB를 뺍니다. 오류 번호 하나만으로 성공을 판정하지 않습니다.
5. 기본 설정에서는 NAV 버튼을 1.5초 이내 간격으로 세 번 눌러 Manager를 열 수 있습니다. 터치식 공조/버튼 차량 등 물리 NAV 버튼이 없거나 버튼 구성이 다른 차량은 아래 USB 방법을 사용합니다.

USB 방법: 설치 tar를 PC에 보관하고 USB에서 치운 뒤, 메모장으로 아래 내용을 저장합니다. 파일 이름은 **`NEMESIS.data`**이며 `NEMESIS.data.txt`가 아닙니다. Windows 탐색기에서 **보기 → 표시 → 파일 확장명**을 켜서 확인합니다. 메모장 “다른 이름으로 저장”에서 파일 형식을 “모든 파일”로 고릅니다.

```ini
[nemesis]
type=open
id=open-manager
name=Open NEMESIS Manager
version=1
compat=gen5w
```

이 USB를 다시 꽂았을 때 Manager의 **Packages / Services / Logs**가 보이면 다음 단계로 진행합니다. 안 열리면 [NEMESIS 공식 설치 안내](https://github.com/xwtk/hmg_nemesis#quick-installation-guidance)를 확인하세요. Factory Reset이나 다른 펌웨어 쓰기로 대신하지 않습니다.

## 5. 먼저 점검하고 맞는 버전 고르기

설치 전에 **점검 USB**로 내 차에 맞는 버전을 확인합니다. 점검은 차에 아무것도 쓰지 않습니다.

1. [다운로드 페이지](https://github.com/Chunwol/gen5w-kr/releases/latest)에서 **`gen5w-kr-check.zip`**을 받아 압축을 풀고, 내용 전체를 USB 맨 바깥에 복사합니다.
2. 차량에 USB를 꽂으면 NEMESIS가 실행할지 묻습니다. **예**를 누릅니다(60초 안에 안 누르면 취소). "점검 완료" 알림이 뜨면 USB를 뺍니다.
3. PC에서 USB의 **`GEN5W-REPORT/CHECK.md`**를 엽니다.
   - **판정: 설치하지 마세요** → 설치하지 말고, 적힌 이유(예: 공식 V039 업데이트 필요)부터 해결합니다.
   - **판정: 설치 가능** → 아래에 적힌 **받을 파일**을 확인합니다.

| CHECK.md의 받을 파일 | 뜻 |
|---|---|
| 기본형 `gen5w-kr-standard.zip` | 내장 Wi-Fi가 확인됐거나, 아직 확인하지 못했습니다. 기본형 설치기가 Wi-Fi를 잠깐 켜서 다시 확인하고, 내장 Wi-Fi가 없으면 무선만 빼고 설치한 뒤 결과 화면에서 동글형을 안내합니다. |
| 동글형 `gen5w-kr-dongle.zip` | 내장 Wi-Fi가 확인되지 않았고 지원 USB Wi-Fi 동글(AR9271/AR7010)이 꽂혀 있습니다. 또는 이미 동글형이 설치되어 있습니다. |

**유선만 쓴다면:** 유선(케이블) CarPlay·Android Auto만 쓸 거라면 Wi-Fi·동글과 관계없이 **기본형**을 쓰세요. 무선 설정은 순정으로 두고 유선 기능(HUD 길안내 등)만 설치하려면 USB 맨 바깥 `GEN5W-ACTION` 파일 첫 줄에 `wired-only`라고 적고 실행합니다. 동글은 필요 없습니다. 만드는 방법은 [9. 업데이트·상태 확인·되돌리기·제거](#9-업데이트상태-확인되돌리기제거)를 보세요.

내장 Wi-Fi가 없는 차라는 걸 이미 안다면 지원 동글을 꽂은 상태로 점검하세요. 동글형은 설치 직전에 내장 Wi-Fi를 한 번 더 확인하고, 있으면 설치를 멈추고 기본형을 안내합니다(차는 바뀌지 않음). 내장 Wi-Fi가 있어도 동글을 꼭 쓰려면 USB 맨 바깥에 확장자 없는 빈 파일 `GEN5W-FORCE-DONGLE`을 둡니다.

## 6. Gen5W KR 설치 ZIP 받기

1. 같은 다운로드 페이지에서 CHECK.md가 알려 준 설치 ZIP(**기본형 `gen5w-kr-standard.zip`** 또는 **동글형 `gen5w-kr-dongle.zip`**)을 받습니다. 그 밖의 파일(`gen5w-kr-source.zip`, `gen5w-kr-dongle-gpl-source.tar.xz`)은 받지 않아도 됩니다.
2. 기본형은 순정의 10초 자동 전환 타이머가 있는 지원 사양에서 확인 버튼이 활성화되자마자 넘깁니다. 주의 안내 화면과 순정 안전 조건은 유지하며, 수동 동의가 필요한 사양은 그대로입니다. 화면을 완전히 생략하는 개인용 구성은 공개 배포하지 않습니다. USB Wi-Fi 동글형은 내장 Wi-Fi가 없는 차용이며 실차 동작은 아직 확인하지 않았습니다.
3. 같은 릴리스의 `RELEASE-SHA256SUMS`도 받습니다. `Get-FileHash`로 내려받은 설치 ZIP의 SHA256을 구하고 해당 파일 줄과 비교합니다. `gen5w-kr-source.zip`은 개발용 소스이며 설치할 파일이 아닙니다.
4. 받은 설치 ZIP의 압축을 풀고, **그 안의 내용 전체**를 점검에 쓴 USB 맨 바깥에 덮어 복사합니다(`GEN5W-REPORT` 폴더는 그대로 둡니다). 이전의 NEMESIS 설치 tar와 다른 버전의 실행 스크립트는 섞지 않습니다.

```text
USB 드라이브
├─ NEMESIS.data
├─ NEMESIS.sh
├─ install.sh, update.sh, remove.sh, rollback.sh, status.sh, wired-only.sh, check.sh 등 실행 스크립트
├─ zipstore
├─ packages/          ← 선택한 버전의 설치 파일
├─ checks/            ← 설치 전 검사 자료
├─ README.md / CHANGELOG.md
├─ docs/             ← 설치·사용 문서
└─ LICENSE / SOURCE.md / BUILD-REVISION 등
```

`USB\gen5w-kr-standard\NEMESIS.data`처럼 폴더가 한 겹 더 들어가면 안 됩니다. ZIP 자체를 Manager의 단일 패키지 설치로 선택하는 방식도 아닙니다.

## 7. Gen5W KR 설치

1. USB 루트에 `GEN5W-ACTION` 파일이 **없는지** 확인합니다. 기본 동작은 설치입니다.
2. 차량에 USB를 꽂으면 Manager가 열립니다. 이 버전은 **USB 삽입만으로 설치하지 않습니다.**
3. USB를 꽂고 NEMESIS가 실행할지 물으면 **예**를 누릅니다. 차량 상태를 확인해 설치 또는 필요한 복구 경로로 진행합니다. 기능이나 복구 모드를 따로 고를 필요가 없습니다.
4. 정상 완료 시 한 번 재부팅합니다. 실패하면 원복을 시도하고 결과를 남깁니다. 거부 메시지가 나오면 검사 코드를 우회하거나 지원되지 않은 파일을 교체하지 않습니다.
5. 작업이 끝나면 USB를 빼고 PC에서 **GEN5W-REPORT/RESULT.html**을 엽니다. 기능별 적용·실패·원복 결과를 한눈에 볼 수 있습니다. 노란 **받을 버전 안내**가 보이면 그 안내대로 다른 버전으로 바꿔 설치하세요. 핫스팟만 복구한 경우도 구분해 표시합니다. 설치한 기능은 별도 홈 화면 조작 없이 실행됩니다.

설치 완료는 파일 설치 성공을 뜻합니다. 휴대폰 연결이나 HUD의 실제 동작 성공 표시와 구분합니다.

## 8. 휴대폰 사용

- iPhone: Bluetooth와 Wi-Fi를 켜고 차량과 페어링합니다. 휴대폰에 CarPlay 허용 요청이 나오면 허용합니다. 이미 페어링돼 있다면 차량 Bluetooth 연결 상태를 먼저 확인합니다.
- 유선 CarPlay: 데이터 케이블을 데이터 USB 포트에 연결합니다. 무선을 먼저 연결해야 한다는 요구 조건은 없습니다. Apple USB 장치가 감지되면 무선 브리지는 대기합니다. 무선 실패 직후 순정 USB로 넘어가는 전체 동작은 차량에서 별도 확인이 필요합니다.
- HUD: CarPlay 지도 앱에서 **실제 길안내를 시작**합니다. 앱이 제공하는 회전·거리·차선 정보만 표시할 수 있습니다. 지도만 열어 놓은 상태와 안내 시작은 다릅니다. 모든 지도 앱이 같은 정보를 보내지는 않습니다.
- Android Auto: 순정 Google Projection 및 무선 기능 선언을 활성화합니다. V039 환경에서 별도의 휴대폰 보조 앱 없이 순정 계기판 채널(NavigationStatusService)을 사용하는 구성입니다. 앱별 계기판·HUD 턴바이턴 표시는 실차 검증 중입니다.

## 9. 업데이트·상태 확인·되돌리기·제거

PC에서 USB 루트에 확장자 없는 텍스트 파일 **`GEN5W-ACTION`**을 만들고 첫 줄에 아래 단어 하나만 적습니다. UTF-8 BOM 없이 저장합니다. Windows PowerShell에서는 `$actionFile = 'E:\GEN5W-ACTION'; [IO.File]::WriteAllText($actionFile, 'status', [Text.UTF8Encoding]::new($false))`로 만들 수 있습니다. E:와 `status`를 원하는 작업에 맞게 바꿉니다.

| 첫 줄 | 작업 |
|---|---|
| `check` | 아무것도 바꾸지 않고 점검만 해서 `GEN5W-REPORT/CHECK.md`에 판정과 받을 버전 기록 |
| `wired-only` | 무선 설정은 순정으로 두고 유선 기능(HUD 길안내 등)만 설치. 유선만 쓰는 차에 권장 |
| `status` | 설치된 모듈과 직전 작업 상태 확인 |
| `update` | 새 통합본으로 교체 |
| `rollback` | 가장 최근 작업 직전 상태로 복원 |
| `remove` | Gen5W KR을 제거하고 원본 복구 |

USB를 꽂고 실행 확인에서 **예**를 누릅니다. 완료 후 `GEN5W-ACTION`을 지워 다음에 같은 작업을 실수로 반복하지 않게 합니다. 업데이트 시 새 ZIP의 내용을 전체 교체하고 서로 다른 빌드의 모듈을 섞지 않습니다.

NEMESIS까지 제거하려면 **Gen5W KR 제거가 성공한 뒤** NEMESIS 공식 안내에 따라 **Wipe NEMESIS**를 사용합니다. `recovery-required`가 있으면 백업을 지우거나 Wipe부터 하지 않습니다.

## 10. 막혔을 때

| 증상 | 먼저 확인 |
|---|---|
| Engineering Mode 진입/PIN 실패 | 정확한 모델·버전·자리 수. 알려지지 않은 코드 반복 입력 금지 |
| DSP OTA 메뉴 없음 | 현재 NEMESIS 설치 경로 대상 여부. 우리 ZIP으로 해결되지 않음 |
| USB를 꽂아도 Manager가 안 열림 | 데이터 포트, USB 파일 시스템, 루트 파일 위치, `.txt` 이중 확장자, NEMESIS 설치 여부 |
| USB를 꽂아도 실행 확인이 안 뜸 | USB 맨 바깥에 `NEMESIS.data`가 있는지, 차가 완전히 켜졌는지, GEN5W-ACTION 내용 |
| unknown/mismatch/unsupported | 정확한 원본·지원 조건 불일치. 다른 차종 파일로 대체하지 않음 |
| recovery-required | 원본 백업 보존, 같은 호환 번들로 복구. 추가 설치/삭제를 반복하지 않음 |
| HUD가 없음 | CarPlay인지, 실제 안내 중인지, 지도 앱이 해당 정보를 보내는지, core/bridge 설치 여부 |

설치나 점검을 했다면 잘 됐든 안 됐든 [설치 결과 공유](https://github.com/Chunwol/gen5w-kr/issues/new?template=result.yml)로 알려 주세요. 이때 USB의 **GEN5W-REPORT** 폴더 로그(`ISSUE.md`, `EXEC_LOG.txt`, `STARTUP.txt`, 점검 때 `CHECK.md`·`CHECK.txt`)를 확인한 뒤 함께 첨부합니다. 다른 차종이나 펌웨어 지원은 [차량 지원 요청](https://github.com/Chunwol/gen5w-kr/issues/new/choose)에 모델·연식·사용한 배포판·릴리스 버전·재현 순서와 같은 로그를 올려 주세요. `logcat`·`dmesg` 같은 원시 시스템 로그·VIN·전화번호·SSID/비밀번호·키·인증서·제조사 파일은 첨부하지 않습니다. 내장 Wi-Fi 모듈이 없는 차량은 USB Wi-Fi 동글형을 사용할 수 있습니다. 동글형은 배포 중이지만 실차 동작은 아직 확인하지 않았고, 지원 동글(ath9k_htc)만 동작합니다.

설치 기준: [NEMESIS 공식 안내](https://github.com/xwtk/hmg_nemesis), [Manager 사용법](https://github.com/xwtk/hmg_nemesis/blob/main/02-Debugging-Execution-Interface.md). 엔지니어링 모드 진입 순서는 한국 코나 사용자의 확인을 반영했습니다.
