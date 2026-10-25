// Orchestration.
//
// virtual mode (default)
//   For every requested iOS runtime and device idiom (phone/pad) exactly ONE simulator is
//   booted. The app is launched once per language with the agent injected; inside that single
//   process the agent renders every preview × device × appearance off-screen at the device's
//   exact point size, scale, safe area and size classes. So the number of app launches is
//   runtimes × idioms × languages — independent of the number of devices or previews.
//
// device mode
//   One simulator per device × runtime; the agent puts each preview on the real screen and the
//   host grabs the framebuffer with `simctl io screenshot` (real status bar, 9:41).

import Foundation

struct RuntimeInfo: Decodable {
    struct SupportedType: Decodable { let identifier: String; let name: String; let productFamily: String? }
    let identifier: String
    let version: String
    let supportedDeviceTypes: [SupportedType]?
}

final class Runner {
    let options: Options
    /// Everything needed to render one platform (iOS or watchOS).
    struct Target {
        let platform: Platform
        var app: BuiltApp
        let runtimes: [SimRuntime]
        let types: [SimDeviceType]
        var includeRuntimeInName: Bool { runtimes.count > 1 }
    }
    var shots: [ShotRecord] = []
    var errors: [String] = []
    var skipped: [String] = []
    var warned = Set<String>()
    var timings: [(String, Double)] = []
    let lock = NSLock()
    /// Boots started early (while xcodebuild runs), keyed by simulator name.
    var bootTasks: [String: Task<SimDevice, Error>] = [:]

    init(options: Options) throws {
        self.options = options
        if options.command != "emit-table" { _ = try Runner.locateAgent(.ios) }   // emit-table only merges files
        if let set = options.deviceSet {
            let path = URL(fileURLWithPath: set).standardizedFileURL.path
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            // Keep Spotlight out of the simulators' data containers (tens of thousands of files).
            FileManager.default.createFile(atPath: (path as NSString).appendingPathComponent(".metadata_never_index"), contents: nil)
            Simctl.deviceSet = path
        }
        TemplateStore.enabled = options.templates
        if let dir = options.templateCache {
            TemplateStore.root = URL(fileURLWithPath: dir).standardizedFileURL.path
            TemplateStore.persistent = true
        }
    }

    static func locateAgent(_ platform: Platform) throws -> String {
        let envKey = platform == .ios ? "SWIFTSHOT_AGENT" : "SWIFTSHOT_WATCH_AGENT"
        if let env = ProcessInfo.processInfo.environment[envKey] { return env }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let dir = exe.deletingLastPathComponent()
        let candidates = [
            dir.appendingPathComponent(platform.agentFile),
            dir.appendingPathComponent("../lib/swiftshot/\(platform.agentFile)"),
            dir.appendingPathComponent("../../bin/\(platform.agentFile)"),
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c.path) { return c.standardizedFileURL.path }
        throw CLIError("\(platform.agentFile) not found next to the swiftshot binary. Run `make` or set \(envKey).")
    }

    var outputDir: String { URL(fileURLWithPath: options.output).standardizedFileURL.path }
    var workDir: String { (outputDir as NSString).appendingPathComponent(".swiftshot") }

    func record(_ name: String, _ start: Date) {
        lock.lock(); timings.append((name, Date().timeIntervalSince(start))); lock.unlock()
    }

    // MARK: Resolution

