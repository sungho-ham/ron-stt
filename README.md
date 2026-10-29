# ron

**A local speech-to-text app for macOS, powered by Whisper.**

Dictate naturally, review and edit your transcription, then paste it into any app. Everything runs locally on your Mac—no cloud transcription, API key, or subscription required.

## Features

- **Private, on-device speech-to-text:** Transcribe speech locally using Whisper. Your audio stays on your Mac, with no cloud transcription or internet connection required after setup.
- **Global keyboard shortcuts:** `⌃⌥Space` starts or stops dictation; `⌃⌥Return` pastes the final text into your selected input. Enter is never sent to submit a prompt.
- **Live transcription preview:** Follow the accumulated transcript while recording for up to five minutes. Review and edit the final text before sending it. The preview window is resizable and can stay on top.
- **Copy and paste automatically:** Completed transcriptions are copied to the clipboard by default, without overwriting anything newer you've copied. Manual copying and explicit sending are also supported.
- **Smart input tracking:** Automatically tracks your active app, window, and supported terminal tab or split, including Ghostty, iTerm2, and macOS Terminal, so your text goes to the intended destination.
- **Multilingual speech recognition:** Supports Korean (default), Japanese, English, and automatic language detection using multilingual Whisper Small and Medium models with Metal GPU acceleration.
- **English and Korean interface:** Switch the app interface independently of the transcription language. Your preference is remembered, and the tutorial opens in your selected language.

## Requirements

- **macOS 13 or later.** Apple Silicon is the tested target; Intel Macs have not been separately verified.
- **Build tools:** Xcode or compatible Command Line Tools with Swift 5.9 or later, plus CMake. Full Xcode is recommended for the Metal shader tools. Setup can install CMake through an existing Homebrew installation.
- **Storage:** at least 4 GB of free space recommended for source, builds, and models. The tutorial starts with the Small model (about 500 MB); Medium is optional.
- **Microphone:** uses the system's default audio input device.
- **Internet during setup:** needed to download source and models. Transcription works offline afterward.
- **macOS permissions:** Microphone for recording, Accessibility for general app and clipboard-based delivery, and Automation when sending to supported terminals. Grant permissions in System Settings as described in the tutorial.

Python, ffmpeg, and Hammerspoon are not required to install or run the app.

## Installation & Usage

Build and install locally, grant macOS permissions, and follow the first-recording walkthrough:

**[English tutorial](TUTORIAL.en.md) · [한국어 튜토리얼](TUTORIAL.ko.md)**

The tutorials cover installation, permissions, your first recording, and common problems.

## License

ron is released under the [MIT License](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for dependency and model licenses.
