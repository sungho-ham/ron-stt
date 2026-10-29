import XCTest
@testable import WhisperPasteCore

final class TerminalTests: XCTestCase {
    func testDetectsSupportedTerminalsAndRoutesOtherAppsToPaste() throws {
        XCTAssertEqual(TerminalKind.detect(bundleID: "com.mitchellh.ghostty"), .ghostty)
        XCTAssertEqual(TerminalKind.detect(bundleID: "com.googlecode.iterm2"), .iterm2)
        XCTAssertEqual(TerminalKind.detect(bundleID: "com.apple.Terminal"), .terminal)
        XCTAssertEqual(TerminalKind.detect(bundleID: "com.example.Editor"), .application)
        var target = try destination()
        XCTAssertFalse(target.needsClipboard(for: "첫째\n둘째"))
        target.kind = .iterm2
        XCTAssertFalse(target.needsClipboard(for: "한글 Codex"))
        XCTAssertTrue(target.needsClipboard(for: "첫째\n둘째"))
        XCTAssertTrue(target.needsClipboard(for: "첫째\r둘째"))
        XCTAssertTrue(target.needsClipboard(for: "첫째\t둘째"))
        target.kind = .terminal
        XCTAssertTrue(target.needsClipboard(for: "한글 Codex"))
    }

    func testLateTargetAndFinalResultJoinExactlyOnce() throws {
        var delivery = TerminalDelivery()
        let ticket = try XCTUnwrap(delivery.begin(text: nil))
        XCTAssertNil(delivery.begin(text: "duplicate hotkey"))
        delivery.provide("최종 결과", for: ticket)
        XCTAssertNil(delivery.take())
        let original = try destination()
        delivery.resolve(original, for: ticket)
        // A later lookup must not redirect an already captured target.
        var other = original; other.terminalID = "tab-b-split"
        delivery.resolve(other, for: ticket)
        let item = try XCTUnwrap(delivery.take())
        XCTAssertEqual(item.destination, original)
        XCTAssertEqual(item.text, "최종 결과")
        XCTAssertNil(delivery.take())
    }

    func testTargetCanArriveBeforeFinalText() throws {
        var delivery = TerminalDelivery()
        let ticket = try XCTUnwrap(delivery.begin(text: nil))
        delivery.resolve(try destination(), for: ticket)
        XCTAssertNil(delivery.take())
        delivery.provide("final", for: ticket)
        XCTAssertEqual(delivery.take()?.text, "final")
    }

    func testCancelFencesBothCallbacksFromPreviousRecording() throws {
        var delivery = TerminalDelivery()
        let old = try XCTUnwrap(delivery.begin(text: nil))
        delivery.cancel()
        let fresh = try XCTUnwrap(delivery.begin(text: "new"))
        delivery.resolve(try destination(), for: old)
        delivery.provide("stale", for: old)
        XCTAssertNil(delivery.take())
        delivery.resolve(try destination(), for: fresh)
        XCTAssertEqual(delivery.take()?.text, "new")
    }

    func testSessionIdentityRejectsChangedWindowSplitAndProcessLifetime() throws {
        let first = try destination()
        var other = first; other.terminalID = "different-split"
        XCTAssertFalse(first.isSameInput(as: other))
        other = first; other.windowID = "different-window"
        XCTAssertFalse(first.isSameInput(as: other))
        other = first; other.launchedAt += 1
        XCTAssertFalse(first.isSameInput(as: other))
        other = first; other.windowTitle = "renamed"
        XCTAssertTrue(first.isSameInput(as: other))
    }

    func testTextValidationAllowsQuotesAndUnicodeButRejectsTerminalControls() throws {
        XCTAssertNoThrow(try TerminalBridge.validate("한글 \"quotes\" 'test' $(literal) \\n\n둘째\t열"))
        for text in ["", " \n ", "\u{1b}[A", "\u{0}", "\u{7f}", String(repeating: "a", count: 262_145)] {
            XCTAssertThrowsError(try TerminalBridge.validate(text))
        }
    }

    private func destination() throws -> TerminalDestination {
        try JSONDecoder().decode(TerminalDestination.self, from: Data(#"""
        {"kind":"ghostty","bundleID":"com.mitchellh.ghostty","appName":"Ghostty","processID":12,
         "launchedAt":1,"windowID":"window-a","windowTitle":"work","tabID":"tab-a",
         "terminalID":"split-a","terminalTitle":"Codex"}
        """#.utf8))
    }
}
