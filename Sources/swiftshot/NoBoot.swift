// No-boot rendering (the default): iOS and watchOS previews without any simulator.
//
// The app is a simulator binary, but it runs fine as a plain process on the Mac when it gets the
// environment a booted device's launchd would give it (runtime root, a home directory, device
// variables). What a booted device adds for rendering — Metal, IOSurface and the shader compiler
// service — swiftshot-simhost provides (Agent/SimHost.m, Agent/NoBoot.c), and the agent captures
// with Core Animation's own renderer (same engine as the render server, Liquid Glass included).
// No CoreSimulator device is created or booted, and one process renders every device of a runtime
// (each device gets its own screen scale), so a whole language costs one app launch (~1 s).

import Foundation

extension Runner {
    static func locateHelper(_ file: String) throws -> String {
        let agent = URL(fileURLWithPath: try locateAgent(.ios))
        let path = agent.deletingLastPathComponent().appendingPathComponent(file).path
        guard FileManager.default.fileExists(atPath: path) else { throw CLIError("\(file) not found next to \(agent.lastPathComponent). Run `make`.") }
        return path
    }

    func runNoBoot(_ target: Target, hosts: [Host]) async throws {
        let simhost = try Runner.locateHelper("swiftshot-simhost")
        let shim = try Runner.locateHelper(target.platform == .ios ? "SwiftshotNoBoot.dylib" : "SwiftshotNoBoot-watchOS.dylib")
        let agent = try Runner.locateAgent(target.platform)
        let executable = try appExecutable(target.app.path)
        let allTextSizes = (options.textSizes + options.screens.flatMap { $0.textSizes ?? [] })
            .reduce(into: [String]()) { list, s in if !list.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) { list.append(s) } }
        var dyldCaches: [String: String] = [:]
        for runtime in target.runtimes { dyldCaches[runtime.identifier] = try await dyldCache(for: runtime) }
        // Each language is one short-lived process; run a few side by side.
        let limiter = AsyncLimiter(limit: max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for runtime in target.runtimes {
                let runtimeHosts = hosts.filter { $0.runtime.identifier == runtime.identifier }
                guard let host = runtimeHosts.first, let bundle = runtime.bundlePath else { continue }
                let root = (bundle as NSString).appendingPathComponent("Contents/Resources/RuntimeRoot")
                // One process per default text size (watch models differ: 46 mm XL, 42 mm L…)
                // unless --content-size pins it for all.
                // Watches: one process per model; MobileGestalt answers (screen class, pitch) are
                // per process and watchOS lays out by them.
                // Watch text sizes: one process each, launched at that size (list cells follow the
                // app-wide setting); iOS renders all sizes in one process via trait overrides.
                var groups: [(String, SimDeviceType, [DeviceProfile], String?)] = []
                if target.platform == .watchos {
                    for h in runtimeHosts { for p in h.profiles {
                        let type = target.types.first { $0.name == p.name } ?? h.type
                        let base = options.contentSize == nil ? p.contentSizeCategory ?? "" : ""
                        for size in allTextSizes {
                            groups.append((contentSizeCategory(size) ?? base, type, [p], size))
                        }
                    } }
                } else {
                    let byCategory = Dictionary(grouping: runtimeHosts.flatMap(\.profiles)) { options.contentSize == nil ? $0.contentSizeCategory ?? "" : "" }
                    for (category, profiles) in byCategory.sorted(by: { $0.key < $1.key }) { groups.append((category, host.type, profiles, nil)) }
                }
                for (category, type, profiles, textSize) in groups {
                for language in options.languages {
                    group.addTask {
                        try await limiter.run {
                            let t = Date()
                            var job = self.makeJob(mode: .virtual, language: language, runtime: runtime, devices: profiles, target: target)
                            job.processTextSize = textSize
                            do {
                                let result = try await self.launchNoBoot(job, tag: "noboot-\(runtime.version)-\(language)-\(type.name)\(category.isEmpty ? "" : "-" + category)-\(textSize ?? "all")", simhost: simhost,
                                                                         insert: "\(shim):\(agent)", root: root, dyldCache: dyldCaches[runtime.identifier] ?? nil, runtime: runtime,
                                                                         type: type, profile: profiles[0], executable: executable,
                                                                         contentSize: category.isEmpty ? nil : category)
                                self.collect(result)
                                self.record("render \(runtime.name) \(language) (no boot)", t)
                                Log.success("\(runtime.name) · \(language) · \(profiles.count) devices, no simulator: \(result.shots.count) shots in \(ms(since: t)) (in-app \(Int(result.totalMs)) ms)")
                            } catch {
                                self.lock.lock(); self.errors.append("\(runtime.name) · \(language) (no boot): \(error)"); self.lock.unlock()
                            }
                        }
                    }
                }
                }
            }
            try await group.waitForAll()
        }
    }

    /// Watches have no host grouping: every supported model of a runtime is one device of the job.
    func noBootWatchHosts(_ target: Target) async throws -> [Host] {
        let cache = DeviceCatalog.loadCache()
        var hosts: [Host] = []
        for runtime in target.runtimes {
            let info = try await runtimeInfo(runtime)
            let types = target.types.filter { supports(info, $0) }
            let profiles = types.compactMap { DeviceCatalog.profile(for: $0, runtime: runtime.version, cache: cache)?.0 }
            if let first = types.first, !profiles.isEmpty { hosts.append(Host(target: target, runtime: runtime, type: first, profiles: profiles)) }
        }
        return hosts
    }

    func appExecutable(_ app: String) throws -> String {
        let info = URL(fileURLWithPath: app).appendingPathComponent("Info.plist")
        guard let plist = NSDictionary(contentsOf: info), let name = plist["CFBundleExecutable"] as? String else {
            throw CLIError("Cannot read CFBundleExecutable from \(info.path)")
        }
        return (app as NSString).appendingPathComponent(name)
    }

    /// Runtimes that don't ship a dyld shared cache run from one CoreSimulator builds on the host
    /// (per host OS build). Without it the runtime's libraries load one by one and e.g. its shader
    /// compiler crashes. Builds the cache once if it is missing (as a first boot would).
    func dyldCache(for runtime: SimRuntime) async throws -> String? {
        guard let bundle = runtime.bundlePath else { return nil }
        let ownCache = (bundle as NSString).appendingPathComponent("Contents/Resources/RuntimeRoot/System/Library/Caches/com.apple.dyld")
        if FileManager.default.fileExists(atPath: ownCache) { return nil }
        let hostBuild = try await sh(["sw_vers", "-buildVersion"], stdoutOnly: true).trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = "/Library/Developer/CoreSimulator/Caches/dyld/\(hostBuild)/\(runtime.identifier).\(runtime.buildversion ?? runtime.version)/"
        if !FileManager.default.fileExists(atPath: dir) {
            let t = Date()
            Log.info("Building the dyld shared cache for \(runtime.name) (one-time per runtime and macOS build)…")
            try await sh(Simctl.cmd(["runtime", "dyld_shared_cache", "update", runtime.identifier]))
            Log.info("dyld shared cache ready in \(ms(since: t))")
        }
        return FileManager.default.fileExists(atPath: dir) ? dir : nil
    }

    func launchNoBoot(_ job: Job, tag: String, simhost: String, insert: String, root: String, dyldCache: String?, runtime: SimRuntime,
                      type: SimDeviceType, profile: DeviceProfile, executable: String, contentSize deviceDefault: String? = nil) async throws -> JobResult {
        var job = job
        let base = (workDir as NSString).appendingPathComponent("noboot/\(tag)")
        let home = (base as NSString).appendingPathComponent("home")
        try? FileManager.default.removeItem(atPath: base)
        try FileManager.default.createDirectory(atPath: (home as NSString).appendingPathComponent("tmp"), withIntermediateDirectories: true)
        job.resultPath = (base as NSString).appendingPathComponent("result.json")
        let jobPath = try writeJob(job, tag: tag)

        // What launchd_sim would put into the environment of a process on a booted device
        // (DYLD_* are set by swiftshot-simhost: SIP strips them on the way through /usr/bin/env).
        var env: [String: String] = [
            "SIMULATOR_ROOT": root, "IPHONE_SIMULATOR_ROOT": root,
            "HOME": home, "CFFIXED_USER_HOME": home, "TMPDIR": home + "/tmp/",
            "SIMULATOR_SHARED_RESOURCES_DIRECTORY": home, "IPHONE_SHARED_RESOURCES_DIRECTORY": home,
            "SIMULATOR_RUNTIME_VERSION": runtime.version, "SIMULATOR_RUNTIME_BUILD_VERSION": runtime.buildversion ?? "",
            "SIMULATOR_MODEL_IDENTIFIER": type.modelIdentifier ?? "", "SIMULATOR_DEVICE_NAME": "swiftshot no-boot",
            "SIMULATOR_UDID": "00000000-0000-0000-0000-000000000000",
            "SIMULATOR_CAPABILITIES": (type.bundlePath as NSString).appendingPathComponent("Contents/Resources/capabilities.plist"),
            "SIMULATOR_MAINSCREEN_WIDTH": "\(Int(profile.width * profile.scale))", "SIMULATOR_MAINSCREEN_HEIGHT": "\(Int(profile.height * profile.scale))",
            "SIMULATOR_MAINSCREEN_SCALE": String(format: "%.6f", profile.scale),
            "SIMULATOR_MAINSCREEN_PITCH": String(format: "%.6f", DeviceCatalog.screen(of: type)?.pitch ?? 0),
            "SIMULATOR_HOST_HOME": NSHomeDirectory(), "SIMULATOR_ARCHS": "arm64",
            "SWIFTSHOT_NOBOOT": "1", "SWIFTSHOT_JOB": jobPath,
            "SWIFTSHOT_NOBOOT_SHIM": (insert as NSString).components(separatedBy: ":")[0], "SWIFTSHOT_NOBOOT_INSERT": insert,
        ]
        if let dyldCache { env["SWIFTSHOT_NOBOOT_DYLD_CACHE"] = dyldCache }
        // Debugging: the app's os_log (UIKit warnings…) on stderr, shown with --verbose.
        let osLog = ProcessInfo.processInfo.environment["SWIFTSHOT_OSLOG"] != nil
        if osLog { env["OS_ACTIVITY_DT_MODE"] = "1" }
        // iOS: Dynamic Type pinned to the system default (L); watch models keep their own defaults.
        let contentSize = job.processTextSize.flatMap(contentSizeCategory) ?? options.contentSize.flatMap(contentSizeCategory) ?? deviceDefault ?? (job.platform == "ios" ? "UICTContentSizeCategoryL" : nil)
        let args = [simhost, root, executable, "-AppleLanguages", "(\(job.language))", "-AppleLocale", localeIdentifier(for: job.language)]
            + (contentSize.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        let output = try await sh(args, env: env, timeout: options.timeout, onLine: { line in if osLog || line.hasPrefix("[swiftshot]") { Log.debug(line) } })
        guard let resultPath = job.resultPath, FileManager.default.fileExists(atPath: resultPath) else {
            throw CLIError("Agent did not report a result for \(tag). Output:\n\(output.suffix(3000))")
        }
        return try JSONDecoder().decode(JobResult.self, from: Data(contentsOf: URL(fileURLWithPath: resultPath)))
    }
}
