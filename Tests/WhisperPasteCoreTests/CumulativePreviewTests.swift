import XCTest
@testable import WhisperPasteCore

final class CumulativePreviewTests: XCTestCase {
    private func audio(_ seconds: Double, level: Float = 0.05) -> [Float] {
        Array(repeating: level, count: Int(seconds * Double(AudioData.sampleRate)))
    }

    func testPreviewAccumulatesAcross30And60SecondsWithoutEatingRepeatedWords() throws {
        let samples = audio(23) + audio(1, level: 0) + audio(23) + audio(1, level: 0) + audio(22)
        var preview = CumulativePreview()
        let first = try XCTUnwrap(preview.nextRequest(in: Array(samples.prefix(10 * AudioData.sampleRate))))
        XCTAssertFalse(first.sealsChunk)
        preview.complete(first, text: "첫 문장 초안")
        XCTAssertEqual(preview.text, "첫 문장 초안")

        let seal = try XCTUnwrap(preview.nextRequest(in: Array(samples.prefix(25 * AudioData.sampleRate))))
        XCTAssertTrue(seal.sealsChunk)
        XCTAssertEqual(seal.range, 0..<(23 * AudioData.sampleRate + AudioData.sampleRate / 4))
        preview.complete(seal, text: "첫 문장. 네.")

        let second = try XCTUnwrap(preview.nextRequest(in: Array(samples.prefix(35 * AudioData.sampleRate))))
        XCTAssertEqual(second.range.lowerBound, seal.range.upperBound)
        preview.complete(second, text: "네. 두 번째 초안")
        XCTAssertEqual(preview.text, "첫 문장. 네. 네. 두 번째 초안")

        let secondSeal = try XCTUnwrap(preview.nextRequest(in: Array(samples.prefix(60 * AudioData.sampleRate))))
        XCTAssertTrue(secondSeal.sealsChunk)
        preview.complete(secondSeal, text: "네. 두 번째 문장.")
        let third = try XCTUnwrap(preview.nextRequest(in: samples))
        XCTAssertEqual(third.range.lowerBound, secondSeal.range.upperBound)
        XCTAssertEqual(third.range.upperBound, samples.count)
        preview.complete(third, text: "세 번째 문장.")
        XCTAssertEqual(preview.text, "첫 문장. 네. 네. 두 번째 문장. 세 번째 문장.")
    }

    func testContinuousSpeechIsNeverTrimmedAt30SecondsEvenAtFiveMinutes() throws {
        var preview = CumulativePreview()
        for seconds in [2, 29, 31, 61, 90, 300] {
            let samples = audio(Double(seconds))
            let request = try XCTUnwrap(preview.nextRequest(in: samples))
            XCTAssertEqual(request.range, 0..<samples.count)
            XCTAssertFalse(request.sealsChunk)
            preview.complete(request, text: "처음부터 \(seconds)초까지")
            XCTAssertEqual(preview.sampleOffset, 0)
        }
        XCTAssertEqual(preview.text, "처음부터 300초까지")
    }

    func testShortGapIsNotAChunkBoundaryAndLatePauseKeepsAllAudio() throws {
        var preview = CumulativePreview()
        let samples = audio(23) + audio(0.3, level: 0) + audio(40)
        let long = try XCTUnwrap(preview.nextRequest(in: samples))
        XCTAssertFalse(long.sealsChunk)
        preview.complete(long, text: "긴 문장")
        let paused = try XCTUnwrap(preview.nextRequest(in: samples + audio(1, level: 0)))
        XCTAssertTrue(paused.sealsChunk)
        XCTAssertEqual(paused.range.lowerBound, 0)
        XCTAssertGreaterThan(paused.range.upperBound, samples.count)
    }

    func testFailureEmptyResultAndRetryRetainVisibleTextAndAudio() throws {
        var preview = CumulativePreview()
        let samples = audio(23) + audio(1, level: 0)
        let partial = try XCTUnwrap(preview.nextRequest(in: Array(samples.prefix(10 * AudioData.sampleRate))))
        preview.complete(partial, text: "기존 결과")
        let failed = try XCTUnwrap(preview.nextRequest(in: samples))
        XCTAssertNil(preview.nextRequest(in: samples), "Only one in-flight preview")
        preview.fail(failed)
        XCTAssertEqual(preview.text, "기존 결과")
        XCTAssertEqual(preview.sampleOffset, 0)
        let empty = try XCTUnwrap(preview.nextRequest(in: samples))
        XCTAssertFalse(preview.complete(empty, text: " \n"))
        XCTAssertEqual(preview.text, "기존 결과")
        XCTAssertEqual(preview.sampleOffset, 0)
        let retry = try XCTUnwrap(preview.nextRequest(in: samples))
        XCTAssertEqual(retry.range, failed.range)
        XCTAssertFalse(preview.complete(failed, text: "늦은 응답"))
        XCTAssertTrue(preview.complete(retry, text: "완성 결과"))
        XCTAssertFalse(preview.complete(retry, text: "중복 응답"))
        XCTAssertEqual(preview.text, "완성 결과")
    }

    func testSilenceAfterSpeechDoesNotEraseCommittedText() throws {
        var preview = CumulativePreview()
        let samples = audio(23) + audio(30, level: 0)
        let spoken = try XCTUnwrap(preview.nextRequest(in: samples))
        preview.complete(spoken, text: "앞부분 유지")
        let silent = try XCTUnwrap(preview.nextRequest(in: samples))
        XCTAssertFalse(silent.hasSignal)
        XCTAssertTrue(silent.sealsChunk)
        preview.complete(silent, text: "")
        XCTAssertEqual(preview.text, "앞부분 유지")
        let tail = try XCTUnwrap(preview.nextRequest(in: samples))
        XCTAssertEqual(tail.range.lowerBound, silent.range.upperBound)
        XCTAssertFalse(tail.hasSignal)
        preview.complete(tail, text: "")
        XCTAssertEqual(preview.text, "앞부분 유지")
    }

    func testResetRejectsPreviousRecordingCallbacks() throws {
        var preview = CumulativePreview()
        let previous = try XCTUnwrap(preview.nextRequest(in: audio(24)))
        preview.reset()
        XCTAssertEqual(preview.text, "")
        XCTAssertEqual(preview.sampleOffset, 0)
        XCTAssertNil(preview.nextRequest(in: audio(1)))
        let fresh = try XCTUnwrap(preview.nextRequest(in: audio(2)))
        XCTAssertFalse(preview.complete(previous, text: "이전 녹음"))
        preview.fail(previous)
        XCTAssertTrue(preview.complete(fresh, text: "새 녹음"))
        XCTAssertEqual(preview.text, "새 녹음")
    }
}
