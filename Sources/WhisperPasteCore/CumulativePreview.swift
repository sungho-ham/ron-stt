import Foundation

/// A recording's stable prefix plus its revisable current utterance. Audio ranges
/// partition the original recording; matching/deduplicating text would eat real repeats.
public struct CumulativePreview {
    public struct Request: Equatable {
        fileprivate let id: UUID
        public let range: Range<Int>
        public let sealsChunk: Bool
        public let hasSignal: Bool
    }

    public private(set) var sampleOffset = 0
    public private(set) var committedText = ""
    private var partialText = ""
    private var pending: Request?

    public init() {}

    public var text: String { Self.join(committedText, partialText) }

    public mutating func reset() { self = Self() }

    /// `samples` must contain this session's entire recording, not a rolling suffix.
    /// Prefer a quiet boundary after 20 seconds. Without one, retain all pending
    /// audio, even beyond 30 seconds: latency may grow, but no speech is cut away.
    public mutating func nextRequest(in samples: [Float]) -> Request? {
        guard pending == nil, samples.count - sampleOffset >= AudioData.sampleRate * 3 / 2 else { return nil }
        let boundary = quietBoundary(in: samples)
        let range = sampleOffset..<(boundary ?? samples.count)
        let request = Request(id: UUID(), range: range, sealsChunk: boundary != nil,
                              hasSignal: AudioData.hasSignal(Array(samples[range])))
        pending = request
        return request
    }

    /// Errors and empty speech results leave the last readable preview intact.
    /// Request identity also fences callbacks from before reset or a retry.
    @discardableResult
    public mutating func complete(_ request: Request, text: String) -> Bool {
        guard pending == request else { return false }
        pending = nil
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.hasSignal || !clean.isEmpty else { return false }
        if request.sealsChunk {
            committedText = Self.join(committedText, clean)
            partialText = ""
            sampleOffset = request.range.upperBound
        } else {
            partialText = clean
        }
        return true
    }

    public mutating func fail(_ request: Request) {
        if pending == request { pending = nil }
    }

    private func quietBoundary(in samples: [Float]) -> Int? {
        let window = AudioData.sampleRate / 10
        let start = sampleOffset + 20 * AudioData.sampleRate
        let quietFrames = 5 * window // 500 ms; a conservative energy heuristic, not VAD.
        guard samples.count - start >= quietFrames else { return nil }
        var quietStart: Int?
        for offset in stride(from: start, through: samples.count - window, by: window) {
            var energy: Float = 0
            for i in offset..<(offset + window) { energy += samples[i] * samples[i] }
            if sqrt(energy / Float(window)) < 0.003 {
                if quietStart == nil { quietStart = offset }
                if let quietStart, offset + window - quietStart >= quietFrames {
                    // Keep quiet padding on both sides, with neither overlap nor gaps.
                    return quietStart + quietFrames / 2
                }
            } else { quietStart = nil }
        }
        return nil
    }

    private static func join(_ first: String, _ second: String) -> String {
        [first, second].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
