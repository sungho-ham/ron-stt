import XCTest
@testable import WhisperPasteCore

final class CoreTests: XCTestCase {
    func testWAVHasStandardPCMHeaderAndClampsInvalidSamples() {
        let data = AudioData.wav([-2, -1, 0, 1, 2, .nan, .infinity])
        func u16(_ offset: Int) -> UInt16 { UInt16(data[offset]) | UInt16(data[offset + 1]) << 8 }
        func u32(_ offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << (8 * $1) }
        }
        XCTAssertEqual(data.count, 44 + 14)
        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<16], encoding: .ascii), "WAVEfmt ")
        XCTAssertEqual(u32(4), UInt32(data.count - 8))
        XCTAssertEqual(u16(20), 1) // uncompressed PCM
        XCTAssertEqual(u16(22), 1) // mono
        XCTAssertEqual(u32(24), 16_000)
        XCTAssertEqual(u32(28), 32_000)
        XCTAssertEqual(u16(34), 16)
        XCTAssertEqual(u32(40), 14)
        XCTAssertEqual(Int16(bitPattern: u16(44)), -32767)
        XCTAssertEqual(Int16(bitPattern: u16(50)), 32767)
        XCTAssertEqual(u16(54), 0) // NaN
        XCTAssertEqual(u16(56), 0) // infinity
    }

    func testEnergyGateRejectsSilenceAndClickButKeepsSpeechWithLongSilence() {
        XCTAssertFalse(AudioData.hasSignal([]))
        XCTAssertFalse(AudioData.hasSignal(Array(repeating: 0, count: 16_000)))
        var click = Array(repeating: Float(0), count: 16_000)
        click[100] = 1
        XCTAssertFalse(AudioData.hasSignal(click))
        let speech = Array(repeating: Float(0.02), count: 8_000)
        XCTAssertTrue(AudioData.hasSignal(speech + Array(repeating: 0, count: 160_000)))
        XCTAssertFalse(AudioData.hasSignal(Array(repeating: 0.0001, count: 16_000)))
    }

    func testArgumentsPreservePathsWithSpacesAndNoShellEvaluation() {
        let config = TranscriptionConfiguration(executable: URL(fileURLWithPath: "/bin/true"),
            model: URL(fileURLWithPath: "/a path/$(not-a-command)/model.bin"), language: "ko", useGPU: false)
        let args = config.arguments(input: URL(fileURLWithPath: "/tmp/a file.wav"),
                                    output: URL(fileURLWithPath: "/tmp/out file"))
        XCTAssertEqual(args[1], "/a path/$(not-a-command)/model.bin")
        XCTAssertEqual(args[3], "/tmp/a file.wav")
        XCTAssertEqual(args[5], "ko")
        XCTAssertTrue(args.contains("-ng"))
        XCTAssertFalse(args.contains("-tr")) // transcribe, do not translate
    }

    func testWorkerReadsTranscriptAndRemovesTemporaryAudio() throws {
        let helper = try Helper(script: """
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -of) shift; output="$1" ;;
            -f) shift; input="$1" ;;
          esac
          shift
        done
        test -f "$input" || exit 4
        printf '%s' "$input" > "$0.input-path"
        printf '  안녕하세요.\\n\\nTest prompt.\\n' > "$output.txt"
        """)
        defer { helper.remove() }
        let engine = Transcriber()
        let done = expectation(description: "transcript")
        engine.transcribe(samples: [0, 0.5, 0], configuration: helper.configuration) { result in
            XCTAssertEqual(try? result.get(), "안녕하세요. Test prompt.")
            XCTAssertTrue(Thread.isMainThread)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        let input = try String(contentsOfFile: helper.url.path + ".input-path", encoding: .utf8)
        XCTAssertFalse(FileManager.default.fileExists(atPath: input))
    }

    func testWorkerReportsNonzeroExitWithoutLeakingTemporaryAudio() throws {
        let helper = try Helper(script: "echo 'Model is not valid' >&2\nexit 9")
        defer { helper.remove() }
        let engine = Transcriber()
        let done = expectation(description: "failure")
        engine.transcribe(samples: [0], configuration: helper.configuration) { result in
            guard case .failure(let error) = result else { XCTFail("Expected failure"); done.fulfill(); return }
            XCTAssertTrue(error.localizedDescription.contains("Model is not valid"))
            XCTAssertTrue(error.localizedDescription.contains("9"))
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testCancellationDiscardsQueuedJobAndAllowsNextRecording() throws {
        let helper = try Helper(script: "exec /bin/sleep 30")
        defer { helper.remove() }
        let engine = Transcriber()
        let done = expectation(description: "cancelled jobs"); done.expectedFulfillmentCount = 2
        for _ in 0..<2 {
            engine.transcribe(samples: [0], configuration: helper.configuration) { result in
                guard case .failure(TranscriptionError.cancelled) = result else {
                    XCTFail("Obsolete job must be cancelled"); done.fulfill(); return
                }
                done.fulfill()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { engine.cancel() }
        wait(for: [done], timeout: 4)
        let fresh = try Helper(script: "while [ \"$1\" != '-of' ]; do shift; done\nshift\nprintf 'new' > \"$1.txt\"")
        defer { fresh.remove() }
        let freshDone = expectation(description: "fresh generation")
        engine.transcribe(samples: [0], configuration: fresh.configuration) { result in
            XCTAssertEqual(try? result.get(), "new"); freshDone.fulfill()
        }
        wait(for: [freshDone], timeout: 4)
    }

    func testTimeoutKillsWorkerThatIgnoresTermination() throws {
        let helper = try Helper(script: "trap '' TERM\nwhile :; do :; done")
        defer { helper.remove() }
        let engine = Transcriber(timeout: 0.3)
        let done = expectation(description: "bounded timeout")
        engine.transcribe(samples: [0], configuration: helper.configuration) { result in
            guard case .failure(TranscriptionError.timedOut) = result else {
                XCTFail("Expected timeout"); done.fulfill(); return
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 4)
    }
}

private struct Helper {
    let directory: URL
    let url: URL
    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-paste-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("fake engine")
        try ("#!/bin/sh\nset -eu\n" + script + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    var configuration: TranscriptionConfiguration {
        TranscriptionConfiguration(executable: url, model: directory.appendingPathComponent("model.bin"), language: "ko")
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
