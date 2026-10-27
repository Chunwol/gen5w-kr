# 외부 iAP2 Bluetooth bridge 설치·복구

`gen5w.kr.bridge`는 자체 작성한 작은 stock iAP2 service 제어 shim, DiPO의 dormant wireless receiver 제어 shim과 `app_process` Java daemon을 묶는 NEMESIS 모듈입니다. 제조사 APK/ODEX/Java 구현은 포함하지 않습니다. 실제 연결·인증·세션 로직은 daemon과 기존 순정 native 경로에서 처리합니다.

## 적용 조건

`/system/app/Iap2ServerApp.odex`의 전체 해시가 helper `iap2-patch-v035` 또는 `iap2-patch-v039`의 원본/수정본 중 하나와 같아야 합니다. `/system/app/HKMC_DiPO.odex`도 동일 버전 `dipo-patch-v035`/`dipo-patch-v039`에 맞아야 합니다. 두 APK 전체 해시는 해당 버전의 `BRIDGE_APK_V035_SHA`/`BRIDGE_APK_V039_SHA`와 `BRIDGE_DIPO_APK_V035_SHA`/`BRIDGE_DIPO_APK_V039_SHA`로 검사합니다. 두 APK는 수정하지 않습니다. 새 파일·교차 버전 조합은 설치 전 exit 77로 건너뜁니다. 이미 소유한 파일이 달라졌거나 어느 백업이든 훼손됐으면 실패하며 양쪽 모두 덮어쓰지 않습니다.

네 helper는 `original FILE`, `patched FILE`, `apply IN OUT`, `verify FILE SHA`를 제공합니다. NEMESIS 추출 권한 0644를 고려하여 실행 전 우리 helper만 0755로 바꿉니다. daemon DEX와 iAP2 runtime JAR 존재도 설치 전에 확인합니다.

## 백업과 수명주기

- reset 유지 백업: `/system/etc/gen5w-kr-backup/bridge/{owner,original,dipooriginal}`.
- runtime 백업: `/data/nemesis/backup/gen5w.kr.bridge/{owner,original,dipooriginal}`.
- 소유 값: `gen5w.kr.bridge:v035-1` 또는 `gen5w.kr.bridge:v039-1`.
- 두 고정 stage: 각 ODEX 이름 뒤 `.gen5w-kr-bridge.tmp`.

설치 시 NEMESIS로 system을 rw로 remount한 뒤, 두 원본을 모두 `cp -p`로 보관하고 전체 해시를 검증합니다. 백업은 임시 파일에서 검증한 뒤 rename합니다. 수정 결과도 helper로 검증한 뒤 원본 속성(mode/uid/gid)을 가진 stage에 쓰고 sync 후 rename합니다. stage 쓰기 직전에 durable staging 소유 표식도 sync하므로 중간 쓰기 이후 중단된 stage를 다음 실행에서 정리할 수 있습니다. 한쪽만 수정된 상태에서 전원이 끊겼으면 소유한 원본 쌍을 확인하고 다음 설치에서 나머지를 완성합니다. 두 번째 파일 적용에 실패하면 양쪽 원본으로 rollback합니다. rollback 실패 시 두 원본을 남기고 실패를 알립니다. 원본/수정본 target만 인정하며 알 수 없는 target은 자동 복구하지 않습니다. 종료 경로는 system을 ro로 되돌립니다.

재설치 시 원본 백업을 수정본으로 덮어쓰지 않습니다. `/data` reset으로 runtime 백업만 없어졌으면 system 백업으로 복구합니다. 제거는 원본 해시·소유 표식을 확인한 뒤 원본 bytes와 mode/uid/gid를 보존하여 복원하고 자기 백업만 제거합니다. 심볼릭 링크나 다른 소유 표식은 거부합니다. 이 경로에서 USB로 제조사 원본을 수집하지 않습니다.

설치 도중 stock Iap2Server를 종료하지 않습니다. standalone 설치 성공 시 한 번 재부팅합니다. `/data/nemesis/gen5wkr.noreboot`가 있으면 통합 설치의 마지막 재부팅에 맡깁니다. 인접 ODEX가 유지되므로 Dalvik cache를 삭제하지 않습니다.

## daemon

NEMESIS background 서비스 `scripts/service.sh`가 매번 두 stock APK/수정 ODEX와 소유 원본 쌍을 검증합니다. 한쪽만 수정된 상태에서는 시작하지 않습니다. `sys.boot_completed=1` 이후 `nemesis root 1000 -c`를 통해 system UID로 시작합니다. Classpath는 패키지 `app/bridge.dex`와 `/system/framework/com.tcc.iap2.jar`입니다. shell 명령에 넣는 패키지 경로는 ASCII 문자·숫자·`_./-`만 허용합니다. daemon 내부에서 Binder 재연결을 처리하며, 프로세스가 끝나면 supervisor가 2~30초 backoff로 재시작합니다. transport 내용이나 전화기 식별자는 로그에 출력하지 않습니다.

제거는 `/data/nemesis/gen5wkr.bridge.stopping`을 만든 뒤 `kr.gen5w.wireless.STOP_BRIDGE`를 방송하고 2초 기다립니다. daemon receiver는 `android.permission.SHUTDOWN`으로 보호됩니다. supervisor는 표식이 있으면 시작·재시작하지 않습니다. 다음 설치가 성공한 뒤에만 표식을 지웁니다.

## PC 검증

2026-10-27 WSL의 실제 mksh에서 `bash tests/bridge.sh`: 87개 통과, 실패 0. 합성 원본/수정본으로 두 버전의 두 파일 설치·재설치·reset 복구·원상복원, 해시/교차 버전/소유/각 백업 불일치, 첫/둘째 파일 rename 실패와 rollback, 두 방향의 부분 적용 쌍 복구, 중단 stage, 심볼릭 링크, remount 실패, daemon 기동·중지 표식·변경 firmware/불완전 쌍 거부를 확인했습니다. 제조사 원본을 저장소나 시험 fixture에 넣지 않았습니다. 실제 ARM helper·DEX 빌드/서명·통합 설치 시험은 별도 전체 검증에서 수행하며, 실차 무선 연결은 아직 확인하지 않았습니다.
