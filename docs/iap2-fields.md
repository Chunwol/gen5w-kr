# 순정 iAP2 길안내 인터페이스 확인

2026-10-27 보유 V039 `com.tcc.iap2` 라이브러리의 상수 선언에서 확인한 인터페이스 사실이다. 제조사 구현은 포함하지 않는다. 실제 앱 수신·화면 출력은 최종 통합본 시험 전이다.

| 용도 | 알림 종류(`NotiType`) | 주요 항목 번호 |
|---|---|---|
| 상태 | `0x78` | component 0, state 1, 다음 회전 거리 10, 현재 회전 목록 13, source 19 |
| 회전 | `0x79` | component 0, index 1, description 2, type 3, after-road 4, distance 5, driving-side 8, junction-type 9, exit-angle 11 |
| 차선 | `0x7a` | component 0, index 1, lane groups 2, instruction 3 |
| 각 차선 | 그룹 내부 | index 0, status 1, angles 2, highlighted angles 3 |

- wire 메시지 번호 `0x5201`(상태), `0x5202`(회전)와 Java listener의 알림 종류는 다르다.
- 주행 방향 상수: right-hand `0`, left-hand `1`. 이전 `Maneuver` 초안의 right-hand `2`는 수정했다.
- 안내 상태: `0` 없음, `1` 경로 있음, `2` 도착, `3` 로딩, `4` 위치 찾기, `5` 재탐색, `6` 경로 진입 중. 알 수 없는 상태는 표시 허용으로 취급하지 않는다.
- unsigned 32-bit 숫자가 `int[]`로 전달되면 부호 없이 해석한다. 누락된 각도를 0도로 간주하지 않는다.
- 차선 status·각도·index는 원본 값으로 보관한다. 아래 차선 전송 형식 절에 확인 사실과 변환 정책, 미검증 가정을 구분한다.
- 상태·회전은 부분 갱신이다. component가 생략되면 현재 component를 쓰고, component 배열이면 일치하는 현재 component를 우선한다. 현재 회전 목록의 첫 index가 첫 표시 대상이다. 명시적인 빈 목록은 이전 안내를 지운다.
- `Iap2SvcStopMain(listener)`는 확인한 순정 `Iap2Service$2`에서 해당 listener를 제거한다. 이 앱은 다른 앱의 listener나 공용 네이티브 transport를 중지하지 않는다.

## 길안내 시작 요청과 지역 조건

순정 DiPO `e/b.M()`은 `G().aT()==1`이며 iAP2 Binder가 있을 때 `Iap2SvcStartRouteGuidanceUpdate(["RouteGuidanceComponent0"],true,true)`를 호출합니다. 그러나 `e/h`의 listener 등록은 `i/e.jw()`(ro.product.opt.stepofspec >= 999)가 참이고 지역 KR/CN/US/EU/ME/AU/BR 중 하나일 때만 `0x1000` RouteGuidance bit를 더합니다. KR step 110에서는 이 순정 구독에 의존할 수 없습니다. 원본 disassembly에 quick 호출이 남아 있어 `M()`의 모든 호출 지점은 증명하지 않았습니다.

확인한 API는 `Iap2SvcGetRouteGuidanceRegisteredComponentCount():int`, `Iap2SvcGetRouteGuidanceComponentNameIdList(int[] ids,String[] names):int`, `Iap2SvcStartRouteGuidanceUpdate(String[] names,boolean sourceName,boolean sourceSupport):boolean`입니다. list의 양수 반환은 실제 채운 component 수입니다. 두 boolean은 차선 요청 flag가 아니라 source name/source support 포함 여부입니다. server는 `IsValidSvcState`(연결됨 + identification/authentication 초기화 완료)와 nonzero native handle을 검사합니다. 이름은 `CheckRouteComponentName`으로 광고된 설정에 대조합니다. native 결과 false/미준비 count 0은 성공으로 처리하지 않습니다.

`InitRouteGuidance`는 route capability가 켜졌을 때만 `RouteGuidanceComponent0`를 추가하며, 4개 문자열 최대 길이 각 64, maneuver 저장량 10을 광고합니다. Core는 임의 이름/null 전체 component 요청으로 우회하지 않고 count/list에서 얻은 유효한 이름만 요청합니다. 자체 요청은 등록·연결·IdentificationAccepted(0)·AuthenticationSuccess(5) 이후 시도하며, 실패 시 5초 후 재시도하고 성공은 연결 세대당 한 번으로 제한합니다. shared `Iap2SvcStopRouteGuidanceUpdate`는 호출하지 않습니다. 연결 종료는 자기 listener/캐시만 정리합니다.

step 110의 route capability는 별도 검증된 iAP2 shim으로 활성화해야 합니다. Core 단독으로 capability 광고를 변경하지 않습니다. 원본 `RouteGuidance`가 꺼진 환경에서는 유선 연결이어도 자체 시작 요청만으로 안내 데이터를 받을 수 없습니다. 실제 폰/지도 앱의 지원과 실차 출력은 최종 통합 시험 대상입니다.

