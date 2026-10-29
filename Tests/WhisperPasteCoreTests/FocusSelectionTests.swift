import XCTest
@testable import WhisperPasteCore

final class FocusSelectionTests: XCTestCase {
    func testSwitchingAppsImmediatelyClearsOldDestinationAndRejectsItsLateLookup() throws {
        var selection = FocusSelection()
        let first = try target()
        selection.observe(first)
        let old = try XCTUnwrap(selection.beginLookup())
        var other = first; other.bundleID = "com.example.editor"; other.processID = 43
        XCTAssertTrue(selection.observe(other))
        XCTAssertEqual(selection.application, other)
        XCTAssertNil(selection.destination)
        XCTAssertFalse(selection.resolve(first, for: old))
        let fresh = try XCTUnwrap(selection.beginLookup())
        XCTAssertTrue(selection.resolve(other, for: fresh))
        XCTAssertEqual(selection.destination, other)
    }

    func testOwnPreviewKeepsLastExternalInputButUnsupportedForegroundClearsIt() throws {
        var selection = FocusSelection()
        let first = try target()
        selection.observe(first)
        let lookup = try XCTUnwrap(selection.beginLookup())
        selection.resolve(first, for: lookup)
        XCTAssertFalse(selection.observe(nil, isOwnApplication: true))
        XCTAssertEqual(selection.destination, first)
        XCTAssertTrue(selection.observe(nil))
        XCTAssertNil(selection.application)
        XCTAssertNil(selection.destination)
        XCTAssertNil(selection.beginLookup())
    }

    func testSameAppTracksNewWindowsTabsAndSplitsWhileDeliveryStaysFrozen() throws {
        var selection = FocusSelection(), delivery = TerminalDelivery()
        let first = try target()
        selection.observe(first)
        let lookup = try XCTUnwrap(selection.beginLookup())
        selection.resolve(first, for: lookup)
        let ticket = try XCTUnwrap(delivery.begin(text: nil))
        delivery.resolve(try XCTUnwrap(selection.destination), for: ticket)
        for field in ["tab", "split", "window"] {
            var next = first
            if field == "window" { next.windowID = "second-window" }
            next.tabID = "tab-\(field)"; next.terminalID = "input-\(field)"
            XCTAssertFalse(selection.observe(next))
            let request = try XCTUnwrap(selection.beginLookup())
            XCTAssertTrue(selection.resolve(next, for: request))
            XCTAssertEqual(selection.destination, next)
            delivery.resolve(next, for: ticket)
        }
        delivery.provide("최종 결과", for: ticket)
        let sent = try XCTUnwrap(delivery.take())
        XCTAssertEqual(sent.destination, first)
        XCTAssertEqual(sent.text, "최종 결과")
        XCTAssertNil(delivery.take())
    }

    func testOlderPollAndWrongProcessCannotReplaceLatestTarget() throws {
        var selection = FocusSelection()
        let first = try target()
        selection.observe(first)
        let old = try XCTUnwrap(selection.beginLookup())
        let latest = try XCTUnwrap(selection.beginLookup())
        var newer = first; newer.terminalID = "new-split"
        XCTAssertFalse(selection.resolve(first, for: old))
        var wrongProcess = newer; wrongProcess.launchedAt += 1
        XCTAssertFalse(selection.resolve(wrongProcess, for: latest))
        XCTAssertTrue(selection.resolve(newer, for: latest))
        XCTAssertEqual(selection.destination, newer)
        XCTAssertFalse(selection.resolve(first, for: latest))
        let pending = try XCTUnwrap(selection.beginLookup())
        XCTAssertTrue(selection.observe(wrongProcess))
        XCTAssertFalse(selection.resolve(first, for: pending))
        XCTAssertNil(selection.destination)
    }

    func testCaptureFailureDoesNotFallBackToPreviousTab() throws {
        var selection = FocusSelection()
        let first = try target()
        selection.observe(first)
        let resolved = try XCTUnwrap(selection.beginLookup())
        selection.resolve(first, for: resolved)
        let failed = try XCTUnwrap(selection.beginLookup())
        XCTAssertTrue(selection.resolve(nil, for: failed))
        XCTAssertNil(selection.destination)
        XCTAssertEqual(selection.application, first)
    }

    private func target() throws -> TerminalDestination {
        try JSONDecoder().decode(TerminalDestination.self, from: Data(#"""
        {"kind":"ghostty","bundleID":"com.mitchellh.ghostty","appName":"Ghostty","processID":42,
         "launchedAt":1,"windowID":"window-a","windowTitle":"work","tabID":"tab-a",
         "terminalID":"split-a","terminalTitle":"Codex"}
        """#.utf8))
    }
}
