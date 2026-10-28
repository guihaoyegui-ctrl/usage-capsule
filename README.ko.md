# Usage Capsule

[简体中文](README.zh-CN.md) · [English](README.md) · [日本語](README.ja.md) · **한국어**

Codex의 5시간 및 주간 한도를 확인하는 작은 macOS 데스크톱 위젯입니다. 광택 있는 어두운 유리, 따뜻한 금속 테두리, 다섯 단계 색상을 **184 × 60 pt** 크기로 표시합니다.

![Usage Capsule과 개요 패널. 예시 데이터입니다](docs/preview-ko.png)

## 기능

- 5시간 및 주간 잔여 한도, 초기화 시각과 카운트다운.
- 마우스를 올리면 개요 표시, 클릭하면 고정, × 또는 Escape로 닫기.
- 최근 7일간 Token 소비량을 날짜별 셀로 확인.
- 잔여량에 따른 다섯 단계 색상. 50% 부근에서도 밝고 선명한 표시.
- 위젯 전체 영역에서 드래그. 메뉴 막대, 100–150% 확대, 항상 위에 표시 지원.
- 중국어 간체, 영어, 일본어, 한국어. 시스템 언어 자동 선택과 수동 변경.
- 사용 가능한 초기화 카드 표시. 0.8초 길게 누르면 확인 창이 열리며, 사용자가 명시적으로 확인한 후에만 요청합니다. 취소나 Escape는 카드를 소비하지 않습니다. 데모에서는 사용할 수 없습니다.
- Codex 로그인이 만료되면 연결을 다시 만들고 한 번 재조회합니다. 인증이 계속 실패하면 오래된 잔여량을 숨기고 다시 로그인하도록 안내합니다.

- 개별 선택한 작업의 자동 재개를 지원합니다. 개요 또는 메뉴에서 **자동 재개**를 열어 작업을 선택하세요. 한도 소진과 명확한 한도 초과 오류를 감지한 뒤, 한도가 회복되면 원래 대화를 이어갑니다. 선택 해제 시 대기 중인 명령을 취소할 수 있으며 이미 시작된 작업은 Codex에서 중지합니다. [동작 및 제한](docs/AUTO_RESUME.md).

## 요구 사항과 설치

**Apple Silicon Mac, macOS 13 이상, Xcode Command Line Tools**가 필요합니다. 실제 사용량을 보려면 로컬 Codex CLI에 로그인되어 있어야 합니다.

Codex에 다음과 같이 요청할 수 있습니다:

> $skill-installer로 https://github.com/guihaoyegui-ctrl/usage-capsule의 skills/usage-capsule을 설치한 다음, $usage-capsule로 내 Mac에서 앱을 빌드하고 설치한 뒤 시작해 주세요.

직접 설치하려면 저장소를 다운로드하고 해당 폴더에서 실행합니다:

```sh
zsh skills/usage-capsule/scripts/capsule.sh doctor
zsh skills/usage-capsule/scripts/capsule.sh install
zsh skills/usage-capsule/scripts/capsule.sh start
```

로컬에서 빌드한 앱은 `~/Applications/Usage Capsule.app`에 설치됩니다. 현재는 임시 서명된 미리보기 버전이며 Developer ID 공증을 받지 않았습니다. Gatekeeper를 끄지 말고 소스를 검토한 후 빌드하세요. 컴파일러가 없으면 `xcode-select --install`을 실행합니다.

위젯을 오른쪽 클릭하거나 메뉴 막대 아이콘에서 설정, 새로고침, 숨기기, 종료를 선택할 수 있습니다. 설정에서 한국어를 선택하거나 `zsh skills/usage-capsule/scripts/capsule.sh language ko`를 실행하세요.

`preview`는 예시 PNG를 생성합니다. `demo`는 설치된 앱이 정지된 상태에서 데모 창을 엽니다. 두 모드 모두 계정 사용량을 조회하지 않습니다. Skill 설치만으로 앱이 시작되지는 않으며, 클라우드 전용 환경에서는 Mac 데스크톱에 창을 표시할 수 없습니다.

## 데이터와 개인정보

60초마다 로컬 Codex app-server에서 계정 사용량 확인 자체는 모델 생성 턴을 만들지 않습니다. 자동 재개가 실행되면 사용 한도가 소모됩니다. 기존 Codex 로그인을 사용하고 개발자 서버나 분석 서비스로 데이터를 보내지 않습니다. 자세한 내용은 [Privacy](docs/PRIVACY.md)를 참고하세요.

이 앱은 커뮤니티 프로젝트이며 OpenAI 공식 제품이 아닙니다. 일별 소비량과 초기화 카드 지원은 CLI와 계정에 따라 달라집니다. 알 수 없는 값은 0으로 처리하지 않습니다. [검증 범위](docs/VALIDATION.md)와 [문제 해결](docs/TROUBLESHOOTING.md)도 확인해 주세요.

현재 미리보기에는 오픈소스 라이선스가 아직 지정되지 않았습니다.
