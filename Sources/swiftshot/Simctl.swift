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

    static func shutdown(_ udid: String) async throws {
        try await sh(Simctl.cmd(["shutdown", udid]), allowFailure: true)
    }

    static func install(_ udid: String, app: String) async throws {
        try await sh(Simctl.cmd(["install", udid, app]))
    }

    static func overrideStatusBar(_ udid: String) async throws {
        try await sh(Simctl.cmd(["status_bar", udid, "override",
                      "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                      "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100"]),
                     allowFailure: true)
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
        try await sh(Simctl.cmd(["io", udid, "screenshot", "--type=png", path]))
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
