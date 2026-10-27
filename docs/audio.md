# 무선 오디오 형식

`gen5w.kr.audio`는 정확히 일치하는 한국 V035/V039 순정 라이브러리에 자체 작성한 ARM Thumb 형식 선택 함수를 적용합니다. 실차 소리 재생은 아직 시험하지 않았습니다. PC에서는 실제 ARM 함수와 설치 도구를 실행하고 순정 PCM 유지, AAC/Opus 변환 규격, 설치·제거·초기화 복구를 검증했습니다.

## 구현과 확인한 ABI

대상은 `libCarPlayAudio.so`의 입력/출력 형식 선택 함수 두 곳입니다. 스트림 100/101, 역할 CFString과 연결 종류를 받아 64비트 형식 비트맵을 반환합니다. 기존 PCM 비트를 유지하면서 AAC-LC와 Opus를 추가합니다. 알려지지 않은 스트림/역할에는 0을 반환합니다. 연결 종류에 따른 분기는 순정과 마찬가지로 없습니다.

| 추가 비트 | 순정 Core 변환 함수가 반환한 형식 | 채널 | 패킷당 프레임 |
|---|---|---|---|
| 22 | AAC-LC 44.1 kHz | 2 | 1024 |
| 23 | AAC-LC 48 kHz | 2 | 1024 |
| 28 | Opus 16 kHz | 1 | 320 |
| 29 | Opus 24 kHz | 1 | 480 |

순정 `AirPlayAudioFormatToASBD`를 ARM 에뮬레이터로 실행하여 위 값을 확인했습니다. 순정 Utils에는 AAC 변환기와 Opus 어댑터가 있으며, Opus는 별도 `libopus.so`를 로드합니다. 설치 전 Audio 전체 파일과 Core/Utils/Opus 세 의존성의 SHA-256을 모두 검사합니다. 현재 Audio 전체 해시로 V035/V039 프로필을 자동 선택하며 각 버전의 Core/Utils/Opus 조합까지 확인합니다. 버전이 섞이거나 알려지지 않은 원본이나 의존성은 처음 설치할 때 77로 건너뛰고, 소유한 설치 상태가 있으면 실패로 보고합니다.

`tools/audio/recipe.json`(V039), `recipe-v035.json`에는 전체 원본/수정 파일 해시, 수정 영역의 위치·길이·해시, 의존성 해시만 있습니다. 순정 코드나 원본 바이트는 저장하지 않습니다. 교체 코드는 `formats.S`에서 직접 빌드하며 생성된 두 영역의 길이와 해시도 레시피와 대조합니다. ASLR 대응 주소 계산, CFEqual 호출, ARM/Thumb 상태 전환, 8바이트 스택 정렬과 callee-saved 레지스터 보존을 시험합니다.

## 설치·복구

- 원본을 `/data/nemesis/backup/gen5w.kr.audio`와 초기화 후 남는 `/system/etc/gen5w-kr-backup/audio`에 보관합니다. 원본은 차량 내부에만 남습니다.
- 소유 표식과 원본 해시를 검사한 뒤 수정 파일을 별도로 생성합니다. 수정 결과 전체 해시를 확인하고 같은 디렉터리의 임시 파일을 rename하여 교체합니다.
- 재설치는 원본 백업을 유지합니다. data 초기화 뒤 재설치하면 system의 원본에서 data 백업을 다시 만들며, 초기화 직후 직접 제거해도 system 원본으로 복원합니다.
- 복사/rename 실패 시 검증된 원본 또는 기존 수정 파일과 백업을 유지합니다. 같은 시도에서 만든 불완전한 임시 파일을 정리하므로 재시도할 수 있습니다.
- 다른 소유자, 손상된 백업, 알 수 없는 현재 파일, 소유 경로의 심볼릭 링크는 거부합니다. 기존에 발견한 알 수 없는 임시 파일도 임의 삭제하지 않습니다.
- 제거는 원본 전체 해시를 다시 확인한 뒤 복원하며, 자체 백업과 표식만 지웁니다. system remount는 NEMESIS로만 수행하고 성공/실패 시 ro 복귀를 시도합니다.
- 통합 설치의 `/data/nemesis/gen5wkr.noreboot` 표식이 있으면 중간 재부팅을 생략합니다.

`audio-patch`는 libc/동적 로더 없이 Linux ARM EABI syscall을 사용하는 자체 도구입니다. NDK 27의 최소 지원 API와 관계없이 Android 4.4/API19 커널에서 제공하는 syscall만 씁니다. 파일 크기는 32 MiB로 제한하고, 출력 파일이 이미 있으면 덮어쓰지 않습니다. V039 도구 `audio-patch`와 V035 도구 `audio-patch-v035`를 함께 빌드합니다. 두 도구 모두 패키지 ZIP 안에서 실행 권한 0755가 필요합니다.

## PC 재현

Windows NDK 빌드:

```text
python tools/audio/build.py --ndk "$ANDROID_NDK_HOME"
python tests/audio.py
python tests/audio_native.py
```

Linux/WSL에서는 mksh, qemu-arm이 필요합니다. 셸 설치 시험은 실제 chown을 검증하므로 root로 실행합니다.

```text
bash tests/audio.sh
python3 tests/audio_arm.py
```

선택적 비공개 원본 대조는 `audio_native.py --stock <Audio.so> --core <Core.so>`, `audio_arm.py --stock <Audio.so>`로 실행합니다. V035는 두 명령에 `--profile tools/audio/recipe-v035.json`을 더하고 ARM 도구 시험에는 `--helper packages/audio-format/bin/audio-patch-v035`도 지정합니다. 원본은 읽기만 하고 ARM 도구가 생성한 수정 파일은 저장소 밖 임시 디렉터리에서 검사 후 삭제합니다.

2026-10-27 검증: 호스트 C 도구 6개 시험, mksh 설치/복구 45개 검사, V035/V039 각각 Thumb 선택 함수 560개 경우(두 재배치 주소·순정 PCM 비교 포함), 각 실제 Core의 압축 형식 4개 변환, 각 배포 ARM 도구 28개 검사(실제 비공개 원본의 생성/전체 해시 포함)가 통과했습니다. 실차에서는 음악·안내·Siri·통화·재연결·유선 전환과 최종 제거를 확인해야 합니다.
