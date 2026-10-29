# ron 설치 및 사용

[English](TUTORIAL.en.md) · **한국어** · [README](README.md)

말한 내용을 Mac에서 텍스트로 바꾸고 원하는 앱에 붙여넣는 메뉴바 앱입니다.

## 1. 설치하기

macOS 13 이상의 Mac이 필요합니다. Apple Silicon Mac에서 동작을 확인했습니다.

먼저 아래 도구를 설치하세요. 이미 설치되어 있다면 건너뛰세요.

- **[Xcode](https://apps.apple.com/app/xcode/id497799835)**: 설치 후 한 번 열어 초기 설정을 마치세요.
- **[CMake](https://cmake.org/download/)**: Homebrew를 사용한다면 터미널에서 `brew install cmake`로 설치할 수 있습니다.

터미널에 아래 명령을 붙여넣으세요. 소스와 Small 모델(약 500MB)을 내려받으므로 처음에는 인터넷이 필요합니다.

```bash
git clone https://github.com/sungho-ham/whisper-paste.git ron &&
cd ron &&
./scripts/setup.sh small &&
./scripts/build-app.sh --install &&
open "$HOME/Applications/ron.app"
```

이미 소스를 받았다면 해당 폴더에서 `./scripts/setup.sh small`부터 실행하세요.

설치가 끝나면 미리보기 창과 화면 위쪽 메뉴바에 파형 아이콘이 나타납니다. 다음부터는 Spotlight에서 **ron**을 검색해 실행하세요.

## 2. 권한 허용하기

- **마이크**: 첫 녹음 때 나타나는 요청에서 허용하세요.
- **손쉬운 사용**: **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**에서 ron을 켜세요. 목록에 없으면 `+`를 누르고 `~/Applications/ron.app`을 추가하세요. 파일 선택창에서 `⌘⇧G`를 누르면 경로를 입력할 수 있습니다.
- **자동화**: Ghostty, iTerm2, Terminal에 보내기를 사용할 때 제어 권한 요청이 나오면 허용하세요.

## 3. 말하고 붙여넣기

1. 메모나 채팅 앱에서 글을 넣을 입력칸을 클릭하세요.
2. **Control + Option + Space (`⌃⌥Space`)**를 누르고 말하세요. 처음에는 마이크 권한을 허용한 뒤 다시 눌러야 할 수 있습니다.
3. 같은 단축키를 다시 눌러 녹음을 끝내세요.
4. **자동 복사 완료**가 표시되면 입력칸에서 **`⌘V`**로 붙여넣으세요.

미리보기에서 문장을 수정했다면 **복사** 버튼을 누른 뒤 붙여넣으세요. 자동 복사가 되지 않았을 때도 **복사** 버튼을 사용하면 됩니다.

바로 보내려면 입력할 곳을 클릭하고 **Control + Option + Return (`⌃⌥Return`)**을 누르세요. ron 창의 **입력 대상**에 표시된 곳으로 텍스트를 보냅니다. Enter는 대신 누르지 않으므로 메시지 전송이나 명령 실행은 직접 하세요.

메뉴바 파형 아이콘에서 인식 언어와 화면 언어를 바꿀 수 있습니다. 기본값은 **Small 모델 + 한국어**입니다.

## 잘 안 될 때

- **녹음이 안 돼요**: 시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 ron을 켜고, 사운드 → 입력에서 마이크를 확인하세요.
- **보내기가 안 돼요**: 손쉬운 사용에서 ron을 허용하고 다시 시도하세요. 우선 **복사 → `⌘V`**로도 사용할 수 있습니다.
- **창이 안 보여요**: 메뉴바 파형 아이콘 → **미리보기 열기**를 선택하세요.
- **설치 중 Metal 오류가 나요**: Xcode → Settings → Components에서 Metal Toolchain을 설치하고 `./scripts/setup.sh small`부터 다시 실행하세요.
