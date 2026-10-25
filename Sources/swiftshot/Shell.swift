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
    static func failure(_ message: String) { emit("\u{001B}[31m✘\u{001B}[0m \(message)") }
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
        timeout: TimeInterval? = nil, onTimeout: (@Sendable (Int32) -> Void)? = nil,
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
        // Done once the output reached EOF and the process exited, in either order. (A
        // readabilityHandler could still be appending its last chunk when the termination handler
        // took the output: a large `simctl list -j` came back cut short.)
        let done = DispatchGroup()
        done.enter(); done.enter()
        process.terminationHandler = { _ in done.leave() }
        do { try process.run() } catch { continuation.resume(throwing: error); return }
        Thread.detachNewThread {
            let handle = pipe.fileHandleForReading
            while case let data = handle.availableData, !data.isEmpty { buffer.append(data) }
            done.leave()
        }
        done.notify(queue: .global()) {
            let output = buffer.string
            if process.terminationStatus != 0 && !allowFailure {
                continuation.resume(throwing: ShellError(command: display, status: process.terminationStatus, output: output))
            } else {
                continuation.resume(returning: output)
            }
        }
        // A command that should be quick but isn't shows up in the log (a stall is otherwise silent).
        DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
            if process.isRunning && timeout == nil { Log.warn("still running after 300s: \(display)") }
        }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    buffer.append(Data("\n[swiftshot] timed out after \(Int(timeout))s\n".utf8))
                    onTimeout?(process.processIdentifier)
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
