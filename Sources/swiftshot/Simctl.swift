// Thin, headless wrapper around `xcrun simctl`. Nothing here ever opens Simulator.app:
// devices are booted with `simctl boot` and driven purely over CoreSimulator, which is
// exactly what works on CI machines without a GUI session.

import Foundation

struct SimRuntime: Decodable {
    let identifier: String
    let version: String
    let name: String
    let platform: String?
    let isAvailable: Bool
    let bundlePath: String?
    let buildversion: String?
}

struct SimDeviceType: Decodable {
    let identifier: String
    let name: String
    let productFamily: String?
    let bundlePath: String
    let modelIdentifier: String?
    let minRuntimeVersionString: String?
    let maxRuntimeVersionString: String?
}

struct SimDevice: Decodable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool
    let deviceTypeIdentifier: String?
    let dataPath: String?
    let dataPathSize: Int?

    /// A device that has never finished a first boot: its data container is (nearly) empty, so
    /// booting it would run the full ~30 s data migration — unless it is seeded from a template.
    var isPristine: Bool { state == "Shutdown" && (dataPathSize ?? 0) < 64 << 20 }
}

enum Platform: String {
    case ios, watchos
    var runtimeName: String { self == .ios ? "iOS" : "watchOS" }
    var destination: String { self == .ios ? "generic/platform=iOS Simulator" : "generic/platform=watchOS Simulator" }
    var agentFile: String { self == .ios ? "SwiftshotAgent.dylib" : "SwiftshotAgent-watchOS.dylib" }

    static func of(_ type: SimDeviceType) -> Platform {
        (type.productFamily ?? type.name).lowercased().contains("watch") ? .watchos : .ios
    }
}

enum Simctl {
    /// Optional isolated device set (`simctl --set <dir>`), e.g. a pristine set per CI job.
    nonisolated(unsafe) static var deviceSet: String?

    static func cmd(_ args: [String]) -> [String] {
        ["xcrun", "simctl"] + (deviceSet.map { ["--set", $0] } ?? []) + args
    }

    static func runtimes(platform: Platform = .ios) async throws -> [SimRuntime] {
        struct R: Decodable { let runtimes: [SimRuntime] }
        let out = try await sh(Simctl.cmd(["list", "runtimes", "-j"]), stdoutOnly: true)
        return try JSONDecoder().decode(R.self, from: Data(out.utf8)).runtimes
            .filter { $0.isAvailable && $0.identifier.contains(".\(platform.runtimeName)-") }
    }

    static func deviceTypes() async throws -> [SimDeviceType] {
        struct R: Decodable { let devicetypes: [SimDeviceType] }
        let out = try await sh(Simctl.cmd(["list", "devicetypes", "-j"]), stdoutOnly: true)
        return try JSONDecoder().decode(R.self, from: Data(out.utf8)).devicetypes
    }

    static func devices() async throws -> [String: [SimDevice]] {
        struct R: Decodable { let devices: [String: [SimDevice]] }
        let out = try await sh(Simctl.cmd(["list", "devices", "-j"]), stdoutOnly: true)
        return try JSONDecoder().decode(R.self, from: Data(out.utf8)).devices
    }

    /// Returns a dedicated `swiftshot` device for (type, runtime), creating it if needed.
    /// Dedicated devices keep user simulators untouched and stay warm between runs.
    static func deviceName(type: SimDeviceType, runtime: SimRuntime, suffix: String = "") -> String {
        "swiftshot \(type.name) (\(runtime.version))\(suffix)"
    }

