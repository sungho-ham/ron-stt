import AppKit

public enum TerminalKind: String, Codable, CaseIterable {
    case ghostty, iterm2, terminal, application

    public static func detect(bundleID: String) -> TerminalKind {
        switch bundleID {
        case "com.mitchellh.ghostty": return .ghostty
        case "com.googlecode.iterm2": return .iterm2
        case "com.apple.Terminal": return .terminal
        default: return .application
        }
    }
}

/// Process lifetime + window + session, never a tab index that can be reordered.
public struct TerminalDestination: Codable, Equatable {
    public var kind: TerminalKind
    public var bundleID: String
    public var appName: String
    public var processID: Int32
    public var launchedAt: Double
    public var windowID: String = ""
    public var windowTitle: String = ""
    public var tabID: String = ""
    public var terminalID: String = ""
    public var terminalTitle: String = ""

    public init(application: NSRunningApplication) throws {
        guard let bundleID = application.bundleIdentifier, let date = application.launchDate else {
            throw TerminalBridgeError.unavailable
        }
        self.kind = TerminalKind.detect(bundleID: bundleID)
        self.bundleID = bundleID
        appName = application.localizedName ?? bundleID
        processID = application.processIdentifier
        launchedAt = date.timeIntervalSince1970
    }

    public var runningApplication: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier == processID && !$0.isTerminated && $0.bundleIdentifier == bundleID &&
                $0.launchDate?.timeIntervalSince1970 == launchedAt
        }
    }

    public var displayWindowTitle: String {
        windowTitle.isEmpty ? AppText("현재 창").text : windowTitle
    }

    public var displayInputTitle: String {
        kind == .application ? AppText("현재 입력칸").text : terminalTitle
    }

    public func needsClipboard(for text: String) -> Bool {
        kind == .application || kind == .terminal ||
            (kind == .iterm2 && text.contains(where: { $0.isNewline || $0 == "\t" }))
    }

    public func isSameInput(as other: Self) -> Bool {
        isSameApplication(as: other) &&
            windowID == other.windowID && terminalID == other.terminalID
    }

    public func isSameApplication(as other: Self) -> Bool {
        bundleID == other.bundleID && processID == other.processID && launchedAt == other.launchedAt
    }
}

public enum TerminalBridgeError: AppLocalizedError {
    case unavailable, permission, missingTarget, failed, timedOut, invalidText
    public var message: AppText {
        switch self {
        case .unavailable: return "입력 앱을 찾을 수 없습니다. 입력할 창을 선택한 뒤 다시 전송하세요."
        case .permission: return "시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 Whisper Paste의 대상 앱 제어를 허용하세요."
        case .missingTarget: return "입력할 창이나 탭이 바뀌었거나 없어졌습니다. 내용을 보존했습니다. 원하는 입력창을 선택한 뒤 다시 전송하세요."
        case .failed: return "터미널 연동에 실패했습니다. 자동화 권한과 터미널 버전을 확인하세요. 재전송 전 대상 입력창을 확인하세요."
        case .timedOut: return "터미널 응답 시간이 초과되었습니다. 이미 입력되었을 수 있으므로 대상 입력창을 확인한 뒤 다시 시도하세요."
        case .invalidText: return "전송할 내용이 비어 있거나 지원하지 않는 제어 문자 또는 너무 긴 텍스트가 포함되어 있습니다."
        }
    }
}

/// One explicit send gesture joins target lookup and final transcription in either order.
/// Once taken, a delivery cannot be issued again. Cancellation fences late callbacks.
public struct TerminalDelivery {
    public struct Item {
        public let id: UUID
        public let destination: TerminalDestination
        public let text: String
    }
    public private(set) var id: UUID?
    private var destination: TerminalDestination?
    private var text: String?
    private var taken = false

    public init() {}
    public var isPending: Bool { id != nil }
    public mutating func begin(text: String?) -> UUID? {
        guard id == nil else { return nil }
        let ticket = UUID()
        id = ticket; destination = nil; self.text = text; taken = false
        return ticket
    }
    public mutating func resolve(_ destination: TerminalDestination, for ticket: UUID) {
        guard id == ticket, self.destination == nil, !taken else { return }
        self.destination = destination
    }
    public mutating func provide(_ text: String, for ticket: UUID) {
        guard id == ticket, !taken else { return }
        self.text = text
    }
    public mutating func take() -> Item? {
        guard let id, let destination, let text, !text.isEmpty, !taken else { return nil }
        taken = true
        return Item(id: id, destination: destination, text: text)
    }
    public mutating func cancel() { self = Self() }
}
