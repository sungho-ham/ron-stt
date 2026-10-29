import XCTest
import AVFoundation
@testable import WhisperPasteCore

/// Opt-in: scripts/smoke-test.sh generates this non-private Korean speech fixture.
final class RealEngineTests: XCTestCase {
    func testCumulativePreviewWithRealSpeechBeyondOneMinute() throws {
        guard let fixture = ProcessInfo.processInfo.environment["WHISPER_PASTE_TEST_WAV"] else {
            throw XCTSkip("Run scripts/smoke-test.sh for real-model integration testing.")
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: fixture))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                  frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        let speech = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let block = Array(repeating: speech, count: 3).flatMap { $0 } + Array(repeating: Float(0), count: 16_000)
        let samples = Array(repeating: block, count: 4).flatMap { $0 }
        XCTAssertGreaterThan(samples.count, 60 * AudioData.sampleRate)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binaries = ProcessInfo.processInfo.environment["WHISPER_PASTE_TEST_BIN_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent("Applications/Whisper Paste.app/Contents/Resources/bin")
        let resident = ResidentTranscriber()
        defer { resident.shutdown() }
        for model in ["small", "medium"] {
            let config = TranscriptionConfiguration(executable: binaries.appendingPathComponent("whisper-worker"),
                model: home.appendingPathComponent("Library/Application Support/WhisperPaste/models/ggml-\(model).bin"),
                language: "ko")
            var preview = CumulativePreview()
            var firstCommitted = "", sealedCount = 0
            for limit in [10, 24, 31, 46, 61].map({ $0 * AudioData.sampleRate }) + [samples.count] {
                let available = Array(samples.prefix(limit))
                // A delayed inference may need to catch up through multiple completed chunks.
                while let request = preview.nextRequest(in: available) {
                    let previous = preview.committedText
                    var resultText = ""
                    if request.hasSignal {
                        let done = expectation(description: "cumulative \(model) at \(limit / 16_000)s")
                        let started = Date()
                        resident.transcribe(samples: Array(available[request.range]), configuration: config) { result in
                            do { resultText = try result.get() } catch { XCTFail("\(error)") }
                            print("CUMULATIVE \(model) range=\(request.range) seals=\(request.sealsChunk) inference=\(-started.timeIntervalSinceNow)s")
                            done.fulfill()
                        }
                        wait(for: [done], timeout: 60)
                        XCTAssertFalse(resultText.isEmpty)
                    }
                    let accepted = preview.complete(request, text: resultText)
                    XCTAssertTrue(accepted)
                    guard accepted else { break }
                    XCTAssertTrue(preview.text.hasPrefix(previous))
                    if request.sealsChunk {
                        sealedCount += 1
                        if firstCommitted.isEmpty { firstCommitted = preview.committedText }
                    }
                    if !firstCommitted.isEmpty { XCTAssertTrue(preview.text.hasPrefix(firstCommitted)) }
                    if !request.sealsChunk { break }
                }
            }
            XCTAssertGreaterThanOrEqual(sealedCount, 3)
            XCTAssertTrue(firstCommitted.contains("회의"), firstCommitted)
            XCTAssertGreaterThan(preview.text.count, firstCommitted.count * 2)
            print("CUMULATIVE \(model) retained first chunk through \(samples.count / 16_000)s, sealed=\(sealedCount), characters=\(preview.text.count)")
        }
    }

