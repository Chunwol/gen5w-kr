# 무선 프로젝션 연결 요청

브리지는 Bluetooth로 연결된 휴대폰을 현재 연결 후보로 확인합니다. 저장된 순정 무선 프로필이 없으면 V039 PhoneProjection의 첫 등록 경로를 한 번 요청합니다. 이 경로는 PhoneProjection 앱에 한정한 `START_SPP_CONNECT_FOR_CONNECTIVITY` 동작과 `PPManager.requestConnectSPP(address)`를 사용합니다. 요청은 등록 또는 연결 성공을 뜻하지 않습니다.

프로필이 있으면 CarPlay와 Android Auto 유형을 구분해 해당 플랫폼의 순정 프로필과 연결 상태를 읽습니다. 프로필이 활성화되어 있고 자동 연결이 허용된 경우에만 순정 PhoneProjection 연결 요청을 보냅니다. 브리지는 연결 소켓, iAP2 세션, Android Auto 전송을 직접 소유하지 않습니다. 작업 세대, 연결 후보, 유선 연결, 다른 프로젝션 소유권, 요청 기한을 확인해 취소된 작업의 후속 요청을 막습니다.

프로젝션 Wi-Fi 준비 상태도 별도로 관찰합니다. 진단에는 `ConnectivitySSID`·`ConnectivityPSK`의 존재 여부와 Wi-Fi AP 진행 상태만 남기며 자격 증명 값은 저장하거나 기록하지 않습니다. 일반 핫스팟의 `SSID`·`preSharedKey`는 별도 설정이므로 프로젝션 Wi-Fi 준비 판정에 대신 사용하지 않습니다. 브리지는 이 연결 흐름에서 프로젝션 Wi-Fi 자격 증명을 일반 핫스팟 값으로 덮어쓰지 않습니다.

V039 소스에서 순정 SPP 등록 요청과 CarPlay·Android Auto 프로필 경로, 별도 프로젝션 Wi-Fi 필드 및 AP 시작 경로를 확인했습니다. 이는 구현 근거이며 차량에서 순정 요청이 수락됐거나 등록·연결이 성공했다는 증거는 아닙니다. 차량의 `GEN5W-REPORT`에 프로필 등록·순정 연결 요청과 `projection-active`를 포함한 수락·활성 결과가 기록되기 전까지 실차 연결은 미검증입니다.

## 표시되는 진단 결과

- `profile-unavailable`: 현재 사용자에게 저장된 프로필을 읽지 못했습니다.
- `profile-mismatch`: 저장된 프로필 주소 또는 유형이 현재 연결 후보와 일치하지 않습니다.
- `profile-disabled` 또는 `auto-connect-disabled`: 차량 설정에서 해당 프로필 또는 자동 연결이 꺼져 있습니다.
- `cancelled`: 요청이 처리되는 동안 연결이 끊기거나 요청이 만료되어 순정 요청을 보내지 않았습니다.
- `oem-action-sent`: 순정 앱에 저장된 프로필 연결 요청을 전달했습니다. 연결 성공 여부는 아직 확인되지 않았습니다.
- `oem-requested`: 순정 첫 등록 경로의 요청 호출이 반환됐습니다. 프로필 등록이나 연결 성공을 뜻하지 않습니다.
- `progress=connecting`: 순정 상태가 같은 휴대폰의 연결 진행 중이라고 보고했습니다. 브리지는 추가 연결 요청을 보내지 않고 상태만 확인합니다.
- `projection-active`: 순정 PhoneProjection이 같은 휴대폰을 프로젝션 연결 상태로 보고했습니다.
- `timeout`: 정해진 시간 안에 순정 연결 상태가 확인되지 않았습니다.

`projection-active`와 관련 수락 결과를 담은 차량 진단 로그가 확인되기 전까지 차량 연결은 미검증입니다. 시험 때는 `GEN5W-REPORT`의 진단 결과를 보관하고, 주소·휴대폰 이름이 포함될 수 있는 상세 로그를 공개 이슈에 올리기 전 가리세요.
