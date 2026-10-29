import AppKit
import Darwin
import Carbon

/// osascript only runs static code. User content travels as JSON on private stdin, not
/// script source, command-line arguments, keystroke text, or shell commands.
public final class TerminalBridge {
    private let queue = DispatchQueue(label: "WhisperPaste.terminal", qos: .userInitiated)
    public init() {}

    public func capture(_ candidate: TerminalDestination, requireFrontmost: Bool = false, timeout: Double = 30,
                        completion: @escaping (Result<TerminalDestination, Error>) -> Void) {
        perform(operation: "capture", destination: candidate, requireFrontmost: requireFrontmost,
                timeout: timeout, completion: completion)
    }

    /// Background tracking must never open permission dialogs just because focus moves.
    public static func automationAllowed(for target: TerminalDestination) -> Bool {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: target.bundleID)
        return AEDeterminePermissionToAutomateTarget(descriptor.aeDesc, typeWildCard, typeWildCard, false) == noErr
    }

    public func preparePaste(_ target: TerminalDestination, completion: @escaping (Result<TerminalDestination, Error>) -> Void) {
        perform(operation: "focus", destination: target, completion: completion)
    }

    public func send(_ text: String, to target: TerminalDestination, completion: @escaping (Result<TerminalDestination, Error>) -> Void) {
        perform(operation: "send", destination: target, text: text, completion: completion)
    }

    public static func validate(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 256 * 1024,
              !text.unicodeScalars.contains(where: {
                  ($0.value < 32 && ![9, 10, 13].contains($0.value)) || (127...159).contains($0.value)
              }) else { throw TerminalBridgeError.invalidText }
    }

    private func perform(operation: String, destination: TerminalDestination, text: String = "",
                         requireFrontmost: Bool = false, timeout: Double = 30,
                         completion: @escaping (Result<TerminalDestination, Error>) -> Void) {
        queue.async {
            let result: Result<TerminalDestination, Error>
            do {
                guard destination.runningApplication != nil else { throw TerminalBridgeError.unavailable }
                if operation == "send" {
                    try Self.validate(text)
                    guard !destination.needsClipboard(for: text) else { throw TerminalBridgeError.failed }
                }
                if destination.kind == .application {
                    result = .success(destination)
                } else {
                    var request = try JSONSerialization.jsonObject(with: JSONEncoder().encode(destination)) as! [String: Any]
                    request["operation"] = operation; request["text"] = text
                    request["requireFrontmost"] = requireFrontmost
                    let response = try Self.runScript(request, timeout: timeout)
                    if let error = response["error"] as? String {
                        switch error {
                        case "permission": throw TerminalBridgeError.permission
                        case "unavailable": throw TerminalBridgeError.unavailable
                        case "missing": throw TerminalBridgeError.missingTarget
                        default: throw TerminalBridgeError.failed
                        }
                    }
                    guard response["ok"] as? Bool == true else { throw TerminalBridgeError.failed }
                    var updated = destination
                    if operation == "capture" {
                        guard let value = response["target"] as? [String: String],
                              let windowID = value["windowID"], !windowID.isEmpty,
                              let terminalID = value["terminalID"], !terminalID.isEmpty else {
                            throw TerminalBridgeError.missingTarget
                        }
                        updated.windowID = windowID; updated.terminalID = terminalID
                        updated.windowTitle = value["windowTitle"] ?? ""
                        updated.tabID = value["tabID"] ?? ""
                        updated.terminalTitle = value["terminalTitle"] ?? ""
                    }
                    result = .success(updated)
                }
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // Files avoid pipe-capacity deadlocks for large manually edited prompts.
    // The private directory is removed even after a timeout; no transcript log is kept.
    static func runScript(_ request: [String: Any], timeout: Double = 30) throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-paste-terminal-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("request.json")
        let outputURL = directory.appendingPathComponent("response.json")
        let data = try JSONSerialization.data(withJSONObject: request)
        guard FileManager.default.createFile(atPath: inputURL.path, contents: data, attributes: [.posixPermissions: 0o600]),
              FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw TerminalBridgeError.failed
        }
        let input = try FileHandle(forReadingFrom: inputURL), output = try FileHandle(forWritingTo: outputURL)
        defer { try? input.close(); try? output.close() }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-l", "JavaScript", "-e", TerminalScript.source]
        task.standardInput = input; task.standardOutput = output; task.standardError = FileHandle.nullDevice
        try task.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while task.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if task.isRunning {
            task.terminate()
            let end = ProcessInfo.processInfo.systemUptime + 0.5
            while task.isRunning && ProcessInfo.processInfo.systemUptime < end { Thread.sleep(forTimeInterval: 0.02) }
            if task.isRunning { kill(task.processIdentifier, SIGKILL) }
            throw TerminalBridgeError.timedOut
        }
        guard task.terminationStatus == 0,
              let response = try JSONSerialization.jsonObject(with: Data(contentsOf: outputURL)) as? [String: Any] else {
            throw TerminalBridgeError.failed
        }
        return response
    }
}
