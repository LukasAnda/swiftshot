import Foundation

func log(_ message: String) {
    FileHandle.standardError.write(("[swiftshot] " + message + "\n").data(using: .utf8)!)
}

func now() -> Double { CFAbsoluteTimeGetCurrent() }

/// Collects results from the background PNG/JPEG writers.
final class WriteSink: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var shots: [ShotRecord] = []
    private(set) var errors: [String] = []
    func add(shot: ShotRecord) { lock.lock(); shots.append(shot); lock.unlock() }
    func add(error: String) { lock.lock(); errors.append(error); lock.unlock() }
}

extension Job {
    func fileName(preview: String, device: String, appearance: String) -> String {
        let clean: (String) -> String = { $0.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
        var name = fileNamePattern
            .replacingOccurrences(of: "{device}", with: clean(device))
            .replacingOccurrences(of: "{preview}", with: clean(preview))
            .replacingOccurrences(of: "{appearance}", with: platform == "watchos" || appearance.isEmpty || (appearance == "light" && appearances.count == 1) ? "" : "-\(appearance)")
            .replacingOccurrences(of: "{language}", with: language)
            .replacingOccurrences(of: "{runtime}", with: runtime)
        if includeRuntimeInName && !fileNamePattern.contains("{runtime}") { name += "-\(platform == "watchos" ? "watchOS" : "iOS")\(runtime)" }
        return name + (format == "jpeg" ? ".jpg" : ".png")
    }

    func writeResult(_ result: JobResult) {
        let url = resultPath.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: outputDir).appendingPathComponent(".swiftshot/result-\(runtime)-\(language)-\(ProcessInfo.processInfo.processIdentifier).json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(result).write(to: url)
        log("done: \(result.shots.count) shots, \(result.errors.count) errors in \(Int(result.totalMs)) ms")
        print("SWIFTSHOT_RESULT \(url.path)")
        fflush(stdout)
    }
}
