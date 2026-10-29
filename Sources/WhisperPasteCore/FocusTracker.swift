import AppKit

public final class FocusTracker {
    public struct Target {
        public let destination: TerminalDestination
        public let input: ApplicationInput?
    }
    public var onChange: (() -> Void)?
    public var isPreviewFocused: () -> Bool = { false }
    public private(set) var selection = FocusSelection()
    private var noteMessage: AppText = "입력할 창을 선택하세요."
    public var note: String { noteMessage.text }
    private var lastInput: ApplicationInput?
    private let pollingBridge = TerminalBridge()
    private let sendingBridge = TerminalBridge()
    private var pollBusy = false
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    public init() {}

    public func start() {
        stop()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // Remember the event's app even if the user immediately clicks the
            // preview before a deferred poll reads the new foreground app.
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                self.observe(app)
            }
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    deinit { stop() }

    public var label: String {
        guard let app = selection.application else { return AppText("입력 대상 · 자동 추적\n입력할 창을 선택하세요.").text }
        let detail = selection.destination.map {
            [$0.displayWindowTitle, $0.displayInputTitle].filter { !$0.isEmpty }.joined(separator: " · ")
        } ?? note
        return AppText("입력 대상 · 자동 추적 · {0}\n{1}", .literal(app.appName), .literal(detail)).text
    }

    /// Called on the main thread. Activation events update the app immediately;
    /// periodic fresh captures cover same-app windows, tabs, splits and fields.
    public func refresh() {
        let ownFocus = observeForeground()
        guard !ownFocus, !pollBusy, let app = selection.application else { return }
        guard let lookup = selection.beginLookup() else { return }
        if app.kind == .application {
            do {
                let input = try ApplicationInput.capture(app)
                if selection.resolve(input.destination, for: lookup) { lastInput = input; noteMessage = "" }
            } catch {
                if selection.resolve(nil, for: lookup) { lastInput = nil; noteMessage = .describing(error) }
            }
            onChange?()
            return
        }
        guard TerminalBridge.automationAllowed(for: app) else {
            if selection.resolve(nil, for: lookup) { noteMessage = "전송 시 자동화 권한을 확인합니다." }
            onChange?(); return
        }
        pollBusy = true
        pollingBridge.capture(app, requireFrontmost: true, timeout: 2) { [weak self] result in
            guard let self else { return }
            self.pollBusy = false
            _ = self.observeForeground()
            if self.selection.resolve(try? result.get(), for: lookup) {
                self.noteMessage = (try? result.get()) == nil ? "입력 대상을 확인하지 못했습니다. 전송 시 다시 확인합니다." : ""
                self.onChange?()
            }
        }
    }

    /// A fresh lookup for this gesture, on a separate queue from display polling.
    /// Its result is handed to TerminalDelivery once and is never retargeted.
    public func captureForSend(completion: @escaping (Result<Target, Error>) -> Void) {
        let ownFocus = observeForeground()
        guard let candidate = selection.application else { completion(.failure(TerminalBridgeError.unavailable)); return }
        if candidate.kind == .application {
            do {
                let input: ApplicationInput
                if ownFocus, let previous = lastInput, previous.destination.isSameApplication(as: candidate), previous.isCurrent() {
                    input = previous
                } else { input = try ApplicationInput.capture(candidate, prompt: true) }
                if !ownFocus && NSWorkspace.shared.frontmostApplication?.processIdentifier != candidate.processID {
                    throw TerminalBridgeError.missingTarget
                }
                completion(.success(Target(destination: input.destination, input: input)))
            } catch { completion(.failure(error)) }
        } else {
            // The external app retains its front window while the preview has focus.
            // Always re-query it: a cached window may predate a very recent switch.
            sendingBridge.capture(candidate, requireFrontmost: !ownFocus) { result in
                completion(result.map { Target(destination: $0, input: nil) })
            }
        }
    }

    @discardableResult
    private func observeForeground() -> Bool {
        let foreground = NSWorkspace.shared.frontmostApplication
        let ownFocus = foreground?.processIdentifier == ProcessInfo.processInfo.processIdentifier ||
            (isPreviewFocused() && (foreground == nil || foreground?.processIdentifier == selection.application?.processID))
        if ownFocus { return true }
        observe(foreground)
        return false
    }

    private func observe(_ foreground: NSRunningApplication?) {
        let candidate = foreground.flatMap { app -> TerminalDestination? in
            guard app.activationPolicy == .regular, !app.isTerminated else { return nil }
            return try? TerminalDestination(application: app)
        }
        if selection.observe(candidate) {
            lastInput = nil; noteMessage = "현재 창·입력 영역 확인 중…"
            onChange?()
        }
    }
}
