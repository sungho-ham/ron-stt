import AppKit
import ApplicationServices

/// An ephemeral AX identity, not the contents of the field. Generic apps have no
/// universal tab API; if this exact input cannot be restored, the paste is refused.
public final class ApplicationInput {
    public let destination: TerminalDestination
    private let application: AXUIElement
    private let window: AXUIElement
    private let element: AXUIElement

    private init(destination: TerminalDestination, application: AXUIElement, window: AXUIElement, element: AXUIElement) {
        self.destination = destination; self.application = application; self.window = window; self.element = element
    }

    public static func capture(_ target: TerminalDestination, prompt: Bool = false) throws -> ApplicationInput {
        guard AXIsProcessTrusted() else {
            if prompt {
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            }
            throw InputError.accessibility
        }
        guard target.runningApplication != nil else { throw TerminalBridgeError.unavailable }
        let app = AXUIElementCreateApplication(target.processID)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let windowValue = attribute(app, kAXFocusedWindowAttribute),
              let elementValue = attribute(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(windowValue) == AXUIElementGetTypeID(),
              CFGetTypeID(elementValue) == AXUIElementGetTypeID() else {
            throw InputError.noInput
        }
        let window = windowValue as! AXUIElement, element = elementValue as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.25)
        AXUIElementSetMessagingTimeout(element, 0.25)
        var destination = target
        destination.windowID = String(CFHash(window))
        destination.terminalID = String(CFHash(element))
        destination.windowTitle = String(((attribute(window, kAXTitleAttribute) as? String) ?? "").prefix(160))
        destination.terminalTitle = ""
        return ApplicationInput(destination: destination, application: app, window: window, element: element)
    }

    public func prepare() throws {
        guard destination.runningApplication != nil else { throw TerminalBridgeError.unavailable }
        guard AXIsProcessTrusted() else { throw InputError.accessibility }
        // Some apps cannot set these attributes; validation below remains mandatory.
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    public func isCurrent() -> Bool {
        guard destination.runningApplication != nil, AXIsProcessTrusted(),
              let currentWindow = Self.attribute(application, kAXFocusedWindowAttribute),
              let currentElement = Self.attribute(application, kAXFocusedUIElementAttribute) else { return false }
        return CFEqual(window, currentWindow) && CFEqual(element, currentElement)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    public enum InputError: AppLocalizedError {
        case accessibility, noInput
        public var message: AppText {
            switch self {
            case .accessibility: return "손쉬운 사용 권한이 필요합니다. 시스템 설정에서 ron를 허용한 뒤 입력할 곳을 클릭하고 다시 전송하세요."
            case .noInput: return "현재 입력칸을 확인할 수 없습니다. 입력할 곳을 클릭한 뒤 다시 전송하거나 ‘복사’를 사용하세요."
            }
        }
    }
}
