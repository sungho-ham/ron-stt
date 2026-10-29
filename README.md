# Whisper Paste

A macOS menu bar app that turns speech into text locally with Whisper. Record, review, and paste into your preferred app.

## Features

- **Local transcription:** audio is processed on your Mac, with no cloud transcription, API key, or subscription.
- **Global shortcuts:** `⌃⌥Space` starts or stops recording; `⌃⌥Return` sends the final text to the selected input. Enter is never sent to submit a prompt.
- **Live preview and editing:** follow the accumulated transcript during recordings of up to five minutes, then review and edit the final result. The preview is resizable and can stay on top.
- **Automatic copy and paste:** final results copy to the clipboard by default while preserving anything newer you copied while waiting. Manual copy and explicit send are also available.
- **Automatic input tracking:** follows the active app, window, and supported terminal tab or split, including Ghostty, iTerm2, and macOS Terminal.
- **Models and languages:** multilingual Small and Medium models with Metal GPU acceleration. Korean is the default; Japanese, English, and automatic language detection are available.
- **App language:** switch the interface between English and Korean independently of the recognition language. Your choice is remembered, and the tutorial opens in the selected language.

## Requirements

- **macOS 13 or later.** Apple Silicon is the tested target; Intel Macs have not been separately verified.
- **Build tools:** Xcode or compatible Command Line Tools with Swift 5.9 or later, plus CMake. Full Xcode is recommended for the Metal shader tools. Setup can install CMake through an existing Homebrew installation.
- **Storage:** at least 4 GB of free space recommended for source, builds, and models. The two model downloads total about 2.02 GB.
- **Microphone:** uses the system's default audio input device.
- **Internet during setup:** needed to download source and models. Transcription works offline afterward.
- **macOS permissions:** Microphone for recording, Accessibility for general app and clipboard-based delivery, and Automation when sending to supported terminals. Grant permissions in System Settings as described in the tutorial.

Python, ffmpeg, and Hammerspoon are not required to install or run the app.

## Installation & Usage

Build and install locally, grant macOS permissions, and follow the first-recording walkthrough:

**[English tutorial](TUTORIAL.en.md) · [한국어 튜토리얼](TUTORIAL.ko.md)**

The tutorials also cover model settings, updates, local signing, troubleshooting, and removal.

## License

Whisper Paste is released under the [MIT License](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for dependency and model licenses.
