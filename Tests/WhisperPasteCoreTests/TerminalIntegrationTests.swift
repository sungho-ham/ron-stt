import AppKit
import ApplicationServices
import XCTest
@testable import WhisperPasteCore

/// Opt-in: only targets windows created by scripts/terminal-smoke-test.py.
final class TerminalIntegrationTests: XCTestCase {
    func testExplicitSessionsReceiveTextWithoutEnterAndClosedTargetFails() throws {
        guard let path = ProcessInfo.processInfo.environment["WHISPER_PASTE_TERMINAL_FIXTURE"] else {
            throw XCTSkip("Run scripts/terminal-smoke-test.py for isolated terminal input checks")
        }
        let entries = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [[String: String]]
        let bridge = TerminalBridge()
        let tracker = FocusTracker()
        tracker.start()
        defer { tracker.stop() }
        let runningApps = NSWorkspace.shared.runningApplications
        for entry in entries {
            print("Checking provider: \(entry["bundleID"]!)")
            let app = try XCTUnwrap(runningApps.first { $0.bundleIdentifier == entry["bundleID"]! },
                                   "Test app exited: \(entry["bundleID"]!)")
            var connection = try TerminalDestination(application: app)
            connection.windowID = entry["windowID"]!
            let captured = expectation(description: "capture")
            var target: TerminalDestination?
            bridge.capture(connection) { result in
                do { target = try result.get() } catch { XCTFail("capture: \(error)") }
                captured.fulfill()
            }
            wait(for: [captured], timeout: 35)
            let input = try XCTUnwrap(target)
            XCTAssertEqual(input.terminalID, entry["terminalID"])
            // Route directly to A while B is selected; the fixture begins with B selected.
            var frozen = input
            frozen.terminalID = entry["previousTerminalID"]!
            frozen.tabID = entry["previousTabID"]!
            frozen.windowID = entry["previousWindowID"] ?? frozen.windowID
            // No stored connection: the focused app/window/tab is resolved at each send.
            try activate(input, using: bridge)
            try assertTracked(input, tracker: tracker)
            let automaticallySelected = try capture(tracker, expecting: input)
            XCTAssertTrue(automaticallySelected.isSameInput(as: input))
            tracker.isPreviewFocused = { true }
            XCTAssertTrue(try capture(tracker, expecting: input).isSameInput(as: input), "Preview focus retains the external target")
            tracker.isPreviewFocused = { false }
            try activate(frozen, using: bridge)
            tracker.isPreviewFocused = { true }
            XCTAssertTrue(try capture(tracker, expecting: frozen).isSameInput(as: frozen), "Preview send refreshes a recent same-app switch")
            tracker.isPreviewFocused = { false }
            try assertTracked(frozen, tracker: tracker)
            let capturedA = try capture(tracker, expecting: frozen)
            XCTAssertTrue(capturedA.isSameInput(as: frozen), "\(entry["bundleID"]!) expected \(frozen.terminalID), got \(capturedA.terminalID)")
            // Change selection after capture. A pending final result must still go to A.
            try activate(input, using: bridge)
            try assertTracked(input, tracker: tracker)
            frozen = capturedA
            if let otherEntry = entries.first(where: { $0["bundleID"] != entry["bundleID"] }),
               let otherApp = runningApps.first(where: { $0.bundleIdentifier == otherEntry["bundleID"] }) {
                let rejected = expectation(description: "changed foreground rejected")
                bridge.capture(try TerminalDestination(application: otherApp), requireFrontmost: true) { result in
                    if case .success = result { XCTFail("Must not capture another background app as focused input") }
                    rejected.fulfill()
                }
                wait(for: [rejected], timeout: 35)
            }
            let sample = "한글 Codex \"quote\" 'literal' $(not-a-command) \\ slash"
            if frozen.kind == .terminal {
                let focused = expectation(description: "focus saved Terminal window")
                bridge.preparePaste(frozen) { result in
                    if case .failure(let error) = result { XCTFail("focus: \(error)") }
                    focused.fulfill()
                }
                wait(for: [focused], timeout: 35)
                var front = frozen; front.windowID = ""
                let confirmed = expectation(description: "selected window")
                bridge.capture(front) { result in
                    XCTAssertEqual(try? result.get().isSameInput(as: frozen), true)
                    confirmed.fulfill()
                }
                wait(for: [confirmed], timeout: 35)
                guard AXIsProcessTrusted() else {
                    print("Terminal selection verified; paste requires Accessibility for the test runner.")
                    continue
                }
                let pasted = expectation(description: "paste without Enter")
                ApplicationPasteboard.paste(sample, to: app) { error in
                    XCTAssertNil(error); pasted.fulfill()
                }
                wait(for: [pasted], timeout: 5)
            } else {
                let sent = expectation(description: "send to frozen session")
                bridge.send(sample, to: frozen) { result in
                    if case .failure(let error) = result { XCTFail("send: \(error)") }
                    sent.fulfill()
                }
                wait(for: [sent], timeout: 35)
            }
            let output = URL(fileURLWithPath: entry["previousOutput"]!)
            let deadline = Date().addingTimeInterval(3)
            var bytes = Data()
            while Date() < deadline {
                bytes = (try? Data(contentsOf: output)) ?? Data()
                if !bytes.isEmpty { break }
                Thread.sleep(forTimeInterval: 0.02)
            }
            let expected = frozen.kind == .iterm2 ? sample : "\u{1b}[200~\(sample)\u{1b}[201~"
            XCTAssertEqual(String(data: bytes, encoding: .utf8), expected)
            XCTAssertEqual((try? Data(contentsOf: URL(fileURLWithPath: entry["output"]!)))?.count ?? 0, 0)
            if frozen.kind == .ghostty {
                let multiline = expectation(description: "multiline paste into newly selected tab")
                bridge.send("다음 문장\nsecond line", to: input) { result in
                    if case .failure(let error) = result { XCTFail("multiline: \(error)") }
                    multiline.fulfill()
                }
                wait(for: [multiline], timeout: 35)
                Thread.sleep(forTimeInterval: 0.1)
                XCTAssertEqual(try String(contentsOfFile: entry["output"]!, encoding: .utf8),
                               "\u{1b}[200~다음 문장\nsecond line\u{1b}[201~")
            }
            var missing = frozen; missing.terminalID = "whisper-paste-missing-session"
            let rejected = expectation(description: "missing target")
            let reject: (Result<TerminalDestination, Error>) -> Void = { result in
                if case .success = result { XCTFail("Missing session must not redirect to active tab") }
                rejected.fulfill()
            }
            if missing.kind == .terminal { bridge.preparePaste(missing, completion: reject) }
            else { bridge.send("MUST NOT ARRIVE", to: missing, completion: reject) }
            wait(for: [rejected], timeout: 35)
        }
    }

