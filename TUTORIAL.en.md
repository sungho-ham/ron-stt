# Install and use ron

**English** · [한국어](TUTORIAL.ko.md) · [README](README.md)

ron is a menu bar app that turns speech into text on your Mac and pastes it into your apps.

## 1. Install

You need macOS 13 or later. The app has been tested on Apple Silicon Macs.

Install these tools first. Skip any you already have.

- **[Xcode](https://apps.apple.com/app/xcode/id497799835)**: open it once after installation and complete the initial setup.
- **[CMake](https://cmake.org/download/)**: if you use Homebrew, run `brew install cmake` in Terminal.

Paste these commands into Terminal. The first setup needs an internet connection to download the source and the Small model (about 500 MB).

```bash
git clone https://github.com/sungho-ham/whisper-paste.git ron &&
cd ron &&
./scripts/setup.sh small &&
./scripts/build-app.sh --install &&
open "$HOME/Applications/ron.app"
```

If you already have the source, open its folder in Terminal and start with `./scripts/setup.sh small`.

When installation finishes, a preview window and a waveform icon in the menu bar appear. Next time, search for **ron** in Spotlight to open it.

## 2. Allow permissions

- **Microphone**: allow access when prompted on your first recording.
- **Accessibility**: open **System Settings → Privacy & Security → Accessibility** and enable ron. If it is missing, click `+` and add `~/Applications/ron.app`. Press `⌘⇧G` in the file picker to enter the path.
- **Automation**: when using Send with Ghostty, iTerm2, or Terminal, allow ron to control the app if prompted.

## 3. Speak and paste

1. Click a text field in an app, such as Notes or a chat app.
2. Press **Control + Option + Space (`⌃⌥Space`)** and speak. On your first recording, you may need to press it again after allowing microphone access.
3. Press the same shortcut again to stop recording.
4. When **Copied automatically** appears, press **`⌘V`** in your text field to paste.

If you edit the text in the preview, click **Copy** before pasting. You can also use **Copy** if automatic copying was skipped.

To send directly, click the intended text field and press **Control + Option + Return (`⌃⌥Return`)**. ron sends the text to the **Input target** shown in its window. Press Enter yourself to submit a message or run a command.

Use the waveform menu to change the recognition language or app language. The defaults are **Small model + Korean**.

## If something goes wrong

- **Cannot record**: enable ron in System Settings → Privacy & Security → Microphone, and check your microphone under Sound → Input.
- **Send does not work**: enable ron under Accessibility and retry. You can also use **Copy → `⌘V`**.
- **Cannot find the window**: click the waveform icon in the menu bar → **Open Preview**.
- **Metal error during installation**: install Metal Toolchain in Xcode → Settings → Components, then retry from `./scripts/setup.sh small`.
