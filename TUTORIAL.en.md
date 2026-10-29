# Whisper Paste Installation and Usage Tutorial

**English** · [한국어](TUTORIAL.ko.md) · [README](README.md)

Whisper Paste is a menu bar app that records from your microphone with a shortcut and converts speech to text **on your Mac** using `whisper.cpp`. Review provisional results while recording, then edit the final text and paste it into your input field. The app does not send Enter to submit a prompt.

## 1. Prerequisites and storage

- macOS 13 or later. Apple Silicon Macs are the current implementation and verification target. Intel Macs have not been separately verified.
- Xcode or compatible Command Line Tools with Swift 5.9 or later. Full Xcode is recommended because Metal shader compilation tools are also required.
- CMake. If it is missing, setup installs it through an existing Homebrew installation.
- A microphone. Choose your device in System Settings → Sound → Input. The app uses the default input device. Do not change devices during recording.
- Internet during installation: source is downloaded from GitHub and models from Hugging Face. Transcription does not need internet afterward.
- About 2.02 GB of model files (decimal): Small is 487,601,967 bytes; Medium is 1,533,763,059 bytes. At least 4 GB of free space is recommended to also accommodate source and builds.
- Python, ffmpeg, Hammerspoon, API keys, and subscriptions are not required.

For Korean and Japanese, use the **multilingual `small` / `medium`** models. `.en` models are English-only. The default settings are Small + Korean + Metal GPU + preview during recording + automatic copy after transcription.

## 2. First installation

If you have not cloned the repository yet, run `git clone https://github.com/sungho-ham/whisper-paste.git` from your preferred directory.

In Terminal:

```bash
cd /path/to/whisper-paste
./scripts/setup.sh
swift test
./scripts/build-app.sh --install
./scripts/doctor.sh
open "$HOME/Applications/Whisper Paste.app"
```

`setup.sh` builds a pinned commit of whisper.cpp v1.9.5 from source and downloads both models. Downloaded files are used only after SHA-256 verification. Interrupted downloads resume from `.partial` files. To start with Small only, run `./scripts/setup.sh small`; to add Medium later, run `./scripts/download-models.sh medium`.

