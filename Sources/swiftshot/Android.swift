import Foundation

/// Android projects are rendered by the JVM renderer (`swiftshot-android`, next to this binary):
/// a Gradle project with no Xcode project, or `--platform android`, hands over all arguments.
enum Android {
    static func handOffIfNeeded(_ args: [String]) {
        var args = args
        var platform: String?
        if let i = args.firstIndex(of: "--platform"), i + 1 < args.count {
            platform = args[i + 1]; args.removeSubrange(i...(i + 1))
        }
        if platform == "ios" { return }
        guard platform == "android" || isAndroidProject(args) else { return }
        let dir = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().deletingLastPathComponent()
        let launcher = dir.appendingPathComponent("swiftshot-android").path
        guard FileManager.default.isExecutableFile(atPath: launcher) else {
            FileHandle.standardError.write("\u{001B}[31merror:\u{001B}[0m swiftshot-android not found next to \(dir.path)\n".data(using: .utf8)!)
            exit(1)
        }
        let argv = [launcher] + args
        var cargs = argv.map { strdup($0) } + [nil]
        execv(launcher, &cargs)
        perror("execv"); exit(1)
    }

    /// The project folder has `gradlew` and a Gradle settings file, and no Xcode project or a
    /// config that names one.
    static func isAndroidProject(_ args: [String]) -> Bool {
        var dir = FileManager.default.currentDirectoryPath
        if let i = args.firstIndex(of: "--project-dir"), i + 1 < args.count { dir = args[i + 1] }
        if args.contains("--project") || args.contains("--workspace") || args.contains("--app") { return false }
        let fm = FileManager.default
        func has(_ name: String) -> Bool { fm.fileExists(atPath: (dir as NSString).appendingPathComponent(name)) }
        guard has("gradlew"), has("settings.gradle.kts") || has("settings.gradle") else { return false }
        let items = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        if items.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) { return false }
        if let data = fm.contents(atPath: (dir as NSString).appendingPathComponent("swiftshot.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["scheme"] != nil || json["project"] != nil || json["workspace"] != nil { return false }
        return true
    }
}