    private func activate(_ target: TerminalDestination, using bridge: TerminalBridge) throws {
        let ready = expectation(description: "activate isolated input")
        bridge.preparePaste(target) { result in
            if case .failure(let error) = result { XCTFail("activate: \(error)") }
            ready.fulfill()
        }
        wait(for: [ready], timeout: 35)
        let deadline = Date().addingTimeInterval(3)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processID && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID else {
            throw FixtureError.focusInterrupted
        }
    }

    private enum FixtureError: Error { case focusInterrupted, targetOutsideFixture }

    private func capture(_ tracker: FocusTracker, expecting expected: TerminalDestination) throws -> TerminalDestination {
        // Stop before looking up or requesting permission for an unrelated user's app.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expected.processID else {
            throw FixtureError.focusInterrupted
        }
        let ready = expectation(description: "automatic focused target")
        var target: TerminalDestination?
        tracker.captureForSend { result in
            do { target = try result.get().destination } catch {
                let candidate = tracker.selection.application
                let front = NSWorkspace.shared.frontmostApplication
                XCTFail("automatic capture: \(error); candidate=\(candidate?.bundleID ?? "nil") pid=\(candidate?.processID ?? -1) live=\(candidate?.runningApplication != nil) front=\(front?.bundleIdentifier ?? "nil")")
            }
            ready.fulfill()
        }
        wait(for: [ready], timeout: 35)
        let captured = try XCTUnwrap(target)
        // Assertions alone do not stop XCTest. Never let a mismatched capture become
        // the destination of a later send, even if the user switches tabs mid-test.
        guard captured.isSameInput(as: expected) else { throw FixtureError.targetOutsideFixture }
        return captured
    }

    private func assertTracked(_ target: TerminalDestination, tracker: FocusTracker) throws {
        guard TerminalBridge.automationAllowed(for: target) else {
            print("Background poll permission unavailable to test runner; explicit capture remains tested.")
            return
        }
        tracker.refresh()
        let deadline = Date().addingTimeInterval(4)
        while tracker.selection.destination?.isSameInput(as: target) != true && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID else {
            throw FixtureError.focusInterrupted
        }
        XCTAssertEqual(tracker.selection.destination?.isSameInput(as: target), true)
    }
}
