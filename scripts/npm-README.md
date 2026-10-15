# ManaBar

Claude Code와 Codex의 남은 사용량을 macOS 메뉴바에서 확인하는 앱입니다.

## 지원 환경

- Apple Silicon Mac (arm64), macOS 13 이상
- Node.js 22 이상과 npm
- 사용하려는 서비스의 Claude Code 또는 Codex 로그인

## 설치와 실행

```sh
npm install -g mana-bar@beta
mana-bar
```

한 번 실행하려면 다음 명령을 사용합니다.

```sh
npx mana-bar@beta
```

앱은 npm 패키지에 동봉되어 있습니다. 설치 과정에서 Xcode로 빌드하거나 별도 서버를 설치하지 않습니다.
앱의 종료는 상세 패널 우측 상단의 전원 버튼을 누릅니다.

## 계정 연결

Claude는 해당 Mac의 Claude Code 로그인 정보를 키체인에서 읽습니다. 처음 연결할 때 macOS 승인이 필요할 수 있습니다.
Codex는 설치된 Codex 앱 또는 CLI의 로컬 로그인으로 사용량을 조회합니다.
연결이 없거나 조회에 실패하면 잔여량 대신 미연결·오류 상태를 표시합니다.
계정의 토큰·비밀번호·키체인은 패키지에 포함되지 않습니다.

## 베타 배포 상태

현재 베타 앱은 개발용 자체 서명을 사용하며 Apple 공증을 받지 않았습니다.
다운로드한 앱 실행을 macOS가 경고하거나 차단할 수 있습니다.
Developer ID 서명과 공증을 완료한 정식 배포는 별도로 안내합니다.
Claude 사용량 조회는 Claude Code의 비공개 엔드포인트에 의존하므로 서비스 변경에 따라 연결이 중단될 수 있습니다.

## 업데이트와 제거

실행 중인 ManaBar를 종료한 뒤 업데이트하고 다시 실행합니다.

```sh
npm install -g mana-bar@beta
mana-bar
```

제거 전 앱을 종료합니다.

```sh
npm uninstall -g mana-bar
```

## 라이선스와 출처

앱과 실행 명령은 MIT 라이선스입니다. 전체 조건은 `LICENSE`에 포함되어 있습니다.
아트워크 출처는 `THIRD_PARTY_NOTICES.txt`, 폰트 라이선스는
`app/ManaBar.app/Contents/Resources/Fonts/OFL-*.txt`에 포함되어 있습니다.