    static func ensureDevice(type: SimDeviceType, runtime: SimRuntime, suffix: String = "") async throws -> SimDevice {
        let name = deviceName(type: type, runtime: runtime, suffix: suffix)
        let all = try await devices()
        if let existing = all[runtime.identifier]?.first(where: { $0.name == name && $0.isAvailable }) {
            return existing
        }
        Log.info("Creating simulator \(name)")
        let udid = try await sh(Simctl.cmd(["create", name, type.identifier, runtime.identifier]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let created = try await devices()[runtime.identifier]?.first(where: { $0.udid == udid }) else {
            throw CLIError("simctl created \(udid) but does not list it")
        }
        return created
    }

    static func state(_ udid: String) async throws -> String {
        for (_, list) in try await devices() { if let d = list.first(where: { $0.udid == udid }) { return d.state } }
        return "Unknown"
    }

    /// At most this many simulators boot at the same time. Booting is the one phase that
    /// saturates the machine (a first boot runs data migration and launches every system app);
    /// unbounded parallel boots make everything slower and can crash system apps.
    static let bootLimiter = AsyncLimiter(limit: max(2, ProcessInfo.processInfo.activeProcessorCount / 4))

    /// First boots (full data migration) are the heavy ones: concurrent first boots slow each
    /// other down so much that running them one after another finishes sooner.
    static let firstBootLimiter = AsyncLimiter(limit: 1)

    /// Boots headlessly and waits until the device has finished booting.
    static func boot(_ udid: String, firstBoot: Bool = false) async throws {
        if try await state(udid) == "Booted" { return }
        let work: @Sendable () async throws -> Void = {
            try await bootLimiter.run {
                try await sh(Simctl.cmd(["boot", udid]), allowFailure: true)
                try await sh(Simctl.cmd(["bootstatus", udid, "-b"]))
            }
        }
        if firstBoot { try await firstBootLimiter.run(work) } else { try await work() }
    }

    /// iPads run apps full screen, the classic look (a new simulator defaults to windowed apps:
    /// a resize grabber instead of the home indicator, SpringBoard's window frame under the app's
    /// glass). Written to SpringBoard's preferences while the simulator is shut down.
    static func useFullScreenApps(_ device: SimDevice) async throws {
        guard let data = device.dataPath else { return }
        // The file itself (plutil): the host's `defaults` caches a write and the simulator's own
        // preferences daemon never sees it.
        let prefs = (data as NSString).appendingPathComponent("Library/Preferences/com.apple.springboard.plist")
        let key = "SBMedusaMultitaskingEnabled"
        if (try? await sh(["plutil", "-extract", key, "raw", prefs], stdoutOnly: true))?.trimmingCharacters(in: .whitespacesAndNewlines) == "false" { return }
        if try await state(device.udid) == "Booted" { try await shutdown(device.udid) }
        if !FileManager.default.fileExists(atPath: prefs) {
            try FileManager.default.createDirectory(atPath: (prefs as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try await sh(["plutil", "-create", "binary1", prefs])
        }
        try await sh(["plutil", "-replace", key, "-bool", "NO", prefs])
    }

    static func shutdown(_ udid: String) async throws {
        try await sh(Simctl.cmd(["shutdown", udid]), allowFailure: true)
    }

    static func install(_ udid: String, app: String) async throws {
        try await sh(Simctl.cmd(["install", udid, app]))
    }

    /// What a simulator's status bar goes by, from its region and language settings (which
    /// mirror this Mac's): like any process's current locale, the region's (AppleLocale, with its
    /// calendar and numbering keywords) in the language of the process's localization for the
    /// preferred languages (CFLocale's resolution, which `Locale.current` of this bundle-less tool
    /// skips).
    /// - clock: the 9:41 (and an iPad's date) is formatted in English whatever the languages:
    ///   "en_KR" on a Korean simulator ("9:41\u{202F}", not " 9:41"), "en_SA" on an Arabic one
    ///   (Latin digits), "en_NL", "en_US";
    /// - language: SpringBoard's own localization ("ar_SA" there), which sets the bar's direction.
    /// SWIFTSHOT_HOST_LOCALE / SWIFTSHOT_HOST_LANGUAGES (tests: "ko_KR", "ko-KR,en-US") stand for
    /// this Mac's settings: a simulator set up on a Mac in another region.
    static func statusBarLocales(_ runtime: SimRuntime) -> (clock: String, language: String) {
        let env = ProcessInfo.processInfo.environment, defaults = UserDefaults.standard
        let argumentDomain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var host = argumentDomain
        if let locale = env["SWIFTSHOT_HOST_LOCALE"] { host["AppleLocale"] = locale }
        if let languages = env["SWIFTSHOT_HOST_LANGUAGES"] { host["AppleLanguages"] = languages.split(separator: ",").map(String.init) }
        defaults.setVolatileDomain(host, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(argumentDomain, forName: UserDefaults.argumentDomain) }
        typealias LikeCurrent = @convention(c) (CFArray, Bool) -> Unmanaged<CFLocale>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_CFLocaleCreateLikeCurrentWithBundleLocalizations") else {
            return (Locale.current.identifier, Locale.current.identifier)
        }
        func current(localizations: [String]) -> String? {
            (unsafeBitCast(sym, to: LikeCurrent.self)(localizations as CFArray, false)?.takeRetainedValue() as Locale?)?.identifier
        }
        let springBoard = runtime.bundlePath.map { ($0 as NSString).appendingPathComponent("Contents/Resources/RuntimeRoot/System/Library/CoreServices/SpringBoard.app") }
        let localizations = springBoard.flatMap(Bundle.init(path:))?.localizations ?? []
        let clock = current(localizations: ["en"]) ?? Locale.current.identifier
        return (clock, (localizations.isEmpty ? nil : current(localizations: localizations)) ?? clock)
    }

    /// Apple's 9:41 on Tuesday 9 January 2007, in this Mac's time zone (an iPad's status bar
    /// shows the date too); swiftshot's own status bar shows the same instant.
    static var statusBarTime: String {
        // simctl only takes it with fractional seconds ("2007-01-09T08:41:00.000Z").
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var c = DateComponents(); c.year = 2007; c.month = 1; c.day = 9; c.hour = 9; c.minute = 41
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        return f.string(from: cal.date(from: c)!)
    }

    static func overrideStatusBar(_ udid: String) async throws {
        // The time goes in its own, last call: any other override re-sends the date with a wrong
        // weekday ("Sun 9 Jan" instead of "Tue 9 Jan" on iPad).
        try await sh(Simctl.cmd(["status_bar", udid, "override",
                      "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                      "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100"]),
                     allowFailure: true)
        try await sh(Simctl.cmd(["status_bar", udid, "override", "--time", statusBarTime]), allowFailure: true)
    }

    /// Launches the app with the agent injected and blocks until the app exits.
    static func launchWithAgent(_ udid: String, bundleID: String, agent: String, job: String,
                                language: String, locale: String, contentSize: String?, extraEnv: [String: String] = [:],
                                timeout: TimeInterval) async throws -> String {
        var env = ["SIMCTL_CHILD_DYLD_INSERT_LIBRARIES": agent, "SIMCTL_CHILD_SWIFTSHOT_JOB": job]
        // SWIFTSHOT_* variables of the host (debug/experiment switches) reach the agent too.
        for (k, v) in ProcessInfo.processInfo.environment where k.hasPrefix("SWIFTSHOT_") && k != "SWIFTSHOT_AGENT" { env["SIMCTL_CHILD_" + k] = v }
        for (k, v) in extraEnv { env["SIMCTL_CHILD_" + k] = v }
        return try await sh(Simctl.cmd(["launch", "--console", "--terminate-running-process", udid, bundleID,
                             "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
                             + (contentSize.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])),
                            env: env, timeout: timeout, onLine: { line in if line.hasPrefix("[swiftshot]") { Log.debug(line) } })
    }

    static func screenshot(_ udid: String, to path: String) async throws {
        do {
            try await sh(Simctl.cmd(["io", udid, "screenshot", "--type=png", path]), timeout: 60)
        } catch where "\(error)".contains("Cannot choose between") {
            // A device with a second display (iPhone Duo's inner screen) on some simctl builds;
            // iOS 26.5 rejects --display, so it's only passed when simctl asks for it.
            try await sh(Simctl.cmd(["io", udid, "screenshot", "--type=png", "--display=primary", path]), timeout: 60)
        }
    }
}

/// A tiny async semaphore.
actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        if running >= limit { await withCheckedContinuation { waiters.append($0) } } else { running += 1 }
        defer { if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() } }
        return try await work()
    }
}

/// Follows SpringBoard's home grabber on a booted simulator through its HomeAffordance log. With
/// the new design (iOS 26+) the grabber always auto-hides: it fades in when an app comes up and
/// out again once touches have been idle (`SBHomeGrabberView`, "touch idleness changed - started
/// asserting hidden"). A capture waits for that, rather than for some time to pass.
final class HomeGrabberWatch: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var pending = ""
    private var streaming = false, shown = false, hidden = false

    /// Starts following and returns once the log stream is live (its header is printed).
    init(udid: String) async {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = Simctl.cmd(["spawn", udid, "log", "stream", "--level", "debug", "--style", "compact", "--predicate",
                                        "subsystem == \"com.apple.SpringBoard\" AND category == \"HomeAffordance\""])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.feed(String(decoding: data, as: UTF8.self)) }
        }
        process.terminationHandler = { [weak self] _ in self?.lock.withLock { self?.streaming = true } }
        do { try process.run() } catch { lock.withLock { streaming = true } }
        let deadline = Date().addingTimeInterval(30)   // a stream that never comes up
        while !lock.withLock({ streaming }) && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    private func feed(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        pending += text
        while let r = pending.range(of: "\n") {
            let line = pending[..<r.lowerBound]
            pending.removeSubrange(..<r.upperBound)
            if line.hasPrefix("Filtering the log data") { streaming = true }
            // A grabber's presence: "additive presence change to visible with …" / "… finished".
            if line.contains("presence change to visible") { shown = true; hidden = false }
            else if line.contains("presence change to hidden finished") { if shown { hidden = true } }
            else if line.contains("presence change to hidden") { hidden = false }
        }
    }

    /// True once a grabber has been shown and has finished hiding again (and not come back).
    var settled: Bool { lock.withLock { hidden } }

    func stop() { if process.isRunning { process.terminate() } }
}
