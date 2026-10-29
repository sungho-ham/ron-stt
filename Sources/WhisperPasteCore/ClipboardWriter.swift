import AppKit

public enum ClipboardWriter {
    /// Called on the main thread when final recognition completes. Never erase a newer user copy.
    public static func copyIfUnchanged(_ text: String, since changeCount: Int,
                                        to pasteboard: NSPasteboard = .general) -> Bool {
        guard !text.isEmpty, pasteboard.changeCount == changeCount else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