## 회전 전송 형식 확인

순정 `NativeCall.sendClusterParser`는 `0xF2` 형식을 `NavigationCluster.updateTPTurnListNew`로 전달한다. `libExSLNavi`의 `NaviDrivingAssistManager::sendClusterTBTListTPInfo_Android`에서 87바이트 버퍼, `F2` 헤더, byte 1의 회전 필드 수, byte 2~4의 아이콘, byte 5부터 UTF-16LE 이름을 확인했다. 비움은 `F2,00` 형식이다. 이 내부 TP 데이터는 순정 서비스를 통해 전달하며 직접 CAN을 전송하지 않는다.

일반 회전 아이콘은 V039 순정 DiPO의 `RouteGuidanceAnalyzer`에서 확인했습니다: 왼쪽 `46`, 오른쪽 `43`, 직진 `41`, 우측통행 U턴 `48`, 완만한 좌/우 `47/42`, 급한 좌/우 `45/44`(16진수)입니다. 같은 분기표는 통행 방향·교차로 종류·출구각을 함께 검사합니다. `ClusterIcon`도 이 조합만 허용하며 각도 누락이나 비정확한 각도를 자체 보완하지 않습니다.

확인 위치: `scratchpad/iap2lib/smali/com/tcc/iap2/Iap2Const$NotiType.smali`, `$RouteGuidanceUpdate`, `$RouteGuidanceManeuverUpdate`, `$LaneGuidanceInformation`, `$LaneInformation`, `$DrivingSide`, `$RouteGuidanceState`. 원본 자료는 저장소 밖에 보관한다.

## 차선 전송 형식과 변환 규칙 (2026-10-27)

상태의 lane 필드는 현재 차선 안내 index `16`, 전체 안내 수 `17`, 표시 여부 `18`입니다. 현재 회전 목록 `13`과 별도로 보관합니다. `LaneInformation` index 0, status 1, angles 2, highlighted angles 3을 파싱합니다. 추천은 highlighted angles로 결정하며 status 숫자에 임의 의미를 붙이지 않습니다.

순정 `libExSLNavi` 차선 JSON→구조체 변환 경로를 대조했습니다. 원본 파일은 저장소 밖 분석 경로에만 보관합니다. 81바이트 F1의 byte1은 차선 수입니다. 차선 슬롯 i의 byte `3+i`는 방향별 possibility 2비트 필드이며, j번째 방향은 bits `2*j..2*j+1`을 씁니다. direction은 byte `0x13+3*i+j`에 들어가므로 차선당 최대 3개입니다. possibility 2는 추천, 1은 비추천입니다. 고가/지하 마스크는 `0x43/0x45`의 LE 16비트입니다. 비움은 동일한 81바이트에서 F1 외 0입니다.

이 packing은 순정 변환 함수 `0x1936dc4`의 `0x1937218`(i*3), `0x1937650`(방향 저장), `0x193723c`(i 단위 증가), `0x193766a/0x1937676`(j*2, 폭2), `0x1937682`(possibility byte 저장)로 확인했습니다. 즉 possibility 위치는 `3+2*i`가 아닙니다.

방향 식별자는 순정 Baidu `convertDirectiontoAngleCode`와 `ConvertGuidance` 두 native 변환표를 대조하여 다음과 같이 연결했습니다: 0°→1, -45°→2, -90°→3, +45°→4, +90°→5, -135°→6, +135°→7, ±180°→8. 이는 두 표 사이의 의미 대응이며 iAP2에서 F1까지 동일 각도를 넣은 실차 검증은 아직 없습니다. 그 외 각도는 추측하지 않고 차선을 비웁니다.

차선 index는 0..N-1 또는 1..N만 허용하고 슬롯은 0..N-1로 변환합니다. 부분 갱신을 위해 캐시에는 원본 index를 보존합니다. index 오름차순이 물리적 왼쪽→오른쪽이라는 것은 현재 명시적 가정입니다. 순정 자료에서 그 물리적 순서의 증명은 찾지 못했습니다.

순정 DiPO switch에서 ContinueToFollowTheRoad(5)는 `AC`로 확인했습니다. 순정에 직접 대응하지 않는 ExitFerry(16), ChangeFerry(17), ChangeHighway(51)에는 자체 대체 아이콘을 만들지 않습니다. 회전교차로도 순정 분기에서 실제 처리하는 타입 19, 28, 29, 31~35와 정확한 각도 조합만 사용하며 출구 번호로 방향을 추정하지 않습니다.

좌측 통행 회전교차로는 순정 DiPO `pswitch_34f`에서 타입 31, junction 1, angle 0의 `C0`만 확인했습니다. 다른 타입·각도에 `C0`를 확대 적용하지 않습니다.
