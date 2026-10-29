import AppKit
import AVFoundation
import ApplicationServices
import WhisperPasteCore

final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // Physical W also works while a Korean input source is selected.
        if modifiers == .command && event.keyCode == 13 {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSTextViewDelegate {
    private enum Phase { case idle, authorizing, recording, finalizing, ready, pasting }
    private var phase = Phase.idle
    private var session = UUID()
    private let recorder = AudioRecorder()
    private let transcriber = ResidentTranscriber()
    private let hotKeys = HotKeys()
    private let terminalBridge = TerminalBridge()
    private var delivery = TerminalDelivery()
    private let focusTracker = FocusTracker()
    private var sendingInput: ApplicationInput?
    private var sendingDestination: TerminalDestination?
    private var lastSentText: String?
    private var sendFailure: AppText?
    private var statusMessage: AppText = ""
    private var timer: Timer?
    private var previewBusy = false
    private var preview = CumulativePreview()
    private var lastPreview: Double = 0
    private var startedAt: Date?
    private var configuration: TranscriptionConfiguration?
    private var engineLoading = false
    private var preparation = UUID()
    private let revealNotification = Notification.Name("io.github.sungho-ham.whisper-paste.show-preview")
    private var statusItem: NSStatusItem!
    private var panel: PreviewPanel!
    private let statusLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private let pasteButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let destinationLabel = NSTextField(labelWithString: "")
    private let pinButton = NSButton()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private lazy var cancelButton = NSButton(title: "", target: self, action: #selector(discard))
    private var actionGroups: NSStackView?
    private var alwaysOnTop: Bool {
        get { UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "alwaysOnTop") }
    }
    private var model: String {
        get { UserDefaults.standard.string(forKey: "model") ?? "small" }
        set { UserDefaults.standard.set(newValue, forKey: "model") }
    }
    private var language: String {
        get { UserDefaults.standard.string(forKey: "language") ?? "ko" }
        set { UserDefaults.standard.set(newValue, forKey: "language") }
    }
    private var livePreview: Bool {
        get { UserDefaults.standard.object(forKey: "livePreview") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "livePreview") }
    }
    private var useGPU: Bool {
        get { !(UserDefaults.standard.bool(forKey: "cpuOnly")) }
        set { UserDefaults.standard.set(!newValue, forKey: "cpuOnly") }
    }
    private var autoCopy: Bool {
        get { UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCopy") }
    }
    private var busy: Bool { delivery.isPending || [.authorizing, .recording, .finalizing, .pasting].contains(phase) }
    private var canSend: Bool {
        guard !delivery.isPending else { return false }
        if phase == .recording || phase == .finalizing { return true }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return phase == .ready && !text.isEmpty && text != lastSentText
    }
    private var modelsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhisperPaste/models", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent two app copies from competing for shortcuts and pasteboard restoration.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            // Spotlight can pick the repo's build copy while the installed copy is running.
            DistributedNotificationCenter.default().postNotificationName(revealNotification, object: id,
                                                                          userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whisper Paste")
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        UserDefaults.standard.removeObject(forKey: "inputConnection")
        buildPanel()
        focusTracker.isPreviewFocused = { [weak self] in self?.panel?.isKeyWindow == true }
        focusTracker.onChange = { [weak self] in self?.refreshControls() }
        focusTracker.start()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(revealFromAnotherCopy(_:)),
                                                            name: revealNotification, object: Bundle.main.bundleIdentifier)
        hotKeys.onAction = { [weak self] id in
            if id == 1 { self?.toggleRecording() } else { self?.pasteResult() }
        }
        if !hotKeys.register() {
            showError("단축키를 등록하지 못했습니다. 다른 앱의 Control+Option+Space / Return 설정을 확인하세요. 메뉴와 버튼으로도 사용할 수 있습니다.")
        } else {
            setStatus("입력창을 클릭하고 ⌃⌥Space로 녹음하세요. 마이크는 녹음할 때만 사용합니다.")
        }
        panel.orderFrontRegardless()
        refreshControls()
        prepareEngine()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        focusTracker.stop()
        timer?.invalidate(); transcriber.shutdown(); recorder.discard()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreview()
        return false
    }

    @objc private func revealFromAnotherCopy(_ notification: Notification) {
        showPreview()
    }

    private func buildPanel() {
        panel = PreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 460),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        // Clicking the preview uses normal app activation. Activating the paste
        // destination can then release keyboard focus without hiding this panel.
        // Merely showing it with orderFrontRegardless() still does not make it key.
        panel.title = "Whisper Paste"
        panel.level = alwaysOnTop ? .floating : .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.contentMinSize = NSSize(width: 360, height: 440)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.center()
        guard let content = panel.contentView else { return }
        pinButton.setButtonType(.toggle)
        pinButton.isBordered = false
        pinButton.imagePosition = .imageOnly
        pinButton.imageScaling = .scaleProportionallyDown
        pinButton.target = self; pinButton.action = #selector(toggleAlwaysOnTop)
        let header = NSStackView(views: [hint, pinButton])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 8
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        statusLabel.font = .systemFont(ofSize: 12)
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        textView.isRichText = false
        textView.delegate = self
        textView.font = .systemFont(ofSize: 17)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.frame = NSRect(x: 0, y: 0, width: 660, height: 130)
        textView.minSize = NSSize(width: 0, height: 130)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 660, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.documentView = textView
        recordButton.target = self; recordButton.action = #selector(toggleRecording)
        pasteButton.target = self; pasteButton.action = #selector(pasteResult)
        copyButton.target = self; copyButton.action = #selector(copyResult)
        destinationLabel.font = .systemFont(ofSize: 12)
        destinationLabel.textColor = .secondaryLabelColor
        destinationLabel.lineBreakMode = .byTruncatingMiddle
        destinationLabel.maximumNumberOfLines = 2
        destinationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for button in [recordButton, pasteButton, copyButton, cancelButton] {
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let primaryActions = NSStackView(views: [recordButton, pasteButton])
        let secondaryActions = NSStackView(views: [copyButton, cancelButton])
        for row in [primaryActions, secondaryActions] { row.orientation = .horizontal; row.spacing = 10 }
        let buttons = NSStackView(views: [primaryActions, secondaryActions])
        buttons.orientation = .horizontal; buttons.spacing = 10; buttons.alignment = .centerY
        actionGroups = buttons
        let stack = NSStackView(views: [header, destinationLabel, statusLabel, scroll, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint.widthAnchor.constraint(equalTo: header.widthAnchor, constant: -36),
            pinButton.widthAnchor.constraint(equalToConstant: 28),
            pinButton.heightAnchor.constraint(equalToConstant: 28),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 130),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            destinationLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        applyInterfaceLanguage()
        updateActionLayout()
    }

    func windowDidResize(_ notification: Notification) { updateActionLayout() }

    private func updateActionLayout() {
        guard let actionGroups, let content = panel?.contentView else { return }
        let compact = content.bounds.width < 540
        actionGroups.orientation = compact ? .vertical : .horizontal
        actionGroups.alignment = compact ? .leading : .centerY
        actionGroups.spacing = compact ? 8 : 10
    }

    @objc private func toggleAlwaysOnTop() {
        alwaysOnTop.toggle()
        applyAlwaysOnTop()
    }

    private func applyAlwaysOnTop() {
        panel?.level = alwaysOnTop ? .floating : .normal
        pinButton.state = alwaysOnTop ? .on : .off
        pinButton.image = NSImage(systemSymbolName: alwaysOnTop ? "pin.fill" : "pin",
                                 accessibilityDescription: AppText("항상 위에 표시").text)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        // A quiet accent on the symbol only, without a solid selected background.
        pinButton.contentTintColor = alwaysOnTop ? NSColor.controlAccentColor.withAlphaComponent(0.55) : .secondaryLabelColor
        pinButton.toolTip = (alwaysOnTop ? AppText("항상 위에 표시 끄기") : AppText("항상 위에 표시 켜기")).text
    }

    private func applyInterfaceLanguage() {
        hint.stringValue = AppText("⌃⌥Space  시작 / 종료    ·    ⌃⌥Return  보내기").text
        copyButton.title = AppText("복사").text
        cancelButton.title = AppText("취소 / 비우기").text
        pinButton.setAccessibilityLabel(AppText("항상 위에 표시").text)
        applyAlwaysOnTop()
        refreshControls()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, phase == .recording ? "종료  ⌃⌥Space" : "시작  ⌃⌥Space",
            #selector(toggleRecording), enabled: !busy || phase == .recording)
        add(menu, "미리보기 열기", #selector(showPreview))
        add(menu, "항상 위에 표시", #selector(toggleAlwaysOnTop)).state = alwaysOnTop ? .on : .off
        add(menu, "보내기  ⌃⌥Return", #selector(pasteResult), enabled: canSend)
        menu.addItem(.separator())
        let modelMenu = NSMenu()
        for value in ["small", "medium"] {
            let installed = FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent("ggml-\(value).bin").path)
            let title = installed ? AppText.literal(value.capitalized) : AppText("{0} — 다운로드 필요", .literal(value.capitalized))
            let item = add(modelMenu, title,
                #selector(selectModel(_:)), enabled: !busy && installed)
            item.representedObject = value; item.state = model == value ? .on : .off
        }
        let modelItem = NSMenuItem(title: AppText("모델: {0}", .literal(model.capitalized)).text, action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu; menu.addItem(modelItem)
        let languageMenu = NSMenu()
        for (value, title) in [("ko", "한국어"), ("ja", "日本語"), ("en", "English"), ("auto", "자동 감지")] {
            let item = add(languageMenu, value == "auto" ? AppText("자동 감지") : .literal(title), #selector(selectLanguage(_:)), enabled: !busy)
            item.representedObject = value; item.state = language == value ? .on : .off
        }
        let languageItem = NSMenuItem(title: AppText("인식 언어: {0}", .literal(language)).text, action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu; menu.addItem(languageItem)
        let interfaceMenu = NSMenu()
        for value in InterfaceLanguage.allCases {
            let item = add(interfaceMenu, .literal(value.name), #selector(selectInterfaceLanguage(_:)))
            item.representedObject = value.rawValue
            item.state = InterfaceLanguage.saved() == value ? .on : .off
        }
        let interfaceItem = NSMenuItem(title: AppText("화면 언어: {0}", .literal(InterfaceLanguage.saved().name)).text,
                                      action: nil, keyEquivalent: "")
        interfaceItem.submenu = interfaceMenu; menu.addItem(interfaceItem)
        add(menu, "녹음 중 미리보기 (전체 누적)", #selector(togglePreview), enabled: !busy).state = livePreview ? .on : .off
        add(menu, "인식 완료 후 자동 복사", #selector(toggleAutoCopy), enabled: !busy).state = autoCopy ? .on : .off
        add(menu, "Metal GPU 사용", #selector(toggleGPU), enabled: !busy).state = useGPU ? .on : .off
        menu.addItem(.separator())
        add(menu, "마이크 권한 설정…", #selector(openMicrophoneSettings))
        add(menu, "손쉬운 사용 권한 설정…", #selector(openAccessibilitySettings))
        add(menu, "자동화 권한 설정…", #selector(openAutomationSettings))
        add(menu, "모델 폴더 열기", #selector(openModels))
        add(menu, "사용 튜토리얼", #selector(openTutorial))
        menu.addItem(.separator())
        add(menu, "Whisper Paste 종료", #selector(quit))
    }

    @discardableResult private func add(_ menu: NSMenu, _ title: AppText, _ action: Selector,
                                        enabled: Bool = true) -> NSMenuItem {
        menu.autoenablesItems = false
        let item = NSMenuItem(title: title.text, action: action, keyEquivalent: "")
        item.target = self; item.isEnabled = enabled; menu.addItem(item); return item
    }

    @objc private func toggleRecording() {
        if phase == .recording { finishRecording(); return }
        guard !busy else { NSSound.beep(); return }
        let previousText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if phase == .ready && !previousText.isEmpty && previousText != lastSentText {
            let alert = NSAlert()
            alert.messageText = AppText("이전 인식 결과를 지우고 새로 녹음할까요?").text
            alert.addButton(withTitle: AppText("새 녹음").text); alert.addButton(withTitle: AppText("돌아가기").text)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let executable = Bundle.main.resourceURL!.appendingPathComponent("bin/whisper-worker")
        let modelURL = modelsDirectory.appendingPathComponent("ggml-\(model).bin")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.fileExists(atPath: modelURL.path) else {
            showError(AppText("엔진 또는 {0} 모델이 없습니다. 튜토리얼의 setup.sh와 build-app.sh를 실행하세요.", .literal(model))); return
        }
        lastSentText = nil; sendFailure = nil
        configuration = TranscriptionConfiguration(executable: executable, model: modelURL,
                                                   language: language, useGPU: useGPU)
        prepareEngine()
        session = UUID(); let token = session
        phase = .authorizing; refreshControls()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.session == token else { return }
                    if allowed { self.beginRecording() }
                    else { self.phase = .idle; self.showError("마이크 권한이 필요합니다. 메뉴의 ‘마이크 권한 설정’을 확인하세요.") }
                }
            }
        default:
            phase = .idle; showError("마이크 권한이 꺼져 있습니다. 시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 허용하세요.")
        }
    }

    private func beginRecording() {
        do {
            try recorder.start()
            preview.reset()
            phase = .recording; textView.string = ""; previewBusy = false; lastPreview = 0; startedAt = Date()
            panel.orderFrontRegardless(); refreshControls()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
            tick()
        } catch { phase = .idle; showError(.describing(error)) }
    }

    private func tick() {
        guard phase == .recording else { return }
        let seconds = recorder.duration
        if let error = recorder.error { discard(); showError(AppText("마이크 처리 오류: {0}", .literal(error))); return }
        if seconds >= Double(AudioRecorder.maximumSeconds) || (startedAt?.timeIntervalSinceNow ?? 0) < -305 {
            finishRecording(); return
        }
        let recent = recorder.snapshot(lastSeconds: 1)
        let level = AudioData.rms(recent)
        setStatus(AppText("● 녹음 중 {0}초 / 최대 5분 · {1} · {2}\n{3}",
                          .literal(String(Int(seconds))), .literal(model.capitalized),
                          engineLoading ? "모델 준비 중" : (level > 0.003 ? "입력 감지" : "조용함"),
                          livePreview ? "앞부분을 유지하며 누적 중입니다. 종료하면 전체 내용을 다시 인식합니다." : "종료하면 전체 내용을 인식합니다."))
        guard livePreview, !previewBusy, seconds >= 1.5, seconds - lastPreview >= 1,
              let configuration else { return }
        let recorded = recorder.snapshot()
        guard let request = preview.nextRequest(in: recorded) else { return }
        lastPreview = seconds
        guard request.hasSignal else {
            preview.complete(request, text: "")
            updatePreviewText(preview.text)
            return
        }
        let samples = Array(recorded[request.range])
        previewBusy = true
        let token = session
        transcriber.transcribe(samples: samples, configuration: configuration) { [weak self] result in
            guard let self, self.session == token, self.phase == .recording else { return }
            self.previewBusy = false
            switch result {
            case .success(let text):
                if self.preview.complete(request, text: text) { self.updatePreviewText(self.preview.text) }
            case .failure:
                self.preview.fail(request)
            }
            // A preview failure must not interrupt recording. Final errors are shown in full.
        }
    }

    private func updatePreviewText(_ text: String) {
        guard text != textView.string else { return }
        let scroll = textView.enclosingScrollView
        let origin = scroll?.contentView.bounds.origin ?? .zero
        let visible = textView.visibleRect
        let selection = textView.selectedRange()
        let follow = visible.maxY >= textView.bounds.maxY - 24 && selection.length == 0
        textView.string = text
        let length = (text as NSString).length
        let location = min(selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        if let container = textView.textContainer { textView.layoutManager?.ensureLayout(for: container) }
        if follow { textView.scrollRangeToVisible(NSRange(location: length, length: 0)) }
        else if let scroll {
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func finishRecording() {
        timer?.invalidate(); timer = nil
        let clipboardAtStop = NSPasteboard.general.changeCount
        let samples = recorder.stop(); recorder.discard()
        session = UUID(); let token = session
        transcriber.cancel(); previewBusy = false; preview.reset()
        guard AudioData.hasSignal(samples), let configuration else {
            delivery.cancel()
            phase = .idle; textView.string = ""; showError("인식할 음성이 없습니다. 마이크 입력 장치·볼륨을 확인하고 1초 이상 말해주세요."); return
        }
        phase = .finalizing; refreshControls()
        setStatus(AppText("전체 녹음 최종 인식 중… {0}초 · {1}", .literal(String(Int(Double(samples.count) / 16_000))), .literal(model.capitalized)))
        transcriber.transcribe(samples: samples, configuration: configuration) { [weak self] result in
            guard let self, self.session == token, self.phase == .finalizing else { return }
            switch result {
            case .success(let text):
                self.textView.string = text
                self.phase = text.isEmpty ? .idle : .ready
                if text.isEmpty { self.delivery.cancel() }
                var copyNotice: AppText?
                if self.autoCopy && !text.isEmpty {
                    let copied = ClipboardWriter.copyIfUnchanged(text, since: clipboardAtStop)
                    copyNotice = copied ? "자동 복사 완료 · ⌘V로 붙여넣을 수 있습니다." : "새 클립보드 내용을 보존했습니다. 필요하면 ‘복사’를 누르세요."
                }
                let completed: AppText = "인식 완료 · 수정 후에는 ‘복사’ 또는 ⌃⌥Return. 실행은 직접 합니다."
                let notice = self.sendFailure ?? copyNotice
                self.setStatus(text.isEmpty ? "음성을 인식하지 못했습니다. 다시 녹음해주세요." :
                    notice.map { AppText("{0}\n{1}", $0, completed) } ?? completed)
                if let ticket = self.delivery.id {
                    self.delivery.provide(text, for: ticket)
                    self.deliverWhenReady()
                }
                self.refreshControls()
            case .failure(let error):
                self.delivery.cancel(); self.phase = .idle; self.showError(.describing(error))
            }
        }
    }

    @objc private func pasteResult() { requestFocusedSend() }

    @objc private func copyResult() {
        guard phase == .ready else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(textView.string, forType: .string)
        setStatus("클립보드에 복사했습니다. 원하는 입력창에 ⌘V로 붙여넣으세요.")
    }

    @objc private func discard() {
        guard phase != .pasting else { return }
        delivery.cancel(); sendingInput = nil; sendingDestination = nil; lastSentText = nil; sendFailure = nil
        session = UUID(); timer?.invalidate(); timer = nil
        transcriber.cancel(); recorder.discard(); phase = .idle; previewBusy = false; preview.reset()
        textView.string = ""; configuration = nil
        setStatus("입력창을 클릭하고 ⌃⌥Space로 새 녹음을 시작하세요."); refreshControls()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        discard(); panel.orderOut(nil); return false
    }
    @objc private func showPreview() { panel?.orderFrontRegardless() }
    @objc private func selectModel(_ sender: NSMenuItem) { if !busy, let value = sender.representedObject as? String { model = value; prepareEngine() } }
    @objc private func selectLanguage(_ sender: NSMenuItem) { if !busy, let value = sender.representedObject as? String { language = value; prepareEngine() } }
    @objc private func selectInterfaceLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let language = InterfaceLanguage(rawValue: value) else { return }
        language.save()
        applyInterfaceLanguage()
        if let menu = statusItem.menu { menuNeedsUpdate(menu) }
    }
    @objc private func togglePreview() { if !busy { livePreview.toggle() } }
    @objc private func toggleGPU() { if !busy { useGPU.toggle(); prepareEngine() } }
    @objc private func toggleAutoCopy() { if !busy { autoCopy.toggle() } }
    @objc private func openMicrophoneSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
    @objc private func openAccessibilitySettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    @objc private func openAutomationSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
    @objc private func openModels() { try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true); NSWorkspace.shared.open(modelsDirectory) }
    @objc private func openTutorial() { if let url = Bundle.main.url(forResource: InterfaceLanguage.saved().tutorialResource, withExtension: "md") { NSWorkspace.shared.open(url) } }
    @objc private func quit() { NSApp.terminate(nil) }

    private func prepareEngine() {
        let executable = Bundle.main.resourceURL!.appendingPathComponent("bin/whisper-worker")
        let modelURL = modelsDirectory.appendingPathComponent("ggml-\(model).bin")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.fileExists(atPath: modelURL.path) else { return }
        let config = TranscriptionConfiguration(executable: executable, model: modelURL, language: language, useGPU: useGPU)
        preparation = UUID(); let token = preparation; engineLoading = true
        transcriber.prepare(configuration: config) { [weak self] _ in
            guard let self, self.preparation == token else { return }
            self.engineLoading = false
        }
    }

    private func setStatus(_ message: AppText) {
        statusMessage = message
        refreshStatus()
    }

    private func refreshStatus() {
        let message = statusMessage.text
        statusLabel.stringValue = message
        statusItem.button?.toolTip = "Whisper Paste · \(message.components(separatedBy: "\n").first ?? "")"
    }

    private func showError(_ message: AppText) {
        setStatus(message); refreshControls(); panel.orderFrontRegardless()
    }

    private func refreshControls() {
        refreshStatus()
        recordButton.title = (phase == .recording ? AppText("종료") : AppText("시작")).text
        recordButton.isEnabled = !busy || phase == .recording
        pasteButton.title = (phase == .recording ? AppText("종료 후 보내기") : AppText("보내기")).text
        pasteButton.isEnabled = canSend
        copyButton.isEnabled = phase == .ready
        textView.isEditable = phase == .ready && !delivery.isPending
        if delivery.isPending, let destination = sendingDestination {
            destinationLabel.stringValue = AppText("전송 대상 확정 · {0}\n{1} · {2}", .literal(destination.appName), .literal(destination.displayWindowTitle), .literal(destination.displayInputTitle)).text
        } else if delivery.isPending {
            destinationLabel.stringValue = AppText("전송할 입력 대상을 확인하고 있습니다…").text
        } else { destinationLabel.stringValue = focusTracker.label }
        let symbol = phase == .recording ? "record.circle" : (phase == .finalizing ? "ellipsis.circle" : "waveform")
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Whisper Paste")
        statusItem.button?.contentTintColor = phase == .recording ? .systemRed : nil
    }

    func textDidChange(_ notification: Notification) { refreshControls() }

    private func requestFocusedSend() {
        guard canSend else { NSSound.beep(); return }
        let text = phase == .ready ? textView.string.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        guard let ticket = delivery.begin(text: text) else { return }
        sendFailure = nil; sendingInput = nil; sendingDestination = nil
        setStatus("현재 입력 대상을 확인합니다. 최종 인식 중이면 완료 후 보냅니다.")
        focusTracker.captureForSend { [weak self] result in
            guard let self, self.delivery.id == ticket else { return }
            switch result {
            case .success(let target):
                self.sendingInput = target.input
                self.sendingDestination = target.destination
                self.delivery.resolve(target.destination, for: ticket)
                self.deliverWhenReady(); self.refreshControls()
            case .failure(let error):
                self.delivery.cancel(); self.sendingInput = nil; self.sendingDestination = nil
                self.sendFailure = .describing(error)
                self.showError(.describing(error))
            }
        }
        if phase == .recording { finishRecording() }
        refreshControls()
    }

    private func deliverWhenReady() {
        guard let item = delivery.take() else { return }
        do { try TerminalBridge.validate(item.text) }
        catch { delivery.cancel(); showError(.describing(error)); return }
        phase = .pasting; refreshControls()
        setStatus(AppText("{0} · {1}에 입력 중…", .literal(item.destination.appName),
                          item.destination.kind == .application ? "현재 입력칸" : .literal(item.destination.terminalTitle)))
        let complete: (Error?) -> Void = { [weak self] error in
            guard let self, self.delivery.id == item.id else { return }
            self.delivery.cancel(); self.sendingInput = nil; self.sendingDestination = nil; self.phase = .ready
            if let error { self.showError(.describing(error)) }
            else {
                self.lastSentText = item.text
                let message = item.destination.needsClipboard(for: item.text)
                    ? AppText("{0}에 붙여넣기 키를 보냈습니다. 입력창을 확인하세요.\n같은 결과의 중복 전송을 막았습니다. 새 녹음으로 이어가세요.", .literal(item.destination.appName))
                    : AppText("{0}에 텍스트를 보냈습니다. 실행은 대상에서 직접 Enter를 누르세요.\n같은 결과의 중복 전송을 막았습니다. 새 녹음으로 이어가세요.", .literal(item.destination.appName))
                self.setStatus(message)
                self.refreshControls()
            }
        }
        if item.destination.needsClipboard(for: item.text) {
            if item.destination.kind == .application {
                guard let input = sendingInput, let app = item.destination.runningApplication else {
                    complete(TerminalBridgeError.missingTarget); return
                }
                ApplicationPasteboard.paste(item.text, to: app, validate: { done in
                    do { try input.prepare(); done(input.isCurrent()) }
                    catch { done(false) }
                }) { error in
                    complete(error)
                }
            } else {
                terminalBridge.preparePaste(item.destination) { [weak self] result in
                    guard let self, self.delivery.id == item.id else { return }
                    if case .failure(let error) = result { complete(error); return }
                    guard let app = item.destination.runningApplication else { complete(TerminalBridgeError.unavailable); return }
                    ApplicationPasteboard.paste(item.text, to: app, validate: { done in
                        var front = item.destination; front.windowID = ""
                        self.terminalBridge.capture(front, requireFrontmost: true) { result in
                            done((try? result.get().isSameInput(as: item.destination)) == true)
                        }
                    }) { error in
                        complete(error)
                    }
                }
            }
        } else {
            terminalBridge.send(item.text, to: item.destination) { result in
                if case .failure(let error) = result { complete(error) } else { complete(nil) }
            }
        }
    }

}