If Homebrew is also missing, install [CMake from its official website](https://cmake.org/download/) and make sure `cmake` is on your PATH, or follow the [official Homebrew instructions](https://brew.sh/) and run `brew install cmake`. If developer tools are missing, start installation with `xcode-select --install`. Complete any first-launch, license agreement, or additional-component prompts in Xcode yourself. If you get an error that `xcrun metal` is unavailable, install Xcode's Metal Toolchain component.

Replace `/path/to/whisper-paste` above with the actual path where you cloned the repository. The app bundles its engine, so you can move the repository after installation. Models are read from the fixed locations below.

```text
~/Applications/Whisper Paste.app
~/Library/Application Support/WhisperPaste/models/ggml-small.bin
~/Library/Application Support/WhisperPaste/models/ggml-medium.bin
```

## 3. macOS permissions

### Microphone

1. Start recording from the menu bar waveform icon or the preview window.
2. Allow microphone access when macOS asks.
3. If you previously denied access, enable **System Settings → Privacy & Security → Microphone → Whisper Paste**.

Launching the app alone does not turn on the microphone. Permission is requested on the first recording. The app requesting access is named Whisper Paste.

### Accessibility

This permission lets the app identify the focused window and input field in general apps and send `⌘V`.

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Click `+`, add `~/Applications/Whisper Paste.app`, and enable it. Use `⌘⇧G` in the file picker to enter the path.
3. If a permission message appears on the first paste, grant access and try again. Quit and reopen the app if needed.

The app menu also has entries that open these two settings pages. You must grant permissions yourself in macOS. **Screen Recording, Full Disk Access, and Input Monitoring permissions are not requested.** Recording, transcription, and manual copy work without Accessibility permission.

### Automation — automatic terminal input tracking

The first time you send to Ghostty, iTerm2, or macOS Terminal, allow macOS's request for **Whisper Paste to control that app**. If you previously denied access, enable the target app under **System Settings → Privacy & Security → Automation → Whisper Paste**. You can also open this page from “자동화 권한 설정…” (Automation permission settings…) in the app menu. This permission is not needed when only pasting into general apps. Focus tracking alone does not trigger permission prompts. After granting permission on the first send, you may need to select the intended tab again and resend.

Ghostty's `macos-applescript` setting is enabled by default; enable it if you turned it off. You do not need to enable iTerm2's Python API server. Direct input to Ghostty and single-line input to iTerm2 work without Accessibility permission for clipboard paste, but **macOS Terminal, multiline or tab-containing input to iTerm2, and paste into general apps also require Accessibility permission**.

## 4. Entering your first prompt

The preview window opens when the app launches. As a menu bar app, it does not show an icon in the Dock. Opening it again through Spotlight while it is already running also shows the preview. You can also use the menu bar waveform icon → “미리보기 열기” (Open preview).

Since 0.5.0, the **pin button** at the top right of the window and **“항상 위에 표시”** (Always on Top) in the menu toggle whether the preview stays on top. The enabled state uses a filled pin with a soft accent color; the disabled state uses a gray outline pin. It is enabled by default, and the last choice persists across launches. You can change it while recording.

Drag the window's edge or corner to resize it down to **360 pt wide**. The previous minimum was 700 pt. At narrow widths, action buttons use two rows and shortcut hints wrap. Pressing **⌘W** while the preview has focus closes it, just like its close button. Closing during recording or pending transcription cancels the work and clears the content, so copy anything you want to keep first.

1. **Click the document or text field you want to type into**, for example in TextEdit.
2. Press **Control + Option + Space (`⌃⌥Space`)**. The menu bar icon turns into a red recording indicator.
3. Say something, for example “오늘 회의 내용을 세 가지 항목으로 요약해 줘.” (“Summarize today's meeting in three points.”). Korean is the default recognition language.
4. The first preview transcription starts after about 1.5 seconds of audio. Later jobs start at least one second apart, and only after the previous job finishes. Actual inference time adds to the delay before text appears. The model is prepared when the app launches; the first result can take longer if preparation is still in progress.
5. Press **`⌃⌥Space`** again to stop recording.
6. By default, the final result is **copied automatically** after transcription. When “자동 복사 완료” (Automatic copy complete) appears, paste into your chosen field with `⌘V`. If you copied something else while waiting after stopping the recording, that newer content is preserved and automatic copy is skipped.
7. You can also review and edit the preview text, then use **Control + Option + Return (`⌃⌥Return`)** or “입력 대상에 보내기” (Send to input target). If you edit after automatic copy, click “복사” (Copy) again or use this shortcut to send the edited text.
8. Select the intended app's input field and press `⌃⌥Return` to send there. Clicking the send button inside Whisper Paste uses the previous external input target. Check the result and submit the prompt yourself.

Line breaks inserted by the engine between segments are joined with spaces into a continuous sentence. Line breaks you add manually in the preview are preserved.

Automatic copy replaces the clipboard with the transcription and leaves it there, like a normal copy operation. Disable “인식 완료 후 자동 복사” (Automatically copy after transcription) in the menu to use manual copy instead. The paste shortcut restores the clipboard from immediately before the paste after about 1.5 seconds. With automatic copy enabled, that clipboard content is usually the transcription. If you copy something else in the meantime, it is not overwritten.

If the target has closed or its input position cannot be verified, use “복사” (Copy) and paste manually with `⌘V`. Automatic paste can only confirm that the target app was activated and a key event was sent. It cannot verify successful text insertion in every app, so check the destination field.

### 4.1. Automatic focus tracking — since 0.4.0

The input target automatically follows **the currently focused app, window, and tab**. Connect/disconnect buttons and menu items have been removed, and saved connection settings from earlier versions are deleted. Targets are remembered only while the app is running.

1. Click the intended app's input field or the terminal tab or split containing your CLI input.
2. Check the app, window, and input area in Whisper Paste's **“입력 대상 · 자동 추적”** (Input target · Automatic tracking) display.
3. Record with **⌃⌥Space**. Switching windows or tabs while recording also updates the displayed target.
4. To send immediately, press **⌃⌥Return**. The app looks up and fixes the target at that moment, stops recording, and sends the final transcription of the full audio.
5. To edit before sending, stop recording with **⌃⌥Space**, edit the completed text, then press **⌃⌥Return** or “입력 대상에 보내기” (Send to input target).
6. **No Enter key is added.** Submit the prompt yourself at the destination.

App switches are detected through macOS activation events. Changes to windows, tabs, splits, and general input fields within the same app are checked every 0.75 seconds, so the display may lag by that interval plus lookup time. Sending performs a fresh lookup instead of relying only on the displayed cache. Interacting with Whisper Paste preserves the previous external target. The previous input field in a general app is remembered by its Accessibility identity.

When a send request is accepted, **“전송 대상 확정”** (Send target fixed) appears. Switching windows or tabs while final transcription is pending does not change that send's destination. The next send follows the new focus. If the external app changes during target lookup or the fixed target closes, the result is kept without redirecting it elsewhere.

| Target | Input method and scope |
|---|---|
| Ghostty | Looks up the current window, selected tab, and focused split, then sends direct paste input to that area |
| iTerm2 | Looks up the current window, tab, and session. Sends single-line text directly without a newline; for multiline or tab-containing text, activates the session and pastes |
| macOS Terminal | Looks up the current window and selected tab, then activates the saved window and tab and pastes. Stops if the last target check fails |
| Other apps | Remembers the current window and input element through Accessibility, then restores, rechecks, and pastes. There is no common API for selecting tabs in every app; use “복사” (Copy) if the input element cannot be verified |

Clipboard paste activates the target app and moves focus. Direct input does not move focus. When automatic copy is enabled, the final text is copied to the clipboard independently of whether delivery uses direct input.

Since 0.5.1, sending through clipboard paste does not hide the preview window. Clicking the preview focuses Whisper Paste like a normal window; sending activates the destination app and transfers keyboard focus. With the pin enabled, the preview stays on top. With it disabled, another window may cover the preview, but sending does not hide or close it. This removes hide/show flicker, and a window you closed yourself is not reopened after a successful send.

After a successful send, the result remains in the app for copying, but repeated sends of the same result are blocked. Editing sends **the entire edited text** again; it does not automatically replace text already inserted. Use a new recording for a new sentence. While waiting, “취소 / 비우기” (Cancel / Clear) cancels the pending send. Once the actual input command is being sent, it cannot be canceled.

Input follows the CLI's current cursor and selection, so text is not always appended at the end. The app does not determine whether the destination tab is waiting for a Codex prompt. If a shell, another program, or an approval screen is receiving input, text goes there. Multiline paste follows the receiving program's paste handling and the terminal's confirmation settings. The implementation targets the scripting interfaces of Ghostty 1.3.1 and iTerm2 3.6.9.

## 5. Preview versus final results

- The preview **accumulates all content from the start of recording**. Earlier text is not removed after 30 seconds, though text in the currently processed segment can change. Use the existing recording shortcut without additional configuration.
- Once the pending segment reaches 20 seconds, the app looks for about 0.5 seconds of quiet, preserves the preceding segment, and transcribes the next one. Preserved text is not recomputed each time. Repeated speech is not removed by string deduplication.
- If continuous speech or background noise prevents finding a quiet point, the current segment is kept beyond 30 seconds. Audio is not cut off solely because of elapsed time, but longer segments can make preview updates slower. Splitting is based on audio level and can be inaccurate for quiet speech or noise.
- At the bottom of the preview, scrolling follows new text. If you scroll up to read earlier text, your reading position is preserved.
- Only one transcription job runs at a time. The next segment is processed after the previous job finishes.
- The selected model is prepared at app launch and stays in memory, rather than being reloaded for every request. Changing the model, language, or GPU setting, or an engine crash, causes preparation again. Quitting the app releases model memory.
- Stopping cancels any running preview and transcribes **the full recording** again. It does not simply join provisional segments that may have missing or duplicate words at their boundaries.
- The Small/Medium models and final decoding settings remain unchanged. Preview text is not used as the final transcription's prompt. Short early previews and words at segment boundaries can be unstable, but the final result is recomputed from the complete original audio.
- Recording is limited to five minutes. Reaching the limit automatically stops recording and starts full transcription.
- Closing the window or clicking “취소 / 비우기” (Cancel / Clear) cancels recording and active transcription and clears the result.
- Starting a new recording with an unsent result asks whether to discard it first. Already-sent results are cleared immediately when a new recording starts.
- The send shortcut also works during recording or final transcription. Only the final result is sent. Text cannot be edited during recording; edit it after transcription finishes.
- Almost-silent or very short input skips transcription. This is a simple audio-level check, not full voice activity detection (VAD). Background noise can still produce incorrect text, so review the result.

Whisper is not a dedicated streaming model that continuously emits finalized tokens. This app re-transcribes short recording snapshots. It does not continuously edit the destination field during recording; pressing send inserts the final result.

## 6. Model, language, and speed settings

From the menu bar waveform icon:

| Setting | How to use it |
|---|---|
| 항상 위에 표시 (Always on Top) | On by default. Linked to the pin button; can be changed while recording |
| 모델 → Small (Model → Small) | Prioritizes responsiveness. The default |
| 모델 → Medium (Model → Medium) | Compare when Small makes too many mistakes. Uses more time and memory |
| 인식 언어 (Recognition language) | 한국어 / 日本語 / English / 자동 감지 (Automatic detection) |
| 화면 언어 / App Language | 한국어 / English. Independent of recognition language; Korean by default. Applies immediately and persists across launches |
| 녹음 중 미리보기 (Preview during recording) | Turn off to transcribe only after stopping. Reduces battery and GPU use |
| 인식 완료 후 자동 복사 (Automatically copy after transcription) | On by default. Copies the final result while preserving anything newer you copied while waiting |
| Metal GPU 사용 (Use Metal GPU) | On by default. Turn off and retry in CPU mode if Metal errors occur |

Settings persist across launches. Except for Always on Top and App Language, the settings above cannot be changed during recording or transcription. Keeping a model loaded increases idle memory use compared with earlier versions, and frequent previews can increase computation and battery use. For Korean mixed with code or English abbreviations, try Korean first; compare automatic detection for multilingual speech. Automatic detection is imperfect too, and proper names, code, and punctuation may need editing.

Use **화면 언어 → English** in the menu bar to switch from the default Korean interface. Use **App Language → 한국어** to switch back. Menus, buttons, statuses, and app error messages update immediately, including while recording; transcription text and the recognition language stay unchanged. “Usage Tutorial” opens the document for the selected app language. Permission dialogs displayed by macOS follow the system language settings. Korean labels elsewhere in this tutorial refer to the default interface, with English equivalents alongside them.

Shortcuts are fixed in the current version. To change them, update the keys/modifiers in `Sources/WhisperPaste/HotKeys.swift` together with the app's shortcut hints, then rebuild. If another app uses the same shortcut, change that app's shortcut or use Whisper Paste's menus and buttons.

To compare the actual recording load of Small and Medium, follow the [dictation performance measurement guide (Korean)](PERFORMANCE.ko.md) and run `python3 scripts/profile-resources.py --label small`. It records overall GPU utilization and app/engine CPU and memory use under `~/tmp`, without administrator privileges. Energy Impact alone cannot tell you how responsive a model is.

## 7. Launch at login and updates

To launch automatically at login, manually add `~/Applications/Whisper Paste.app` under **System Settings → General → Login Items & Extensions → Open at Login**. The installation script does not change login items.

To update:

```bash
cd /path/to/whisper-paste
# Quit Whisper Paste from the menu bar first
./scripts/setup.sh
swift test
./scripts/build-app.sh --install
open "$HOME/Applications/Whisper Paste.app"
```

### Keep signing with the same certificate

You can create a local code-signing certificate for use on this Mac without an Apple developer account. After running setup once, subsequent builds use the same certificate.

```bash
./scripts/setup-signing.sh
./scripts/build-app.sh --install
```

- The certificate is named **Whisper Paste Local Signing** and is valid for ten years from creation. Its certificate and private key are kept in the default user keychain.
- Temporary private-key export files and temporary passwords are removed after setup. Do not put private keys in the repository or work logs. Only `/usr/bin/codesign` is pre-authorized for the new key.
- The certificate fingerprint and keychain path are saved in `~/Library/Application Support/WhisperPaste/signing.plist`. This file contains no private key or password.
- With a certificate configured, signing failure stops the build. The script does not silently fall back to ad-hoc signing. Development environments without a configuration retain ad-hoc signing and an explanatory message.
- System and user certificate trust settings are not changed. This local certificate does not replace Apple Developer ID signing or notarization for distribution.

The first switch from an older ad-hoc signature to the new certificate may require granting macOS permissions once again. If input into Firefox or another app fails despite Accessibility being enabled, refresh it in this order: **quit Whisper Paste → remove the existing Whisper Paste entry from Accessibility in System Settings → add and enable `~/Applications/Whisper Paste.app` again → reopen the app**. Microphone and Accessibility permissions are separate.

Keeping the same certificate can preserve the certificate-based app identity requirement even when the binary changes. Actual permission persistence still depends on macOS policy, app path, certificate changes, and other factors; it is not guaranteed in every case. Shared distribution requires a separate setup for Apple developer signing, notarization, and update delivery.

## 8. Troubleshooting

| Symptom | What to check |
|---|---|
| No menu bar icon | Check whether the app is running and whether limited menu bar space has hidden it. Open the app again from Finder |
| Shortcut does nothing | Check for another app using the shortcut or a conflict with VoiceOver's Control+Option. First test recording from the menu |
| Microphone only shows quiet input | Check the system's default input device, input volume, and Microphone permission. Check Bluetooth microphones too |
| Transcription is slow | Choose Small, disable preview, and enable Metal. Allow model preparation time just after launch or a model change |
| Earlier text disappears after 30 seconds | Version 0.3.1 and later use a fully accumulated preview. Quit the older app, replace it with the new build, and reopen |
| Missing model or engine | Run `./scripts/setup.sh`, then `./scripts/build-app.sh --install` |
| Model checksum mismatch | Check and remove the reported `.partial` file, then retry the download. An existing valid model is not overwritten before verification succeeds |
| Paste fails | Grant Accessibility permission and check focus in the original input field. Compare with “복사” (Copy) followed by manual paste |
| Text seems likely to go to the wrong app | Check the automatic input tracking display, click the desired input field, and send. Clicking Whisper Paste preserves the previous external target |
| Metal execution error | Disable “Metal GPU 사용” (Use Metal GPU) in the menu and retry |
| Cannot find the window on an external display or in full screen | Use menu → “미리보기 열기” (Open preview). The window moves to the current workspace |
| Terminal target lookup fails | Check Automation permission and whether the target app is running. For Ghostty, check that `macos-applescript` is enabled |
| No input target is shown | Click the intended window, tab, or text field and resend. Restarting the target app does not require manual connection |
| Cannot verify an input field in a general app | Check Accessibility permission. If the app does not expose an input element, use “복사” (Copy) and paste manually |
| Multiline input or paste into Terminal fails | Check Accessibility permission. Retry without switching windows or tabs during paste |

Diagnostics and tests:

```bash
./scripts/doctor.sh
swift test
./scripts/smoke-test.sh
```

`swift test` runs core tests without models and skips real-model tests. Accumulated-preview coverage includes the 30- and 60-second boundaries, five minutes of uninterrupted input ranges, preservation of repeated sentences, silence, retries after failures or empty results, and ignoring older responses in a new recording. `smoke-test.sh` synthesizes test sentences **to files only** using the macOS Yuna voice. It uses the new engine under `.build/engine/bin` to compare the existing CLI and resident-engine results and repeated processing times for Small and Medium. It also checks reuse after transcription cancellation, full audio longer than 30 seconds, and accumulated previews split from audio longer than a minute. Set `WHISPER_PASTE_TEST_BIN_DIR` to choose a different engine folder. The Yuna voice must be installed. The test does not use the microphone, play audio, or paste into an input field. Even if it passes, check the real microphone, global shortcuts, and input to other apps separately using section 4.

To check the engine separately using saved sample audio, without a microphone:

```bash
./.build/engine/bin/whisper-cli \
  -m "$HOME/Library/Application Support/WhisperPaste/models/ggml-small.bin" \
  -f ./vendor/whisper.cpp/samples/jfk.wav -l en -nt
```

Focus unit tests cover app/window/tab/split changes, preservation of the previous external target, ignoring older lookup responses, process restarts, and a fixed send target while final transcription is pending. To check terminal integration separately, run `python3 scripts/terminal-smoke-test.py`. Python 3 is needed only for this development check. It creates dedicated test windows in Ghostty, iTerm2, and Terminal and checks automatic tracking, fresh lookups before sending, and delivery to the designated target; it does not send test sentences to existing CLI sessions. The test runner needs Automation permission. Without Accessibility permission, it skips actual paste into Terminal and checks only window selection.

## 9. Trying Ctrl+G in Codex CLI

VS Code is recommended for editing dictated text with the keyboard. The command below chooses an editor only for that Codex invocation. It does not change the existing `codex` binary or shell configuration. It assumes VS Code is installed at `/Applications/Visual Studio Code.app`.

```bash
VISUAL='"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --wait' codex
```

1. Press **Control + G** in the Codex input field, not Command + G.
2. In VS Code, click the input position in the temporary prompt file.
3. Record with Whisper Paste's `⌃⌥Space`, then stop with the same shortcut.
4. Once the final result is copied automatically, paste with `⌘V` in VS Code and edit it. You can add text through multiple recordings.
5. Save with `⌘S` and close **that file's tab**. Once `--wait` ends, the text returns to the Codex input field. You do not need to quit all of VS Code.
6. Return to the terminal, check the text, and submit it yourself.

In the current version, provisional recording results appear in Whisper Paste's preview window. This editor configuration alone does not automatically reflect provisional text in VS Code or the Codex input field. Continuously updating text there would require an additional integration.

Official behavior: [OpenAI Docs — Prompt editor](https://learn.chatgpt.com/docs/cli-customization#prompt-editor). `VISUAL` takes precedence; `EDITOR` is used if it is unset.

### English terms in Korean sentences

English terms can appear with Korean recognition selected, but pronunciation and context may cause them to be transcribed in Hangul. The app currently has no user terminology dictionary. Two possible additions could help guide spelling:

- **Recognition hints:** provide the spellings you use, such as `Whisper, Codex, Kubernetes, API`, through whisper.cpp's `initial_prompt`. This influences recognition probabilities but does not guarantee spelling.
- **Spelling replacement dictionary:** apply registered mappings such as `쿠버네티스 → Kubernetes` to transcription results. This can make registered spellings consistent, but it cannot recover words misrecognized as something else. Choose automatic replacements carefully when expressions overlap with ordinary Korean words.

Neither feature is implemented in the installed app yet. Both can be implemented locally; an external AI API is not required.

## 10. Data handling and removal

Automatic focus tracking keeps only app, window, session, and input-element identities and display names in memory while running. It does not read existing input-field text or save target information to settings or logs. Older connection settings are deleted on launching 0.4.0. Automation requests are passed through standard input using a JSON file in a temporary folder private to the current user, then removed after completion. A forced termination can leave `whisper-paste-terminal-UUID` folders in the OS temporary directory. General apps, Terminal, and multiline input to iTerm2 use the clipboard during delivery.

- The app itself makes no network requests. Transcription uses the bundled whisper-worker and local models, with app/engine communication through internal pipes. No HTTP server or externally accessible port is opened. The CLI is also bundled for comparison checks.
- Recordings are kept in memory, with temporary WAV files created for transcription. Results are passed through pipes, without permanent files. Temporary folders are private to the current user (0700 permissions) and removed after each job.
- A forced app or system termination can leave `whisper-paste-UUID` files in the OS temporary directory. With the app closed, inspect and remove only the matching folders in your own temporary directory. No permanent transcripts or app usage history are stored.
- By default, final text is copied automatically and remains on the clipboard. A separate clipboard history app may store it. Even with automatic copy disabled, “복사” (Copy) and the paste shortcut use the clipboard.
- Submitting a prompt to an online AI service sends that text to the service. This is separate from local speech recognition.
- To remove the app, quit it and delete `~/Applications/Whisper Paste.app` and the model folder. Remove its login item if you added one. Reset preferences with `defaults delete io.github.sungho-ham.whisper-paste` if desired.

See the [MIT License](LICENSE) for the app license, [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for source/model provenance and licenses, and [README.md](README.md) for the project overview.
