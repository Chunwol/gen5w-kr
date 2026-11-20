# 범용판 무선 실사용·한 방문 검증

설치 USB는 허용된 `/system` 항목을 영구 적용하고 첫 설치 후 자동 재부팅한다. 이후 시동에는 zygote 재시작을 하지 않는다. Android가 시작되지 않을 때의 응급 USB 실행과 정확 복구는 실차 별도 확인 전까지 미검증이다. PC 통과가 차량 안전이나 CarPlay 성공을 뜻하지 않는다. [상세 절차](portable-candidate.md)를 따른다.

1. 정차·안정 전원, 순정 정상 동작, NEMESIS 1.16.7 이상과 기존 패키지 충돌 해소를 확인한다. 기존 USB·로그를 백업한다. Android가 멈춰도 사용 가능한 USB 마운트·root 감시 서비스는 실제 차량에서 확인해야 한다.
2. 순정 기준점과 boot_id·uptime·카메라/오디오/내비·유선 CarPlay 상태를 남긴다. 설치는 NEMESIS를 사용하며 직접 pm install하지 않는다.
3. 설치 후 mode=auto, enabled=1, armed-next-boot를 확인하고 콜드 재시작한다. 무선 CarPlay 연결·BT 전환·오디오·HUD·카메라·내비와 부팅 후 연결 시간을 확인한다. 무선 보류 단계는 기본값이 아니다.
4. 최소 5분 연속 정상 세션으로 재시도 예산 초기화가 기록되는지 확인하고, 15분 이상 실사용 관찰과 일반 시동/실제 콜드 재시작 재연결을 구분해 확인한다. healthy만으로 예산은 초기화되지 않는다. 5분을 채우지 못한 활성화 3회 뒤에는 네 번째 적용이 차단되며 짧은 정상 시동도 포함될 수 있다.
5. USB 루트에 확장자 없는 GEN5W-PORTABLE-RESCUE 파일(내용 disable-portable-v1 한 줄, 메모장 CRLF 허용)을 둬 꽂는다. Windows가 .txt를 숨겨 붙이지 않았는지 확인한다. 자동 적용 전에 `nemesis service list`에 gen5w.kr.portable/rescue가 running인지 확인한다(없으면 그 부팅은 순정 유지·reason=rescue-watch-unavailable). 화면 확인창 없이 enabled=0이 먼저 저장되고 실제 패치·후킹 해제가 끝나는지 확인한다. restore-required는 완료가 아니다. 실패 시 표식을 둔 채 검증된 콜드 재시작 후 재확인한다.
6. 순정 기준점 비교와 카메라·오디오·내비 동작까지 확인한 뒤 표식을 제거한다. 검토한 실제 plan으로 명시 재-arm하면 영구 자동 운용으로 돌아간다. AP 미완료 기록은 별도의 증거 보존·검토 절차로만 해제한다.

세션 종료·DiPO/후킹 상태 상실 뒤 Android가 60초 동안 정상 유지되면(종료 신호 없음) 자동 적용을 차단한다(session-ended-latched). 시동 종료처럼 Android 종료가 시작되거나 전원이 먼저 끊기면 차단하지 않고(session-ended-at-shutdown) 재시도 예산이 반복을 제한한다. 시동 종료 시 Android shutdown이 실제로 일어나는지는 미확인이므로 실차에서 시동을 끈 뒤 reason을 확인한다.

V039 커널에는 last_kmsg·ramoops·bootreason이 없어 panic 흔적 검사는 이 차에서 아무것도 탐지하지 못한다. 대신 부팅마다 Android dropbox(/data/system/dropbox)를 이전 기록과 비교해, 새 system_server crash·watchdog이나 DiPO·projection·iAP2·WifiSettings가 실패 프로세스로 식별되는 새 crash·ANR·tombstone이 있으면 적용 전에 차단한다(dropbox-failure-evidence). CPU 사용량 표의 이름 언급은 실패 프로세스 판정에 사용하지 않는다. 순정 DiPO 자체의 새 crash도 차단한다(보수적). 하드 리셋은 dropbox 기록을 남기지 않을 수 있으므로 실제 최종 제한은 재시도 예산이다. 커널 정지 중 코드는 실행되지 않으며, 안정 구간(5분) 뒤 기록 없이 반복되는 리셋은 판별하지 못한다. USB 복구는 Android와 독립이 아니다: kernel·NEMESIS 서비스 관리자·framework의 USB 마운트가 필요하고, 전원을 켤 때 꽂아 둔 표식도 마운트 뒤에 인식되므로 그 부팅에서 후킹 시작이 한 번 있을 수 있다(다음 부팅부터 순정).

## 0.3.81 설치와 기능 확인

USB 설치는 상황에 따라 두 번 꽂아야 할 수 있다.

1. **첫 번째 꽂기.** 이전 설치의 `/system` 변경이 패키지 없이 남아 있으면(앱만 지운 경우) 설치하지 않는다.
   - 대신 logcat·getprop을 저장하고, 자동 적용을 끈 뒤 기기 안의 부트 가드로 순정 복구를 확인하고 재부팅한다.
   - 결과는 USB의 `GEN5W-PORTABLE-REPORT/RESULT.txt`에 `결과: restored`로 남는다. 복구 직전 로그는 같은 폴더의 `logcat-before-restore.txt`, `getprop-before-restore.txt`, `restore.txt`에 남는다.
   - 남은 설치가 없으면 이 단계 없이 바로 설치한다.
2. **두 번째 꽂기.** 설치한 뒤 자동 재부팅한다.
3. **5분이 지나도 재부팅이 없을 때.** 실패로 보고 USB를 그대로 회수한다. `failed`·`refused` 결과는 아무것도 바꾸지 않았다는 뜻이다.

설치 뒤 확인 항목:

- **홈 화면:** 재부팅 뒤 런처·위젯이 정상으로 뜨는지(0.3.77 실패 지점).
- **무선 CarPlay:** 연결 시 차 블루투스 통화·오디오가 CarPlay로 넘어가는지. 둘이 동시에 연결된 채 "CarPlay 통화 중"이 뜨는지도 본다.
- **소리·HUD·INFO:** 음악 소리, 길안내 HUD, 계기판 INFO 표시. 안 되면 CarPlay를 1~2분 유지한 뒤 로그를 남긴다. 로그의 `path=cp5` 줄이 iAP2 데이터가 어디서 멈추는지 보여 준다.
- **동의 화면:** 시동 시 확인 버튼이 켜지자마자 닫히는지. 차 화면 앱 스위치로 끄면 순정 10초 동작으로 돌아가는지.
- **블루링크 안내:** 매달 뜨는 가입 안내가 숨겨지는지. 다음 달이 되어야 보이므로 즉시 확인은 어렵다.
- **핫스팟:** 블루링크 미가입 상태에서 순정 핫스팟 스위치가 켜지는지. CarPlay 확인이 끝난 뒤 따로 시험한다. 인터넷은 원래 연결되지 않는다.

기록: 후보 SHA256, 차 빌드·NEMESIS 버전, 각 단계 boot_id·시간·결과와 비공개 로그 경로. 제조사 코드·키는 배포물에 포함하지 않는다.
