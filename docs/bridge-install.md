# 외부 iAP2 / Android Auto 프로젝션 bridge 설치·복구

`gen5w.kr.bridge`는 자체 작성한 iAP2·DiPO·Android Auto(GPM) 제어 shim, 무선 연결 앱 서비스와 핫스팟 보조 프로세스를 묶는 NEMESIS 모듈입니다. 제조사 APK/ODEX/Java 구현은 포함하지 않습니다. 실제 연결·인증·세션 로직은 앱 서비스와 기존 순정 native 경로에서 처리합니다.

## 적용 조건

`/system/app/Iap2ServerApp.odex`의 전체 해시가 helper `iap2-patch-v035` 또는 `iap2-patch-v039`의 원본/수정본 중 하나와 같아야 합니다. `/system/app/HKMC_DiPO.odex`도 동일 버전 `dipo-patch-v035`/`dipo-patch-v039`에 맞아야 합니다. V039 사양에서는 Android Auto HUD 활성화를 위한 `/system/app/HKMC_GPM.odex`도 `gpm-patch-v039`에 의해 함께 검증·적용됩니다. APK 전체 해시는 해당 버전의 `BRIDGE_APK_V035_SHA`/`BRIDGE_APK_V039_SHA`, `BRIDGE_DIPO_APK_V035_SHA`/`BRIDGE_DIPO_APK_V039_SHA`, `BRIDGE_GPM_APK_V039_SHA`로 검사합니다. 원본 APK는 수정하지 않습니다. 새 파일·교차 버전 조합은 설치 전 exit 77로 건너뜁니다. 이미 소유한 파일이 달라졌거나 어느 백업이든 훼손됐으면 실패하며 대상 파일들을 덮어쓰지 않습니다.

helper는 `original FILE`, `patched FILE`, `apply IN OUT`, `verify FILE SHA`를 제공합니다. NEMESIS 추출 권한 0644를 고려하여 실행 전 우리 helper만 0755로 바꿉니다. 브리지 DEX, 호스트 APK와 iAP2 runtime JAR 존재도 설치 전에 확인합니다.

## 백업과 수명주기

- reset 유지 백업: `/system/etc/gen5w-kr-backup/bridge/{owner,original,dipooriginal,gpmoriginal}`.
- runtime 백업: `/data/nemesis/backup/gen5w.kr.bridge/{owner,original,dipooriginal,gpmoriginal}`.
- 소유 값: `gen5w.kr.bridge:v035-1` 또는 `gen5w.kr.bridge:v039-1`.
- 고정 stage: 각 ODEX 이름 뒤 `.gen5w-kr-bridge.tmp`.

설치 시 NEMESIS로 system을 rw로 remount한 뒤, 원본들을 모두 `cp -p`로 보관하고 전체 해시를 검증합니다. 백업은 임시 파일에서 검증한 뒤 rename합니다. 수정 결과도 helper로 검증한 뒤 원본 속성(mode/uid/gid)을 가진 stage에 쓰고 sync 후 rename합니다. stage 쓰기 직전에 durable staging 소유 표식도 sync하므로 중간 쓰기 이후 중단된 stage를 다음 실행에서 정리할 수 있습니다. 일부 파일만 수정된 상태에서 전원이 끊겼으면 소유한 원본 쌍을 확인하고 다음 설치에서 나머지를 완성합니다. 파일 적용에 실패하면 원본들로 rollback합니다. rollback 실패 시 원본들을 남기고 실패를 알립니다. 원본/수정본 target만 인정하며 알 수 없는 target은 자동 복구하지 않습니다. 종료 경로는 system을 ro로 되돌립니다.

재설치 시 원본 백업을 수정본으로 덮어쓰지 않습니다. `/data` reset으로 runtime 백업만 없어졌으면 system 백업으로 복구합니다. 제거는 원본 해시·소유 표식을 확인한 뒤 원본 bytes와 mode/uid/gid를 보존하여 복원하고 자기 백업만 제거합니다. 심볼릭 링크나 다른 소유 표식은 거부합니다. 이 경로에서 USB로 제조사 원본을 수집하지 않습니다.

설치 도중 stock Iap2Server를 종료하지 않습니다. 단독(standalone) NEMESIS 설치는 거부합니다. 통합 설치만 부트가드를 준비하고, 모든 통합 단계는 점검 전에 `/data/nemesis/gen5wkr.noreboot`를 만들어 마지막 재부팅을 직접 합니다. 인접 ODEX가 유지되므로 Dalvik cache를 삭제하지 않습니다.

## 실행 구조

NEMESIS의 `scripts/service.sh`는 원본·수정 파일과 백업을 확인하고, 부팅 완료 후 Android가 관리하는 `BridgeHostService`를 시작합니다. 블루투스 이벤트 수신과 iAP2 바인딩은 이 앱 프로세스에서 처리합니다. 핫스팟 제어는 system UID의 `ApBroker`가 담당하며, 로컬 소켓 양쪽에서 상대 UID를 확인합니다. 앱이 연결을 끊으면 진행 중인 요청을 취소합니다. 소켓에는 명령과 결과만 전달하며 Wi-Fi 비밀번호는 전달하지 않습니다. 이 구조의 실차 동작은 아직 확인하지 않았습니다.

제거는 `/data/nemesis/gen5wkr.bridge.stopping`을 만든 뒤 `kr.gen5w.wireless.STOP_BRIDGE`를 방송하고 2초 기다립니다. 수신기는 `android.permission.SHUTDOWN`으로 보호됩니다. supervisor는 표식이 있으면 앱과 보조 프로세스를 중지하고 재시작하지 않습니다. 다음 설치가 성공한 뒤에만 표식을 지웁니다.

## PC 검증

`bash tests/bridge.sh`의 모의 설치·복원 및 supervisor 검사 162개가 통과했습니다. 앱 UID 검증과 연결 종료 시 요청 취소도 JVM에서 시험했습니다. APK 빌드·서명은 확인했지만, Android 4.4 차량에서 프로세스 간 연결·iAP2·무선 CarPlay는 아직 확인하지 않았습니다.