    func resolveRuntimes(_ platform: Platform = .ios) async throws -> [SimRuntime] {
        let versions = platform == .ios ? options.iosVersions : options.watchosVersions
        var installed = try await Simctl.runtimes(platform: platform).sorted { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
        guard !installed.isEmpty || options.downloadRuntimes else {
            throw CLIError("No \(platform.runtimeName) simulator runtime installed. Install one with `xcodebuild -downloadPlatform \(platform.runtimeName)` or pass --download-missing-runtimes.")
        }
        if versions.isEmpty {
            if installed.isEmpty { try await download(nil, platform); installed = try await Simctl.runtimes(platform: platform) }
            // Newest runtime that can boot the most requested devices: a beta runtime may only
            // know a few device types (iOS 27.1 here: iPhone Duo only).
            let types = try await resolveDeviceTypes()
            var best = installed.last!, bestCount = -1
            for runtime in installed {
                let info = try await runtimeInfo(runtime)
                let count = types.filter { supports(info, $0) }.count
                if count >= bestCount { best = runtime; bestCount = count }
            }
            if best.identifier != installed.last!.identifier {
                Log.info("Using \(platform.runtimeName) \(best.version): the newest installed (\(installed.last!.version)) does not support all requested devices")
            }
            return [best]
        }
        var result: [SimRuntime] = []
        for wanted in versions {
            func match() -> SimRuntime? {
                installed.last { $0.version == wanted || $0.version.hasPrefix(wanted + ".") }
            }
            if let r = match() { result.append(r); continue }
            guard options.downloadRuntimes else {
                throw CLIError("\(platform.runtimeName) \(wanted) runtime is not installed (installed: \(installed.map(\.version).joined(separator: ", "))). Pass --download-missing-runtimes to fetch it.")
            }
            try await download(wanted, platform)
            installed = try await Simctl.runtimes(platform: platform)
            guard let r = match() else { throw CLIError("\(platform.runtimeName) \(wanted) still not available after download") }
            result.append(r)
        }
        return result
    }

    func download(_ version: String?, _ platform: Platform) async throws {
        Log.info("Downloading \(platform.runtimeName) \(version ?? "latest") simulator runtime (one-time, cache it on CI)…")
        var args = ["xcrun", "xcodebuild", "-downloadPlatform", platform.runtimeName, "-architectureVariant", "arm64"]
        if let version { args += ["-buildVersion", version] }
        try await sh(args)
    }

    func resolveDeviceTypes() async throws -> [SimDeviceType] {
        let all = try await Simctl.deviceTypes()
        return try options.devices.map { name in
            guard let t = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
                    ?? all.first(where: { $0.identifier.hasSuffix(name) }) else {
                let suggestions = all.map(\.name).filter { $0.localizedCaseInsensitiveContains(name.split(separator: " ").first.map(String.init) ?? name) }
                throw CLIError("Unknown device '\(name)'. Did you mean: \(suggestions.prefix(8).joined(separator: ", "))")
            }
            return t
        }
    }

    func runtimeInfo(_ runtime: SimRuntime) async throws -> RuntimeInfo? {
        struct R: Decodable { let runtimes: [RuntimeInfo] }
        let out = try await sh(Simctl.cmd(["list", "runtimes", "-j"]), stdoutOnly: true)
        return try JSONDecoder().decode(R.self, from: Data(out.utf8)).runtimes.first { $0.identifier == runtime.identifier }
    }

    func supports(_ info: RuntimeInfo?, _ type: SimDeviceType) -> Bool {
        info?.supportedDeviceTypes?.contains { $0.identifier == type.identifier } ?? true
    }

    // MARK: Job helpers

    func makeJob(mode: JobMode, language: String, runtime: SimRuntime, devices: [DeviceProfile], controlDir: String? = nil,
                 target: Target? = nil) -> Job {
        let statusBar = Simctl.statusBarLocales(runtime)
        return Job(mode: mode, outputDir: outputDir, language: language, runtime: runtime.version, devices: devices,
            appearances: options.appearances, previewFilter: options.previews, format: options.format,
            settleFrames: options.settleFrames, settleDelay: options.delay, controlDir: controlDir,
            fileNamePattern: "{device}-{preview}{appearance}{textSize}", includeRuntimeInName: target?.includeRuntimeInName ?? false,
            screenRules: options.screens, targetPlatform: (target?.platform ?? .ios).rawValue, textSizes: options.textSizes,
            fullLength: options.fullLength, statusBar: options.statusBar,
            statusBarLocale: statusBar.clock, statusBarLanguage: statusBar.language, statusBarTimeZone: TimeZone.current.identifier)
    }

    func writeJob(_ job: Job, tag: String) throws -> String {
        let dir = (workDir as NSString).appendingPathComponent("jobs")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("\(tag).json")
        try JSONEncoder().encode(job).write(to: URL(fileURLWithPath: path))
        return path
    }

    func launch(_ job: Job, tag: String, udid: String, app: BuiltApp, extraEnv: [String: String] = [:]) async throws -> JobResult {
        var job = job
        let resultPath = (workDir as NSString).appendingPathComponent("results/\(tag)-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(atPath: (resultPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        job.resultPath = resultPath
        let jobPath = try writeJob(job, tag: tag)
        let platform = Platform(rawValue: job.platform) ?? .ios
        let agent = try Runner.locateAgent(platform)
        // iOS: pin Dynamic Type to the system default (L) so every run is identical. watchOS models
        // have different default sizes, so leave them alone unless explicitly requested.
        let contentSize = options.contentSize.flatMap(contentSizeCategory) ?? (platform == .ios ? "UICTContentSizeCategoryL" : nil)
        // Freshly (first-)booted simulators sometimes refuse the first launch ("did not return a
        // process handle"); that is transient, so retry a couple of times before failing.
        var output = ""
        for attempt in 1...3 {
            // A retry starts the screenshot handshake over: requests and acks a failed attempt
            // left behind would let the relaunched app skip its screenshots.
            if let control = job.controlDir, let stale = try? FileManager.default.contentsOfDirectory(atPath: control) {
                for file in stale { try? FileManager.default.removeItem(atPath: (control as NSString).appendingPathComponent(file)) }
            }
            do {
                output = try await Simctl.launchWithAgent(udid, bundleID: app.bundleID, agent: agent, job: jobPath,
                                                          language: job.language, locale: localeIdentifier(for: job.language), contentSize: contentSize,
                                                          extraEnv: extraEnv, timeout: options.timeout)
                break
            } catch let error as ShellError where attempt < 3 && error.output.contains("failed to launch") {
                Log.warn("\(tag): launch failed (attempt \(attempt)), retrying…")
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 3_000_000_000)
            }
        }
        let stdoutPath = output.split(separator: "\n").last(where: { $0.hasPrefix("SWIFTSHOT_RESULT ") })
            .map { String($0.dropFirst("SWIFTSHOT_RESULT ".count)) }
        guard let path = FileManager.default.fileExists(atPath: resultPath) ? resultPath : stdoutPath else {
            throw CLIError("Agent did not report a result for \(tag). App output:\n\(output.suffix(3000))")
        }
        let result = try JSONDecoder().decode(JobResult.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try? FileManager.default.removeItem(atPath: path)
        if result.previews.isEmpty && job.mode != .calibrate {
            throw CLIError(options.previews.isEmpty
                ? "No SwiftUI previews found in \(app.path). #Preview code is only compiled into Debug builds — use --configuration Debug (the default)."
                : "No preview matches --previews \(options.previews.joined(separator: ",")).")
        }
        return result
    }

    func collect(_ result: JobResult) {
        lock.lock(); shots += result.shots; errors += result.errors; lock.unlock()
    }

    // MARK: Commands

    func run() async throws {
        let total = Date()
        if options.clearOutput, FileManager.default.fileExists(atPath: outputDir) {
            for lang in options.languages { try? FileManager.default.removeItem(atPath: (outputDir as NSString).appendingPathComponent(lang)) }
        }
        let allTypes = try await resolveDeviceTypes()
        // Plan first and boot every simulator the run needs right away: booting (seconds to a
        // minute when cold) then overlaps with xcodebuild instead of following it.
        var targets: [Target] = []
        var plannedHosts: [Platform: [Host]] = [:]
        let placeholder = BuiltApp(path: "", bundleID: "")
        var plannedBy: [Platform: [(SimDeviceType, SimRuntime, String)]] = [:]
        for platform in [Platform.ios, .watchos] {
            var planned: [(SimDeviceType, SimRuntime, String)] = []
            defer { plannedBy[platform] = planned }
            let types = allTypes.filter { Platform.of($0) == platform }
            if types.isEmpty { continue }
            let runtimes = try await resolveRuntimes(platform)
            let target = Target(platform: platform, app: placeholder, runtimes: runtimes, types: types)
            targets.append(target)
            Log.info("\(platform.runtimeName) matrix: \(types.count) device(s) × \(runtimes.count) \(platform.runtimeName) (\(runtimes.map(\.version).joined(separator: ", "))) × \(options.languages.count) language(s) × \(options.appearances.count) appearance(s), mode: \(options.mode.rawValue)")
            if options.mode == .device || platform == .watchos {
                for runtime in runtimes {
                    let info = try await runtimeInfo(runtime)
                    for type in types where supports(info, type) { planned.append((type, runtime, "")) }
                }
            } else {
                let hosts = try await planHosts(target)
                plannedHosts[platform] = hosts
                for host in hosts {
                    for lane in 0..<min(options.parallelLanguages, options.languages.count) {
                        planned.append((host.type, host.runtime, lane == 0 ? "" : " #\(lane + 1)"))
                    }
                }
            }
        }
        // Scheduling experiments for small CI machines (3-core / 7 GB VMs), see bench/:
        // SWIFTSHOT_BOOT_AFTER_BUILD=1 boots only once the apps are built (no CPU contention with
        // xcodebuild); SWIFTSHOT_STAGED=1 handles one platform at a time (fewer simulators alive).
        let env = ProcessInfo.processInfo.environment
        let bootAfterBuild = env["SWIFTSHOT_BOOT_AFTER_BUILD"] == "1", staged = env["SWIFTSHOT_STAGED"] == "1"
        // No-boot (the default) renders without any simulator: nothing to boot.
        let noBoot = options.noBoot && options.mode == .virtual
        if noBoot { plannedBy[.ios] = []; plannedBy[.watchos] = [] }
        if !bootAfterBuild {
            for (index, target) in targets.enumerated() where !staged || index == 0 {
                try await startBoots(plannedBy[target.platform] ?? [])
            }
        }
        // Builds run one after another (they share DerivedData), but each platform starts
        // rendering as soon as its own app is built.
        var builds: [Task<BuiltApp, Error>] = []
        for target in targets {
            let previous = builds.last
            builds.append(Task {
                _ = try? await previous?.value
                let buildStart = Date()
                let app = try await Builder.build(self.options, platform: target.platform)
                self.record("build \(target.platform.runtimeName)", buildStart)
                return app
            })
        }
        if bootAfterBuild && !staged {
            for build in builds { _ = try await build.value }
            for target in targets { try await startBoots(plannedBy[target.platform] ?? []) }
        }

        let renderStart = Date()
        let render: @Sendable (Int, Target) async throws -> Void = { index, unbuilt in
            var target = unbuilt
            target.app = try await builds[index].value
            if staged && (bootAfterBuild || index > 0) { try await self.startBoots(plannedBy[target.platform] ?? []) }
            // Watch previews are always captured from the real watch screen (one simulator per
            // watch model); iOS uses virtual devices unless --mode device is requested.
            if noBoot && target.platform == .watchos {
                try await self.runNoBoot(target, hosts: try await self.noBootWatchHosts(target))
            } else if self.options.mode == .device || target.platform == .watchos {
                try await self.runDevice(target)
            } else {
                let hosts = (plannedHosts[target.platform] ?? []).map {
                    Host(target: target, runtime: $0.runtime, type: $0.type, profiles: $0.profiles)
                }
                if noBoot { try await self.runNoBoot(target, hosts: hosts) } else { try await self.runVirtual(target, hosts: hosts) }
            }
        }
        if staged {
            for (index, target) in targets.enumerated() { try await render(index, target) }
        } else {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, target) in targets.enumerated() { group.addTask { try await render(index, target) } }
                try await group.waitForAll()
            }
        }
        record("render (all simulators)", renderStart)

        try Report.write(shots: shots, errors: errors, to: outputDir, html: options.html, timings: timings,
                         total: Date().timeIntervalSince(total))
        for s in skipped { Log.warn("Skipped: " + s) }
        for e in errors { Log.warn(e) }
        if shots.isEmpty && errors.isEmpty { Log.warn("No screenshots: no preview matched the filters (previews, screens, devices)") }
        let summary = "\(shots.count) screenshots in \(ms(since: total)) → \(outputDir)"
        if errors.isEmpty { Log.success(summary) } else { Log.failure(summary + " (\(errors.count) failed, see above)") }
        if !errors.isEmpty { throw CLIError("\(errors.count) error(s) while rendering") }
    }

