import Foundation

/// A usage error: wrong flags or settings for the command, or (accept) an invalid report. Exit 64.
struct UsageError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

/// What verify, record and accept print: to the terminal, or (tests) collected in `text`.
final class Console: @unchecked Sendable {
    private let capture: Bool
    private let lock = NSLock()
    private var collected = ""
    init(capture: Bool = false) { self.capture = capture }

    var text: String { lock.lock(); defer { lock.unlock() }; return collected }

    func ok(_ s: String) { emit(s) { Log.success(s) } }
    func warn(_ s: String) { emit(s) { Log.warn(s) } }
    func error(_ s: String) { emit(s) { Log.failure(s) } }
    func plain(_ s: String) { emit(s) { print(s) } }

    private func emit(_ s: String, _ show: () -> Void) {
        if capture { lock.lock(); collected += s + "\n"; lock.unlock() } else { show() }
    }
}

/// A process run to completion, synchronously (git): exit status, stdout and stderr.
enum Proc {
    struct Result { let code: Int32; let out: String; let err: String }

    static func run(_ args: [String], cwd: URL? = nil, env: [String: String] = [:], input: Data? = nil) -> Result {
        signal(SIGPIPE, SIG_IGN)   // a child that exits before reading its input mustn't take this process along
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        p.environment = environment
        if let cwd { p.currentDirectoryURL = cwd }
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        do { try p.run() } catch { return Result(code: -1, out: "", err: "\(args.first ?? "") could not start: \(error.localizedDescription)") }
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async {
            if let input { try? inp.fileHandleForWriting.write(contentsOf: input) }
            try? inp.fileHandleForWriting.close()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        return Result(code: p.terminationStatus, out: String(decoding: outData, as: UTF8.self), err: String(decoding: errData, as: UTF8.self))
    }
}
