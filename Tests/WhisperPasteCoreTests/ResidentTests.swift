import XCTest
import AppKit
@testable import WhisperPasteCore

final class ResidentTests: XCTestCase {
    func testModelIsReusedAndConfigurationChangeReloads() throws {
        let helper = try ResidentHelper()
        defer { helper.remove() }
        let engine = ResidentTranscriber(); defer { engine.shutdown() }
        for _ in 0..<2 {
            let done = expectation(description: "reuse")
            engine.transcribe(samples: [0.1], configuration: helper.configuration()) { result in
                XCTAssertEqual(try? result.get(), "test result"); done.fulfill()
            }
            wait(for: [done], timeout: 4)
        }
        XCTAssertEqual(helper.starts, 1)
        let changed = expectation(description: "different configuration")
        engine.transcribe(samples: [0.1], configuration: helper.configuration(language: "ja")) { result in
            XCTAssertEqual(try? result.get(), "test result"); changed.fulfill()
        }
        wait(for: [changed], timeout: 4)
        XCTAssertEqual(helper.starts, 2)
        let path = try String(contentsOfFile: helper.url.path + ".audio", encoding: .utf8).trimmingCharacters(in: .newlines)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testCancellationKeepsModelAndNextResultIsFresh() throws {
        let helper = try ResidentHelper(mode: "slow-first")
        defer { helper.remove() }
        let engine = ResidentTranscriber(); defer { engine.shutdown() }
        let prepared = expectation(description: "prepared")
        engine.prepare(configuration: helper.configuration()) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            prepared.fulfill()
        }
        wait(for: [prepared], timeout: 4)
        let cancelled = expectation(description: "cancelled")
        engine.transcribe(samples: [0.1], configuration: helper.configuration()) { result in
            guard case .failure(TranscriptionError.cancelled) = result else {
                XCTFail("Expected cancellation"); cancelled.fulfill(); return
            }
            cancelled.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { engine.cancel() }
        wait(for: [cancelled], timeout: 4)
        let final = expectation(description: "final")
        engine.transcribe(samples: [0.1], configuration: helper.configuration()) { result in
            XCTAssertEqual(try? result.get(), "test result"); final.fulfill()
        }
        wait(for: [final], timeout: 4)
        XCTAssertEqual(helper.starts, 1, "Cancelling a preview should preserve model memory")
    }

    func testBrokenWorkerIsRestarted() throws {
        let helper = try ResidentHelper(mode: "crash-first")
        defer { helper.remove() }
        let engine = ResidentTranscriber(); defer { engine.shutdown() }
        let crash = expectation(description: "crash")
        engine.transcribe(samples: [0.1], configuration: helper.configuration()) { result in
            if case .success = result { XCTFail("Expected child failure") }; crash.fulfill()
        }
        wait(for: [crash], timeout: 4)
        let retry = expectation(description: "restart")
        engine.transcribe(samples: [0.1], configuration: helper.configuration()) { result in
            XCTAssertEqual(try? result.get(), "test result"); retry.fulfill()
        }
        wait(for: [retry], timeout: 4)
        XCTAssertEqual(helper.starts, 2)
    }

    func testStartupTimeoutIsBounded() throws {
        let helper = try ResidentHelper(mode: "never-ready")
        defer { helper.remove() }
        let engine = ResidentTranscriber(timeout: 0.2); defer { engine.shutdown() }
        let done = expectation(description: "startup timeout")
        engine.prepare(configuration: helper.configuration()) { result in
            guard case .failure(TranscriptionError.timedOut) = result else {
                XCTFail("Expected timeout"); done.fulfill(); return
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 4)
    }

    func testAutomaticCopyPreservesNewUserClipboardAndSkipsEmptyResult() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("old clipboard", forType: .string)
        let atStop = board.changeCount
        XCTAssertTrue(ClipboardWriter.copyIfUnchanged("final transcript", since: atStop, to: board))
        XCTAssertEqual(board.string(forType: .string), "final transcript")
        let nextStop = board.changeCount
        board.clearContents(); board.setString("user's newer copy", forType: .string)
        XCTAssertFalse(ClipboardWriter.copyIfUnchanged("late transcript", since: nextStop, to: board))
        XCTAssertEqual(board.string(forType: .string), "user's newer copy")
        XCTAssertFalse(ClipboardWriter.copyIfUnchanged("", since: board.changeCount, to: board))
        XCTAssertEqual(board.string(forType: .string), "user's newer copy")
    }
}

private struct ResidentHelper {
    let directory: URL
    let url: URL
    init(mode: String = "normal") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-paste-resident-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("test worker")
        let script = #"""
        #!/bin/sh
        set -eu
        echo "$$" >> "$0.starts"
        MODE="__MODE__"
        if [ "$MODE" = never-ready ]; then exec /bin/sleep 30; fi
        echo '{"type":"ready"}'
        count=0
        cancelled=0
        trap 'cancelled=1' USR1
        while IFS= read -r request; do
          count=$((count + 1))
          id=$(printf '%s' "$request" | /usr/bin/sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
          audio=$(printf '%s' "$request" | /usr/bin/sed -E 's/.*"path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' | /usr/bin/sed 's@\\/@/@g')
          printf '%s' "$audio" > "$0.audio"
          if [ "$MODE" = crash-first ] && [ ! -e "$0.crashed" ]; then touch "$0.crashed"; exit 9; fi
          cancelled=0
          printf '{"type":"started","id":"%s"}\n' "$id"
          if [ "$MODE" = slow-first ] && [ "$count" = 1 ]; then
            i=0
            while [ "$i" -lt 20 ] && [ "$cancelled" = 0 ]; do
              /bin/sleep 0.1 || true
              i=$((i + 1))
            done
          fi
          if [ "$cancelled" = 1 ]; then
            printf '{"type":"cancelled","id":"%s"}\n' "$id"
          else
            printf '{"type":"result","id":"%s","text":"test result"}\n' "$id"
          fi
        done
        """#.replacingOccurrences(of: "__MODE__", with: mode)
        try (script + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    var starts: Int {
        ((try? String(contentsOfFile: url.path + ".starts", encoding: .utf8)) ?? "").split(separator: "\n").count
    }
    func configuration(language: String = "ko") -> TranscriptionConfiguration {
        TranscriptionConfiguration(executable: url, model: directory.appendingPathComponent("model.bin"), language: language)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
