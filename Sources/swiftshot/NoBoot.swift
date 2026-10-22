// --no-boot (experimental): render iOS previews without any simulator.
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
        let shim = try Runner.locateHelper("SwiftshotNoBoot.dylib")
        let agent = try Runner.locateAgent(.ios)
        let executable = try appExecutable(target.app.path)
        // Each language is one short-lived process; run a few side by side.
        let limiter = AsyncLimiter(limit: max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for runtime in target.runtimes {
                let runtimeHosts = hosts.filter { $0.runtime.identifier == runtime.identifier }
                guard let host = runtimeHosts.first, let bundle = runtime.bundlePath else { continue }
                let profiles = runtimeHosts.flatMap(\.profiles)
                let root = (bundle as NSString).appendingPathComponent("Contents/Resources/RuntimeRoot")
                for language in options.languages {
                    group.addTask {
                        try await limiter.run {
                            let t = Date()
                            let job = self.makeJob(mode: .virtual, language: language, runtime: runtime, devices: profiles, target: target)
                            do {
                                let result = try await self.launchNoBoot(job, tag: "noboot-\(runtime.version)-\(language)", simhost: simhost,
                                                                         insert: "\(shim):\(agent)", root: root, runtime: runtime,
                                                                         type: host.type, profile: profiles[0], executable: executable)
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
            try await group.waitForAll()
        }
    }

    func appExecutable(_ app: String) throws -> String {
        let info = URL(fileURLWithPath: app).appendingPathComponent("Info.plist")
        guard let plist = NSDictionary(contentsOf: info), let name = plist["CFBundleExecutable"] as? String else {
            throw CLIError("Cannot read CFBundleExecutable from \(info.path)")
        }
        return (app as NSString).appendingPathComponent(name)
    }

    func launchNoBoot(_ job: Job, tag: String, simhost: String, insert: String, root: String, runtime: SimRuntime,
                      type: SimDeviceType, profile: DeviceProfile, executable: String) async throws -> JobResult {
        var job = job
        let base = (workDir as NSString).appendingPathComponent("noboot/\(tag)")
        let home = (base as NSString).appendingPathComponent("home")
        try? FileManager.default.removeItem(atPath: base)
        try FileManager.default.createDirectory(atPath: (home as NSString).appendingPathComponent("tmp"), withIntermediateDirectories: true)
        job.resultPath = (base as NSString).appendingPathComponent("result.json")
        let jobPath = try writeJob(job, tag: tag)

        // What launchd_sim would put into the environment of a process on a booted device
        // (DYLD_* are set by swiftshot-simhost: SIP strips them on the way through /usr/bin/env).
        let env: [String: String] = [
            "SIMULATOR_ROOT": root, "IPHONE_SIMULATOR_ROOT": root,
            "HOME": home, "CFFIXED_USER_HOME": home, "TMPDIR": home + "/tmp/",
            "SIMULATOR_SHARED_RESOURCES_DIRECTORY": home, "IPHONE_SHARED_RESOURCES_DIRECTORY": home,
            "SIMULATOR_RUNTIME_VERSION": runtime.version, "SIMULATOR_RUNTIME_BUILD_VERSION": runtime.buildversion ?? "",
            "SIMULATOR_MODEL_IDENTIFIER": type.modelIdentifier ?? "", "SIMULATOR_DEVICE_NAME": "swiftshot no-boot",
            "SIMULATOR_UDID": "00000000-0000-0000-0000-000000000000",
            "SIMULATOR_CAPABILITIES": (type.bundlePath as NSString).appendingPathComponent("Contents/Resources/capabilities.plist"),
            "SIMULATOR_MAINSCREEN_WIDTH": "\(Int(profile.width * profile.scale))", "SIMULATOR_MAINSCREEN_HEIGHT": "\(Int(profile.height * profile.scale))",
            "SIMULATOR_MAINSCREEN_SCALE": String(format: "%.6f", profile.scale),
            "SIMULATOR_HOST_HOME": NSHomeDirectory(), "SIMULATOR_ARCHS": "arm64",
            "SWIFTSHOT_NOBOOT": "1", "SWIFTSHOT_JOB": jobPath,
            "SWIFTSHOT_NOBOOT_SHIM": (insert as NSString).components(separatedBy: ":")[0], "SWIFTSHOT_NOBOOT_INSERT": insert,
        ]
        let contentSize = options.contentSize.map(contentSizeCategory) ?? "UICTContentSizeCategoryL"
        let args = [simhost, root, executable, "-AppleLanguages", "(\(job.language))", "-AppleLocale", localeIdentifier(for: job.language),
                    "-UIPreferredContentSizeCategoryName", contentSize]
        let output = try await sh(args, env: env, timeout: options.timeout, onLine: { line in if line.hasPrefix("[swiftshot]") { Log.debug(line) } })
        guard let resultPath = job.resultPath, FileManager.default.fileExists(atPath: resultPath) else {
            throw CLIError("Agent did not report a result for \(tag). Output:\n\(output.suffix(3000))")
        }
        return try JSONDecoder().decode(JobResult.self, from: Data(contentsOf: URL(fileURLWithPath: resultPath)))
    }
}
