import Foundation

public enum AudioData {
    public static let sampleRate = 16_000

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }

    // Do not ask Whisper to invent a transcript for digital silence or a tap click.
    // This is an energy gate, not a speech classifier. The UI explains quiet input.
    public static func hasSignal(_ samples: [Float]) -> Bool {
        let window = sampleRate / 10
        guard samples.count >= sampleRate / 2 else { return false }
        var activeWindows = 0
        for start in stride(from: 0, to: samples.count, by: window) {
            let end = min(start + window, samples.count)
            var energy: Float = 0
            for i in start..<end { energy += samples[i] * samples[i] }
            if sqrt(energy / Float(end - start)) > 0.003 { activeWindows += 1 }
        }
        return activeWindows >= 3
    }

    public static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + samples.count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(samples.count * 2))
        for sample in samples {
            let safe = sample.isFinite ? max(-1, min(1, sample)) : 0
            append(Int16(safe * 32767))
        }
        return data
    }
}
