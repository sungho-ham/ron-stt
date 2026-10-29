import Foundation
import Darwin

/// One reusable model in an isolated child. All pipe I/O happens on the serial worker queue.
public final class ResidentTranscriber {
    private final class Worker {
        let configuration: TranscriptionConfiguration
        let process: Process
        let input: FileHandle
        let output: FileHandle
        var pending = Data()
        init(configuration: TranscriptionConfiguration, process: Process, input: FileHandle, output: FileHandle) {
            self.configuration = configuration; self.process = process; self.input = input; self.output = output
        }
    }
    private let queue = DispatchQueue(label: "WhisperPaste.resident", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    private var activeProcess: Process?
    private var inferenceStarted = false
    private var worker: Worker? // Only accessed on queue.
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 300) { self.timeout = timeout }
    deinit { stopWorker() }

    public func prepare(configuration: TranscriptionConfiguration, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        lock.lock(); let ticket = generation; lock.unlock()
        queue.async {
            let result: Result<Void, Error>
            do {
                guard !self.isCancelled(ticket) else { throw TranscriptionError.cancelled }
                _ = try self.ensureWorker(configuration)
                result = self.isCancelled(ticket) ? .failure(TranscriptionError.cancelled) : .success(())
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        if inferenceStarted, let process = activeProcess, process.isRunning {
            kill(process.processIdentifier, SIGUSR1)
        }
    }

    public func shutdown() {
        lock.lock()
        generation += 1
        if let process = activeProcess, process.isRunning { process.terminate() }
        lock.unlock()
        queue.async { self.stopWorker() }
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

    private func isCancelled(_ ticket: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }; return ticket != generation
    }

    private func ensureWorker(_ configuration: TranscriptionConfiguration) throws -> Worker {
        if let worker, worker.configuration == configuration, worker.process.isRunning { return worker }
        stopWorker()
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = configuration.executable
        process.arguments = ["--model", configuration.model.path, "--language", configuration.language]
            + (configuration.useGPU ? [] : ["--no-gpu"])
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        // Only the child owns these ends. Closing them lets an unexpected child exit produce EOF.
        try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let newWorker = Worker(configuration: configuration, process: process,
                               input: input.fileHandleForWriting, output: output.fileHandleForReading)
        worker = newWorker
        lock.lock(); activeProcess = process; inferenceStarted = false; lock.unlock()
        do {
            let ready = try readMessage(newWorker, deadline: ProcessInfo.processInfo.systemUptime + timeout)
            guard ready["type"] as? String == "ready" else {
                if let detail = ready["error"] as? String { throw TranscriptionError.failed(detail) }
                throw AppText("모델을 준비하지 못했습니다.")
            }
            return newWorker
        } catch { stopWorker(); throw error }
    }

    private func run(_ samples: [Float], _ configuration: TranscriptionConfiguration, _ ticket: Int) throws -> String {
        guard !isCancelled(ticket) else { throw TranscriptionError.cancelled }
        let worker = try ensureWorker(configuration)
        guard !isCancelled(ticket) else { throw TranscriptionError.cancelled }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-paste-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("audio.wav")
        try AudioData.wav(samples).write(to: audio, options: .atomic)
        let id = UUID().uuidString
        var request = try JSONSerialization.data(withJSONObject: ["id": id, "path": audio.path])
        request.append(0x0a)
        do {
            try worker.input.write(contentsOf: request)
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            while true {
                let response = try readMessage(worker, deadline: deadline, ticket: ticket)
                guard response["id"] as? String == id else {
                    throw AppText("음성 인식 작업 응답이 일치하지 않습니다.")
                }
                if response["type"] as? String == "started" {
                    lock.lock()
                    inferenceStarted = true
                    if ticket != generation, worker.process.isRunning { kill(worker.process.processIdentifier, SIGUSR1) }
                    lock.unlock()
                    continue
                }
                lock.lock(); inferenceStarted = false; lock.unlock()
                if isCancelled(ticket) || response["type"] as? String == "cancelled" { throw TranscriptionError.cancelled }
                guard response["type"] as? String == "result", let text = response["text"] as? String else {
                    if let detail = response["error"] as? String { throw TranscriptionError.failed(detail) }
                    throw AppText("음성 인식에 실패했습니다.")
                }
                return text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            }
        } catch TranscriptionError.cancelled {
            // A completed cancellation response keeps the model reusable for the final pass.
            throw TranscriptionError.cancelled
        } catch {
            stopWorker() // A dead/timed-out/malformed worker is never reused.
            if isCancelled(ticket) { throw TranscriptionError.cancelled }
            throw error
        }
    }

    private func readMessage(_ worker: Worker, deadline: TimeInterval, ticket: Int? = nil) throws -> [String: Any] {
        var cancellationDeadline: TimeInterval?
        while true {
            if let newline = worker.pending.firstIndex(of: 0x0a) {
                let line = Data(worker.pending[..<newline]); worker.pending.removeSubrange(...newline)
                guard let response = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw AppText("음성 엔진 응답 형식이 잘못되었습니다.")
                }
                return response
            }
            let now = ProcessInfo.processInfo.systemUptime
            if let ticket, isCancelled(ticket), cancellationDeadline == nil { cancellationDeadline = now + 2 }
            if now > deadline || (cancellationDeadline.map { now > $0 } ?? false) { throw TranscriptionError.timedOut }
            var descriptor = pollfd(fd: worker.output.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let polled = poll(&descriptor, 1, 20)
            if polled < 0 {
                if errno == EINTR { continue }
                throw AppText("음성 엔진 통신이 중단되었습니다.")
            }
            if polled > 0 {
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(worker.output.fileDescriptor, &bytes, bytes.count)
                if count <= 0 { throw AppText("음성 엔진이 종료되었습니다. 다시 녹음하면 재시작합니다.") }
                worker.pending.append(contentsOf: bytes.prefix(count))
                if worker.pending.count > 1_048_576 { throw AppText("음성 엔진 응답이 너무 큽니다.") }
            } else if !worker.process.isRunning {
                throw AppText("음성 엔진이 종료되었습니다. 다시 녹음하면 재시작합니다.")
            }
        }
    }

    private func stopWorker() {
        guard let worker else { return }
        lock.lock(); activeProcess = nil; inferenceStarted = false; lock.unlock()
        try? worker.input.close()
        if worker.process.isRunning {
            worker.process.terminate()
            let until = ProcessInfo.processInfo.systemUptime + 0.5
            while worker.process.isRunning && ProcessInfo.processInfo.systemUptime < until { Thread.sleep(forTimeInterval: 0.02) }
            if worker.process.isRunning { kill(worker.process.processIdentifier, SIGKILL) }
        }
        // Foundation can hang in waitUntilExit after a pipe-owning child has already exited.
        // Process reaps it internally; bounded isRunning polling above is sufficient here.
        try? worker.output.close(); self.worker = nil
    }
}
