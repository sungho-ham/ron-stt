import AppKit
import ApplicationServices

public enum ApplicationPasteboard {
    public static func paste(_ text: String, to target: NSRunningApplication,
                      validate: ((@escaping (Bool) -> Void) -> Void)? = nil,
                      completion: @escaping (AppText?) -> Void) {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            completion("시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 ron를 허용한 뒤 다시 시도하세요. 텍스트는 미리보기에 남아 있습니다.")
            return
        }
        guard !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            completion("원래 입력 앱을 찾을 수 없습니다. ‘복사’ 후 원하는 입력창에 직접 붙여넣으세요."); return
        }
        target.activate(options: [.activateIgnoringOtherApps])
        waitForTarget(target, attempts: 10) { ready in
            guard ready else { completion("입력 앱을 활성화하지 못했습니다. ‘복사’를 사용하세요."); return }
            let send = {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                    completion("입력 대상이 바뀌어 붙여넣기를 중단했습니다. 내용을 확인한 뒤 다시 시도하세요."); return
                }
                let board = NSPasteboard.general
                let backup = (board.pasteboardItems ?? []).map { item in
                    item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                        item.data(forType: type).map { (type, $0) }
                    }
                }
                guard let source = CGEventSource(stateID: .hidSystemState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                    completion("붙여넣기 키 이벤트를 만들지 못했습니다."); return
                }
                board.clearContents(); board.setString(text, forType: .string)
                let ownChange = board.changeCount
                down.flags = .maskCommand; up.flags = .maskCommand
                down.postToPid(target.processIdentifier); up.postToPid(target.processIdentifier)
                // Leave time for the target to consume the clipboard. Never overwrite a newer copy.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if board.changeCount == ownChange {
                        board.clearContents()
                        let items = backup.map { entries -> NSPasteboardItem in
                            let item = NSPasteboardItem()
                            entries.forEach { item.setData($0.1, forType: $0.0) }
                            return item
                        }
                        if !items.isEmpty { board.writeObjects(items) }
                    }
                    completion(nil)
                }
            }
            if let validate {
                validate { valid in
                    if valid { send() }
                    else { completion("선택한 창이나 탭이 바뀌어 붙여넣기를 중단했습니다. 다시 전송하세요.") }
                }
            } else { send() }
        }
    }

    private static func waitForTarget(_ target: NSRunningApplication, attempts: Int,
                                      completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                completion(true)
            } else if attempts > 1 {
                waitForTarget(target, attempts: attempts - 1, completion: completion)
            } else { completion(false) }
        }
    }
}
