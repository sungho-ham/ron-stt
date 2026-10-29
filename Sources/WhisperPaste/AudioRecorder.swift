import AVFoundation
import WhisperPasteCore

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var failure: String?
    static let maximumSeconds = 300

    func start() throws {
        lock.lock(); samples = []; failure = nil; lock.unlock()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else {
            throw AppText("사용 가능한 마이크 입력 장치가 없습니다.")
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / format.sampleRate + 64)
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            self.lock.lock()
            defer { self.lock.unlock() }
            if let error { self.failure = error.localizedDescription; return }
            guard let channel = converted.floatChannelData?[0] else { return }
            let remaining = Self.maximumSeconds * AudioData.sampleRate - self.samples.count
            if remaining > 0 {
                self.samples.append(contentsOf: UnsafeBufferPointer(start: channel,
                    count: min(Int(converted.frameLength), remaining)))
            }
        }
        do { engine.prepare(); try engine.start(); self.engine = engine }
        catch { input.removeTap(onBus: 0); throw error }
    }

    func snapshot(lastSeconds: Int? = nil) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        if let lastSeconds { return Array(samples.suffix(lastSeconds * AudioData.sampleRate)) }
        return samples
    }

    var duration: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(samples.count) / Double(AudioData.sampleRate)
    }

    var error: String? {
        lock.lock(); defer { lock.unlock() }
        return failure
    }

    func stop() -> [Float] {
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        return snapshot()
    }

    func discard() { _ = stop(); lock.lock(); samples = []; lock.unlock() }
}
