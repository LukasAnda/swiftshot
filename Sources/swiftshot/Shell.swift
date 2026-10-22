import Foundation

struct ShellError: Error, CustomStringConvertible {
    let command: String
    let status: Int32
    let output: String
    var description: String { "`\(command)` failed (\(status)):\n\(output.suffix(4000))" }
}

enum Log {
    static var verbose = false
    static let start = Date()
    private static let lock = NSLock()

    static func info(_ message: String) { emit("\u{001B}[36m▸\u{001B}[0m \(message)") }
    static func success(_ message: String) { emit("\u{001B}[32m✔\u{001B}[0m \(message)") }
    static func warn(_ message: String) { emit("\u{001B}[33m!\u{001B}[0m \(message)") }
    static func debug(_ message: String) { if verbose { emit("  \u{001B}[2m\(message)\u{001B}[0m") } }

    private static func emit(_ line: String) {
        let t = String(format: "%6.1fs", Date().timeIntervalSince(start))
        lock.lock(); defer { lock.unlock() }
        FileHandle.standardError.write("\u{001B}[2m\(t)\u{001B}[0m \(line)\n".data(using: .utf8)!)
    }
}

/// Runs a process to completion off the cooperative pool and returns its combined output.
@discardableResult
func sh(_ args: [String], env: [String: String] = [:], cwd: String? = nil, allowFailure: Bool = false, stdoutOnly: Bool = false,
        timeout: TimeInterval? = nil,
        onLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
    let display = args.joined(separator: " ")
    Log.debug("$ \(display)")
    return try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        process.environment = environment
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = stdoutOnly ? FileHandle.nullDevice : pipe
        process.standardInput = FileHandle.nullDevice

        let buffer = OutputBuffer(onLine: onLine)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { buffer.append(data) }
        }
        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            buffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
            let output = buffer.string
            if p.terminationStatus != 0 && !allowFailure {
                continuation.resume(throwing: ShellError(command: display, status: p.terminationStatus, output: output))
            } else {
                continuation.resume(returning: output)
            }
        }
        do { try process.run() } catch { continuation.resume(throwing: error); return }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    buffer.append(Data("\n[swiftshot] timed out after \(Int(timeout))s\n".utf8))
                    process.terminate()
                }
            }
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private var pending = ""
    private let lock = NSLock()
    let onLine: (@Sendable (String) -> Void)?
    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        guard let onLine else { return }
        pending += String(decoding: chunk, as: UTF8.self)
        while let range = pending.range(of: "\n") {
            onLine(String(pending[..<range.lowerBound]))
            pending.removeSubrange(..<range.upperBound)
        }
    }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}

func ms(since start: Date) -> String { String(format: "%.1fs", Date().timeIntervalSince(start)) }
