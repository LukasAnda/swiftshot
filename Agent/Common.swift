import Foundation

func log(_ message: String) {
    let line = ("[swiftshot] " + message + "\n").data(using: .utf8)!
    FileHandle.standardError.write(line)
    // Booted apps' stderr isn't always visible to the host; $SWIFTSHOT_LOG_FILE collects it too.
    if let path = ProcessInfo.processInfo.environment["SWIFTSHOT_LOG_FILE"] {
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        if let handle = FileHandle(forWritingAtPath: path) { handle.seekToEndOfFile(); handle.write(line); handle.closeFile() }
    }
}

func now() -> Double { CFAbsoluteTimeGetCurrent() }

/// Booted simulator: its render server (backboardd) is given renderer settings the CLI gives the
/// no-boot server as env variables (NoBoot.swift), through the server's debug-option interface
/// (env variables are read only at the server's launch). They change only how the server gets to
/// the pixels, so that its frames stop depending on timing; they stay set in the booted
/// simulator's server until it restarts.
func pinServerRendering(_ names: Set<String>) {
    typealias OptionName = @convention(c) (Int32) -> UnsafePointer<CChar>?
    typealias SetOption = @convention(c) (UInt32, Int32, Bool) -> Void
    let handle = UnsafeMutableRawPointer(bitPattern: -2)
    guard let nameSym = dlsym(handle, "CAGetDebugOptionEnvVariableName"), let setSym = dlsym(handle, "CARenderServerSetDebugOption") else {
        log("render server debug options not found"); return
    }
    let name = unsafeBitCast(nameSym, to: OptionName.self), set = unsafeBitCast(setSym, to: SetOption.self)
    // Numbered by an enum that changes between releases (names end with a nil): look them up.
    var wanted = names
    var option: Int32 = 0
    while !wanted.isEmpty, let n = name(option).map({ String(cString: $0) }) {
        if wanted.remove(n) != nil { set(0, option, true) }   // port 0: the default render server
        option += 1
    }
    if !wanted.isEmpty { log("render server options not found: \(wanted.sorted())") }
}

/// Collects results from the background PNG/JPEG writers.
final class WriteSink: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var shots: [ShotRecord] = []
    private(set) var errors: [String] = []
    private(set) var shotErrors: [ShotError] = []
    func add(shot: ShotRecord) { lock.lock(); shots.append(shot); lock.unlock() }
    func add(error: String) { lock.lock(); errors.append(error); lock.unlock() }
    func add(error: ShotError) { lock.lock(); shotErrors.append(error); lock.unlock() }
}

extension Job {
    func fileName(preview: String, device: String, appearance: String, textSize: String = "default") -> String {
        let clean: (String) -> String = { $0.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
        var name = fileNamePattern
            .replacingOccurrences(of: "{device}", with: clean(device))
            .replacingOccurrences(of: "{preview}", with: clean(preview))
            .replacingOccurrences(of: "{appearance}", with: platform == "watchos" || appearance.isEmpty || (appearance == "light" && appearances.count == 1) ? "" : "-\(appearance)")
            .replacingOccurrences(of: "{textSize}", with: contentSizeCategory(textSize) == nil ? "" : "-\(textSize)")
            .replacingOccurrences(of: "{language}", with: language)
            .replacingOccurrences(of: "{runtime}", with: runtime)
        if includeRuntimeInName && !fileNamePattern.contains("{runtime}") { name += "-\(platform == "watchos" ? "watchOS" : "iOS")\(runtime)" }
        return name + (format == "jpeg" ? ".jpg" : ".png")
    }

    /// The report id of a screenshot file this job writes (`file` without the language folder).
    func shotId(_ file: String) -> String { "\(language)/" + (file as NSString).deletingPathExtension }

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

@_silgen_name("swiftshot_flip_layer_drawing") func swiftshot_flip_layer_drawing()
@_silgen_name("swiftshot_install_corner_insets") func swiftshot_install_corner_insets()
@_silgen_name("swiftshot_set_corner_insets") func swiftshot_set_corner_insets(_ values: UnsafePointer<Double>?)
