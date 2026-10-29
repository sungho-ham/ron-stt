import Foundation
import Darwin

public struct TranscriptionConfiguration: Equatable {
    public let executable: URL
    public let model: URL
    public let language: String
    public let useGPU: Bool

    public init(executable: URL, model: URL, language: String, useGPU: Bool = true) {
        self.executable = executable; self.model = model
        self.language = language; self.useGPU = useGPU
    }

    public func arguments(input: URL, output: URL) -> [String] {
        var args = ["-m", model.path, "-f", input.path, "-l", language,
                    "-otxt", "-of", output.path, "-nt", "-np", "-t", "4"]
        if !useGPU { args.append("-ng") }
        return args
    }
}

public enum TranscriptionError: AppLocalizedError {
    case failed(String), cancelled, timedOut
    public var message: AppText {
        switch self {
        case .failed(let message): return .literal(message)
        case .cancelled: return "인식이 취소되었습니다."
        case .timedOut: return "음성 인식 시간이 초과되었습니다. Small 모델 또는 CPU 모드로 다시 시도하세요."
        }
    }
}

/// One serial worker, cancellation fenced by generation. No shell interpolation.
public final class Transcriber {
    private let queue = DispatchQueue(label: "WhisperPaste.transcription", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    private var process: Process?
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 300) { self.timeout = timeout }

    public func cancel() {
        lock.lock()
        generation += 1
        let running = process
        if let running, running.isRunning { running.terminate() }
        lock.unlock()
    }

    public func transcribe(samples: [Float], configuration: TranscriptionConfiguration,
                           completion: @escaping (Result<String, Error>) -> Void) {
        lock.lock(); let ticket = generation; lock.unlock()
        queue.async {
            let result: Result<String, Error>
            do { result = .success(try self.run(samples, configuration, ticket)) }
            catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func run(_ samples: [Float], _ config: TranscriptionConfiguration, _ ticket: Int) throws -> String {
        lock.lock(); let cancelled = ticket != generation; lock.unlock()
        guard !cancelled else { throw TranscriptionError.cancelled }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-paste-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("audio.wav")
        let output = dir.appendingPathComponent("transcript")
        let log = dir.appendingPathComponent("engine.log")
        try AudioData.wav(samples).write(to: input, options: .atomic)
        _ = FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? logHandle.close() }
        let task = Process()
        task.executableURL = config.executable
        task.arguments = config.arguments(input: input, output: output)
        task.standardOutput = logHandle; task.standardError = logHandle
        lock.lock()
        guard ticket == generation else { lock.unlock(); throw TranscriptionError.cancelled }
        do { try task.run(); process = task; lock.unlock() }
        catch { lock.unlock(); throw error }
        // Polling is confined to the background worker; UI and audio keep running.
        let deadline = Date().addingTimeInterval(timeout)
        var timeout = false
        var terminationDeadline: Date?
        while task.isRunning {
            lock.lock(); let obsolete = ticket != generation; lock.unlock()
            if terminationDeadline == nil && (obsolete || Date() > deadline) {
                timeout = !obsolete
                task.terminate()
                terminationDeadline = Date().addingTimeInterval(1)
            }
            if let terminationDeadline, Date() > terminationDeadline, task.isRunning {
                kill(task.processIdentifier, SIGKILL)
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        task.waitUntilExit()
        lock.lock(); process = nil; let wasCancelled = ticket != generation; lock.unlock()
        if wasCancelled { throw TranscriptionError.cancelled }
        if timeout { throw TranscriptionError.timedOut }
        guard task.terminationStatus == 0 else {
            let detail = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw AppText("whisper.cpp 실행 실패 ({0}).\n{1}", .literal(String(task.terminationStatus)), .literal(String(detail.suffix(1600))))
        }
        // CLI segment separators are not intentional Enter presses in a prompt.
        return try String(contentsOf: output.appendingPathExtension("txt"), encoding: .utf8)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