    func testResidentAccuracyCancellationAndWarmLatencyAgainstCLI() throws {
        guard let fixture = ProcessInfo.processInfo.environment["WHISPER_PASTE_TEST_WAV"] else {
            throw XCTSkip("Run scripts/smoke-test.sh for real-model integration testing.")
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: fixture))
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                  frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        XCTAssertTrue(AudioData.hasSignal(samples))
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binaries = ProcessInfo.processInfo.environment["WHISPER_PASTE_TEST_BIN_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent("Applications/Whisper Paste.app/Contents/Resources/bin")
        let binary = binaries.appendingPathComponent("whisper-cli")
        let residentBinary = binaries.appendingPathComponent("whisper-worker")
        let engine = Transcriber(), resident = ResidentTranscriber()
        defer { resident.shutdown() }
        for model in ["small", "medium"] {
            let config = TranscriptionConfiguration(executable: binary,
                model: home.appendingPathComponent("Library/Application Support/WhisperPaste/models/ggml-\(model).bin"),
                language: "ko")
            let persistent = TranscriptionConfiguration(executable: residentBinary, model: config.model, language: "ko")
            var baseline = "", baselineTimes: [Double] = [], warmTimes: [Double] = []
            for _ in 0..<3 {
                let done = expectation(description: "CLI \(model)")
                let start = Date()
                engine.transcribe(samples: samples, configuration: config) { result in
                    do { baseline = try result.get(); baselineTimes.append(-start.timeIntervalSinceNow) }
                    catch { XCTFail("\(model): \(error)") }
                    done.fulfill()
                }
                wait(for: [done], timeout: 60)
            }
            XCTAssertTrue(baseline.contains("회의"), baseline)
            XCTAssertTrue(baseline.contains("담당자"), baseline)
            let ready = expectation(description: "prepare \(model)")
            resident.prepare(configuration: persistent) { result in
                if case .failure(let error) = result { XCTFail("\(error)") }; ready.fulfill()
            }
            wait(for: [ready], timeout: 60)
            // A short preview must not bias the full final transcription.
            let preview = expectation(description: "short preview")
            resident.transcribe(samples: Array(samples.prefix(24_000)), configuration: persistent) { _ in preview.fulfill() }
            wait(for: [preview], timeout: 60)
            for _ in 0..<3 {
                let done = expectation(description: "resident \(model)")
                let start = Date()
                resident.transcribe(samples: samples, configuration: persistent) { result in
                    do {
                        let text = try result.get()
                        XCTAssertEqual(text, baseline, "Resident decoding must match fresh CLI decoding")
                        warmTimes.append(-start.timeIntervalSinceNow)
                    } catch { XCTFail("\(model): \(error)") }
                    done.fulfill()
                }
                wait(for: [done], timeout: 60)
            }
            let cliMedian = baselineTimes.sorted().dropFirst().first ?? .nan
            let warmMedian = warmTimes.sorted().dropFirst().first ?? .nan
            print("BENCHMARK \(model) CLI median=\(cliMedian)s, resident median=\(warmMedian)s. TEXT: \(baseline)")
            let cancelled = expectation(description: "cancel actual inference")
            let longAudio = Array(repeating: samples, count: 6).flatMap { $0 }
            resident.transcribe(samples: longAudio, configuration: persistent) { result in
                guard case .failure(TranscriptionError.cancelled) = result else {
                    XCTFail("Expected cancellation"); cancelled.fulfill(); return
                }
                cancelled.fulfill()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { resident.cancel() }
            wait(for: [cancelled], timeout: 10)
            let afterCancel = expectation(description: "fresh after abort")
            resident.transcribe(samples: samples, configuration: persistent) { result in
                XCTAssertEqual(try? result.get(), baseline); afterCancel.fulfill()
            }
            wait(for: [afterCancel], timeout: 60)
            if model == "small" {
                var longBaseline = ""
                let cliLong = expectation(description: "CLI whole recording")
                engine.transcribe(samples: longAudio, configuration: config) { result in
                    do { longBaseline = try result.get() } catch { XCTFail("\(error)") }; cliLong.fulfill()
                }
                wait(for: [cliLong], timeout: 60)
                let residentLong = expectation(description: "Resident whole recording")
                resident.transcribe(samples: longAudio, configuration: persistent) { result in
                    XCTAssertEqual(try? result.get(), longBaseline, "Final pass must retain audio beyond 30 seconds")
                    residentLong.fulfill()
                }
                wait(for: [residentLong], timeout: 60)
            }
        }
    }
}