    /// A simulator that hosts rendering for one (runtime, idiom) group.
    struct Host { let target: Target; let runtime: SimRuntime; let type: SimDeviceType; let profiles: [DeviceProfile] }

    func planHosts(_ target: Target) async throws -> [Host] {
        let runtimes = target.runtimes, types = target.types
        let cache = DeviceCatalog.loadCache()
        var hosts: [Host] = []
        let allTypes = try await Simctl.deviceTypes()
        for runtime in runtimes {
            let info = try await runtimeInfo(runtime)
            var groups: [String: [(SimDeviceType, DeviceProfile)]] = [:]
            for type in types {
                // A device is only rendered on runtimes that actually support it: a host of another
                // model can carry model-specific chrome (e.g. iPhone Duo's side rail on iOS 27.1).
                if !supports(info, type) && !options.allowUnsupportedDevices {
                    skipped.append("\(runtime.name) does not support \(type.name) (pass --allow-unsupported-devices to render it on another host)")
                    continue
                }
                guard let (profile, source) = DeviceCatalog.profile(for: type, runtime: runtime.version, cache: cache) else {
                    errors.append("No screen information for \(type.name) (\(DeviceCatalog.screenDiagnostics(type)))"); continue
                }
                Log.debug("\(type.name) @ \(runtime.name): \(Int(profile.width))×\(Int(profile.height))pt @\(Int(profile.scale))x, safe area \(profile.safeArea) [\(source)]")
                if source == "heuristic", warned.insert(type.name).inserted { Log.warn("\(type.name): safe area estimated; run `swiftshot calibrate --devices \"\(type.name)\"` once for exact insets") }
                // Hosts are shared by every device of the same scale: an iPad host renders @2x
                // phones pixel-identically (idiom comes from trait overrides), but a host of
                // another scale rasterizes glyphs and glass at its own scale.
                groups[profile.hostGroup, default: []].append((type, profile))
            }
            for (group, members) in groups.sorted(by: { $0.key > $1.key }) {
                // Host on a bootable requested device, preferring an iPad (an iPad host renders
                // phones pixel-identically; the reverse differs in glyph anti-aliasing), then the
                // largest. Devices the runtime cannot boot are still rendered from their geometry.
                func rank(_ m: (SimDeviceType, DeviceProfile)) -> (Int, Double) { (m.1.idiom == "pad" ? 1 : 0, m.1.width * m.1.height) }
                let bootable = members.filter { supports(info, $0.0) }.sorted { rank($0) > rank($1) }
                var hostType = bootable.first?.0
                if hostType == nil {
                    // e.g. a runtime that can't boot any requested model: borrow one it can boot,
                    // of the group's idiom if possible.
                    let wantPad = members.contains { $0.1.idiom == "pad" }
                    let family = group.hasPrefix("watch") ? "watch" : wantPad ? "ipad" : "iphone"
                    let candidates = info?.supportedDeviceTypes ?? []
                    let fallback = candidates.last { ($0.productFamily ?? "").lowercased().contains(family) }
                        ?? (family == "ipad" ? candidates.last { ($0.productFamily ?? "").lowercased().contains("iphone") } : nil)
                    hostType = fallback.flatMap { f in allTypes.first { $0.identifier == f.identifier } }
                    if let hostType {
                        Log.warn("\(runtime.name): none of \(members.map(\.0.name).joined(separator: ", ")) can boot; rendering on \(hostType.name), edges may differ slightly")
                    }
                }
                guard let hostType else {
                    skipped.append("\(runtime.name) has no simulator type to host \(members.map(\.0.name).joined(separator: ", "))")
                    continue
                }
                hosts.append(Host(target: target, runtime: runtime, type: hostType, profiles: members.map(\.1)))
            }
        }
        return hosts
    }

    func runVirtual(_ target: Target, hosts: [Host]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for host in hosts {
                let lanes = min(options.parallelLanguages, options.languages.count)
                for lane in 0..<lanes {
                    let languages = options.languages.enumerated().filter { $0.offset % lanes == lane }.map(\.element)
                    group.addTask {
                        do { try await self.runHostLane(host, lane: lane, languages: languages) } catch {
                            self.lock.lock(); self.errors.append("\(host.runtime.name) · \(host.type.name): \(error)"); self.lock.unlock()
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    /// Starts booting every planned simulator, telling the template store how many will need a
    /// first boot per runtime.
    func startBoots(_ planned: [(SimDeviceType, SimRuntime, String)]) async throws {
        let existing = try await Simctl.devices()
        for (type, runtime, suffix) in planned {
            let name = Simctl.deviceName(type: type, runtime: runtime, suffix: suffix)
            let device = existing[runtime.identifier]?.first { $0.name == name && $0.isAvailable }
            if device == nil || device!.isPristine { await TemplateStore.shared.expect(runtime, pristine: 1) }
        }
        // More than fit in memory: each boots when its turn comes (runDevice).
        guard planned.count <= Simctl.simulatorSlots else { return }
        for (type, runtime, suffix) in planned { startBoot(type: type, runtime: runtime, suffix: suffix) }
    }

    /// Creates (seeding from the runtime template) and boots a simulator once; later callers
    /// for the same simulator await the same boot.
    @discardableResult
    func startBoot(type: SimDeviceType, runtime: SimRuntime, suffix: String) -> Task<SimDevice, Error> {
        let key = "\(type.identifier)|\(runtime.identifier)|\(suffix)"
        lock.lock(); defer { lock.unlock() }
        if let task = bootTasks[key] { return task }
        let task = Task<SimDevice, Error> {
            let t = Date()
            let device = try await Simctl.ensureDevice(type: type, runtime: runtime, suffix: suffix)
            let firstBoot = await TemplateStore.shared.prepare(device, runtime: runtime)
            if type.name.hasPrefix("iPad") { try await Simctl.useFullScreenApps(device) }
            try await Simctl.boot(device.udid, firstBoot: firstBoot)
            self.record("boot \(device.name)", t)
            return device
        }
        bootTasks[key] = task
        return task
    }

    func prepare(type: SimDeviceType, runtime: SimRuntime, suffix: String, app: BuiltApp, statusBar: Bool = false) async throws -> SimDevice {
        let t = Date()
        let device = try await startBoot(type: type, runtime: runtime, suffix: suffix).value
        if statusBar { try await Simctl.overrideStatusBar(device.udid) }
        let i = Date()
        try await Simctl.install(device.udid, app: app.path)
        record("install \(device.name)", i)
        if statusBar {
            // SpringBoard lays out its status bar a pixel differently (Wi-Fi next to the signal
            // bars) until the first app launch after boot; launch once so every capture is settled.
            try await sh(Simctl.cmd(["launch", "--terminate-running-process", device.udid, app.bundleID]), allowFailure: true)
            try await sh(Simctl.cmd(["terminate", device.udid, app.bundleID]), allowFailure: true)
        }
        Log.info("Ready: \(device.name) (boot+install \(ms(since: t)))")
        return device
    }

    func runHostLane(_ host: Host, lane: Int, languages: [String]) async throws {
        let app = host.target.app
        let device = try await prepare(type: host.type, runtime: host.runtime, suffix: lane == 0 ? "" : " #\(lane + 1)", app: app)
        for language in languages {
            let t = Date()
            let job = makeJob(mode: .virtual, language: language, runtime: host.runtime, devices: host.profiles, target: host.target)
            let result: JobResult
            do { result = try await launch(job, tag: "virtual-\(host.runtime.version)-\(host.profiles[0].hostGroup)-\(host.type.name)-lane\(lane)-\(language)", udid: device.udid, app: app) } catch {
                lock.lock(); errors.append("\(host.runtime.name) · \(language) · \(host.type.name): \(error)"); lock.unlock()
                continue
            }
            collect(result)
            record("render \(host.runtime.name) \(host.profiles[0].idiom) \(language)", t)
            Log.success("\(host.runtime.name) · \(language) · \(host.profiles.map(\.name).joined(separator: ", ")): \(result.shots.count) shots in \(ms(since: t)) (in-app \(Int(result.totalMs)) ms)")
        }
        if options.shutdownAfter { try? await Simctl.shutdown(device.udid) }
    }

    func runDevice(_ target: Target) async throws {
        let runtimes = target.runtimes, types = target.types
        let cache = DeviceCatalog.loadCache()
        var jobs: [(SimDeviceType, DeviceProfile, SimRuntime)] = []
        for runtime in runtimes {
            let info = try await runtimeInfo(runtime)
            for type in types {
                guard supports(info, type) else {
                    skipped.append("iOS \(runtime.version) cannot boot \(type.name) (device mode); virtual mode can still render it"); continue
                }
                guard let (profile, _) = DeviceCatalog.profile(for: type, runtime: runtime.version, cache: cache) else { continue }
                jobs.append((type, profile, runtime))
            }
        }
        // Taking turns when they don't all fit in memory: each shuts down for the next.
        let takeTurns = jobs.count > Simctl.simulatorSlots
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (type, profile, runtime) in jobs {
                group.addTask {
                    do {
                        try await Simctl.simulatorLimiter.run {
                            try await self.runOnDevice(type: type, profile: profile, runtime: runtime, target: target, shutdownAfter: takeTurns)
                        }
                    } catch {
                        self.lock.lock(); self.errors.append("\(runtime.name) · \(type.name): \(error)"); self.lock.unlock()
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    func runOnDevice(type: SimDeviceType, profile: DeviceProfile, runtime: SimRuntime, target: Target, shutdownAfter: Bool = false) async throws {
        let app = target.app
        let device = try await prepare(type: type, runtime: runtime, suffix: "", app: app, statusBar: true)
        for language in options.languages {
          // A second attempt after a reboot when SpringBoard never hid the home grabber (such
          // captures show it: a long-running simulator was seen to stop reporting touch idleness)
          // or a framebuffer grab failed (`simctl io` was seen to hang on a hosted runner, again
          // minutes after a reboot).
          let attempts = 3
          for attempt in 0..<attempts {
            let t = Date()
            let control = (workDir as NSString).appendingPathComponent("control/\(device.udid)-\(language)")
            try? FileManager.default.removeItem(atPath: control)
            try FileManager.default.createDirectory(atPath: control, withIntermediateDirectories: true)
            let job = makeJob(mode: .device, language: language, runtime: runtime, devices: [profile], controlDir: control, target: target)
            // On iOS 26+ SpringBoard shows the home grabber when the app comes up and hides it once
            // touches are idle (iPads and iPhones alike, same HomeAffordance log); captures show the
            // settled screen without it.
            let major = Int(runtime.version.split(separator: ".").first ?? "") ?? 0
            // Not with a status bar rail (iPhone Duo): its captures never show the grabber, and
            // waiting for it made the Share dialog's popover come up at another anchor in ~1 of 5
            // runs (_UITraitVerticalBarSuppressed 1 instead of 0); 12/12 identical without.
            let rail = (profile.display?.verticalBarAllowed ?? 0) != 0
            let grabber = profile.idiom != "watch" && profile.safeArea.bottom > 0 && major >= 26 && !rail ? await HomeGrabberWatch(udid: device.udid) : nil
            defer { grabber?.stop() }
            let grabFailed = Latch()
            @Sendable func waitForGrabber() async {
                guard let grabber, !grabber.settled, !grabber.gaveUp else { return }
                let deadline = Date().addingTimeInterval(30)
                while !grabber.settled && Date() < deadline && !Task.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000) }
                if !grabber.settled {
                    // (A long-running simulator's SpringBoard was seen to stop hiding it: no
                    // "touch idleness changed" any more until a reboot.) Once per language.
                    grabber.gaveUp = true
                    Log.warn("\(type.name): the home grabber did not hide; capturing anyway (rebooting the simulator helps)")
                }
            }

            // Screenshot pump: whenever the agent signals N.ready, grab the framebuffer and ack. It
            // serves the lowest unanswered request, so a relaunched app (retry) starts over cleanly.
            let pump = Task {
                while !Task.isCancelled {
                    let files = Set((try? FileManager.default.contentsOfDirectory(atPath: control)) ?? [])
                    // The agent keeps its first preview up through the app's launch and asks for the
                    // launch to be over (SpringBoard's grabber come and gone) before showing it anew.
                    if files.contains("launch.ready") && !files.contains("launch.done") {
                        await waitForGrabber()
                        FileManager.default.createFile(atPath: (control as NSString).appendingPathComponent("launch.done"), contents: nil)
                        continue
                    }
                    let pending = files.compactMap { $0.hasSuffix(".ready") ? Int($0.dropLast(6)) : nil }.filter { !files.contains("\($0).done") }
                    guard let next = pending.min(),
                          let data = FileManager.default.contents(atPath: (control as NSString).appendingPathComponent("\(next).ready")),
                          let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let path = info["path"] as? String else {
                        try? await Task.sleep(nanoseconds: 5_000_000); continue
                    }
                    await waitForGrabber()
                    // After a failed grab the simulator is rebooted anyway: let the app finish fast.
                    if grabFailed.isSet {
                        FileManager.default.createFile(atPath: (control as NSString).appendingPathComponent("\(next).done"), contents: nil)
                        continue
                    }
                    // Until two grabs agree: SpringBoard is still animating its own chrome right
                    // after a launch (a cold boot's Wi-Fi).
                    var previous: Data?
                    for _ in 0..<8 {
                        do { try await Simctl.screenshot(device.udid, to: path) } catch {
                            Log.warn("\(type.name): screenshot \(next) failed: \(error)")
                            grabFailed.set(); try? FileManager.default.removeItem(atPath: path); break
                        }
                        let grab = FileManager.default.contents(atPath: path)
                        if grab != nil && grab == previous { break }
                        previous = grab
                    }
                    if (info["landscape"] as? Bool) == true, let dims = try? await sh(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path]) {
                        // Older simctl versions return the portrait framebuffer; rotate only in that case.
                        let numbers = dims.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.suffix(2)
                        if numbers.count == 2, numbers.first! < numbers.last! {
                            _ = try? await sh(["sips", "-r", "270", path])
                        }
                    }
                    FileManager.default.createFile(atPath: (control as NSString).appendingPathComponent("\(next).done"), contents: nil)
                }
            }
            let result: JobResult
            do { result = try await launch(job, tag: "device-\(runtime.version)-\(type.name)-\(language)", udid: device.udid, app: app) } catch {
                pump.cancel()
                if grabFailed.isSet && attempt < attempts - 1 {
                    Log.warn("\(type.name): rebooting the simulator and capturing \(language) again")
                    try await reboot(device, app: app)
                    continue
                }
                lock.lock(); errors.append("\(runtime.name) · \(language) · \(type.name): \(error)"); lock.unlock()
                break
            }
            pump.cancel()
            // Captures with the grabber in them are wrong: never left in the output.
            let discardShots = { for shot in result.shots { try? FileManager.default.removeItem(atPath: (self.outputDir as NSString).appendingPathComponent(shot.file)) } }
            if (grabber?.gaveUp == true || grabFailed.isSet) && attempt < attempts - 1 {
                discardShots()
                Log.warn("\(type.name): rebooting the simulator and capturing \(language) again")
                try await reboot(device, app: app)
                continue
            }
            // The host writes the files; a shot whose grab failed is an error, not a screenshot.
            var checked = result
            checked.shots = result.shots.filter { FileManager.default.fileExists(atPath: (outputDir as NSString).appendingPathComponent($0.file)) }
            for missing in result.shots where !checked.shots.contains(where: { $0.file == missing.file }) {
                checked.errors.append("\(runtime.name) · \(language) · \(type.name): no framebuffer grab for \(missing.file)")
            }
            if grabber?.gaveUp == true {
                checked.errors.append("\(runtime.name) · \(language) · \(type.name): SpringBoard never hid the home grabber, even after a reboot")
                checked.shots = []
                discardShots()
            }
            collect(checked)
            record("render \(type.name) \(runtime.name) \(language)", t)
            Log.success("\(runtime.name) · \(language) · \(type.name): \(checked.shots.count) shots in \(ms(since: t))")
            break
          }
        }
        if options.shutdownAfter || shutdownAfter { try? await Simctl.shutdown(device.udid) }
    }

    /// Restarts a device-mode simulator the way `prepare` leaves it: status bar overridden and the
    /// app launched once.
    func reboot(_ device: SimDevice, app: BuiltApp) async throws {
        try await Simctl.shutdown(device.udid)
        try await Simctl.boot(device.udid)
        try await Simctl.overrideStatusBar(device.udid)
        try await sh(Simctl.cmd(["launch", "--terminate-running-process", device.udid, app.bundleID]), allowFailure: true)
        try await sh(Simctl.cmd(["terminate", device.udid, app.bundleID]), allowFailure: true)
    }

    // MARK: list / devices / calibrate

    func list() async throws {
        let types = try await resolveDeviceTypes()
        let platform = Platform.of(types[0])
        let app = try await Builder.build(options, platform: platform)
        let runtime = try await resolveRuntimes(platform)[0]
        let target = Target(platform: platform, app: app, runtimes: [runtime], types: types)
        let info = try await runtimeInfo(runtime)
        guard let type = types.first(where: { supports(info, $0) }) else { throw CLIError("No bootable device for iOS \(runtime.version)") }
        let device = try await prepare(type: type, runtime: runtime, suffix: "", app: app)
        let result = try await launch(makeJob(mode: .list, language: options.languages[0], runtime: runtime, devices: [], target: target),
                                      tag: "list", udid: device.udid, app: app)
        print("\(result.previews.count) previews:")
        for p in result.previews { print("  • \(p)") }
    }

    func devices() async throws {
        let runtimes = try await Simctl.runtimes()
        print("Installed iOS runtimes: \(runtimes.map(\.version).joined(separator: ", "))")
        let cache = DeviceCatalog.loadCache()
        let types = options.devices.isEmpty ? try await Simctl.deviceTypes() : try await resolveDeviceTypes()
        for type in types {
            guard let (p, source) = DeviceCatalog.profile(for: type, runtime: runtimes.last?.version ?? "", cache: cache) else { continue }
            let s = p.safeArea
            let geometry = String(format: "%4.0f×%-4.0fpt @%.0fx  safe area t%.0f b%.0f l%.0f r%.0f", p.width, p.height, p.scale, s.top, s.bottom, s.left, s.right)
            print("  " + type.name.padding(toLength: 30, withPad: " ", startingAt: 0) + geometry + "  [\(source)]")
        }
    }

    func calibrate() async throws {
        let types = try await resolveDeviceTypes()
        let platform = Platform.of(types[0])
        let app = try await Builder.build(options, platform: platform)
        let runtimes = try await resolveRuntimes(platform)
        let target = Target(platform: platform, app: app, runtimes: runtimes, types: types)
        var cache = DeviceCatalog.loadCache()
        let cacheLock = NSLock()
        // Each device holds its slot from boot until shutdown, so at most this many are up at once.
        let slots = AsyncLimiter(limit: max(2, ProcessInfo.processInfo.activeProcessorCount / 4))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for runtime in runtimes {
                let info = try await runtimeInfo(runtime)
                for type in types where supports(info, type) {
                    group.addTask {
                      do { try await slots.run {
                        let device = try await self.prepare(type: type, runtime: runtime, suffix: "", app: app)
                        // Shut down (and, in a throwaway device set like CI's full sweep, deleted:
                        // every booted device keeps gigabytes, and all types × runtimes fill a hosted
                        // runner's disk) before the slot goes to the next device, also when the launch fails.
                        let result: JobResult
                        do {
                            let base = DeviceCatalog.profile(for: type, runtime: runtime.version, cache: [:])?.0
                            result = try await self.launch(self.makeJob(mode: .calibrate, language: "en-US", runtime: runtime,
                                                                        devices: base.map { [$0] } ?? [], target: target),
                                                           tag: "calibrate-\(runtime.version)-\(type.name)", udid: device.udid, app: app)
                        } catch { await self.discard(device.udid); throw error }
                        await self.discard(device.udid)
                        if var profile = result.calibration {
                            profile.name = type.name
                            cacheLock.lock()
                            cache[DeviceCatalog.cacheKey(device: type.name, runtime: runtime.version)] = profile
                            DeviceCatalog.saveCache(cache)   // after every device: an interrupted run keeps its results
                            cacheLock.unlock()
                            let s = profile.safeArea
                            Log.success("\(type.name) @ \(runtime.name): \(Int(profile.width))×\(Int(profile.height)) @\(Int(profile.scale))x safe t\(s.top) b\(s.bottom)")
                        }
                      } } catch {
                        Log.warn("\(type.name) @ \(runtime.name): calibration failed: \(error)")
                      }
                    }
                }
            }
            try await group.waitForAll()
        }
        DeviceCatalog.saveCache(cache)
        Log.success("Calibration saved to \(DeviceCatalog.cacheURL.path)")
        if let table = options.emitTable { try writeDisplayTable(cache, to: table) }
    }

    private func discard(_ udid: String) async {
        try? await Simctl.shutdown(udid)
        if Simctl.deviceSet != nil { try? await Simctl.delete(udid) }
    }

    /// `swiftshot emit-table --emit-table <file> a.json b.json …`: merges calibration files (e.g.
    /// from several CI images with different runtimes) into the built-in display table.
    func emitTable() async throws {
        guard let table = options.emitTable else { throw CLIError("emit-table needs --emit-table <BuiltInDisplays.swift>") }
        var merged: [String: DeviceProfile] = [:]
        for file in options.inputFiles {
            let profiles = try JSONDecoder().decode([String: DeviceProfile].self, from: Data(contentsOf: URL(fileURLWithPath: file)))
            merged.merge(profiles) { $1 }
        }
        try writeDisplayTable(merged, to: table)
    }

    func writeDisplayTable(_ cache: [String: DeviceProfile], to table: String) throws {
        let header = "// Generated by `swiftshot calibrate --emit-table` / `swiftshot emit-table` (see bench/update-device-table.sh); do not edit.\n" +
            "// Display data measured on booted simulators.\n"
        try DeviceCatalog.displayTableSource(cache, existing: BuiltInDisplays.table, existingSizes: BuiltInDisplays.contentSizeCategory,
                                              existingSafeAreas: BuiltInDisplays.watchSafeArea, header: header).write(toFile: table, atomically: true, encoding: .utf8)
        Log.success("Display table written to \(table) (\(cache.count) measurements)")
    }
}
