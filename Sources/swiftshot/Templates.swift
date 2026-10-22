// Cold-boot accelerator.
//
// A simulator's first boot spends ~25 s of its ~35 s in "data migration" (LaunchServices,
// MobileSafari, keyboards… migrators populating the empty data container), and parallel first
// boots contend so badly that three of them take 2–3 minutes. That migration result does not
// depend on the device model, only on the runtime. So per runtime we pay one first boot, keep
// the migrated `data` container as a template, and seed every other new device of that runtime
// with an APFS clone of it (`clonefile`, copy-on-write: ~0.1 s, no extra disk). A seeded device
// boots like a warm one (~10 s), and many of them boot in parallel without contention.
//
// Templates live in `~/Library/Caches/swiftshot/templates.noindex/<runtime>-<build>/data` (".noindex": Spotlight
// would otherwise crawl the ~15k files of every template) (override with
// `--template-cache`, e.g. to persist them in a CI cache) and are keyed by runtime build.

import Foundation

actor TemplateStore {
    static let shared = TemplateStore()
    nonisolated(unsafe) static var root = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches/swiftshot/templates.noindex")
    nonisolated(unsafe) static var enabled = true

    private var inFlight: [String: Task<String?, Never>] = [:]
    /// How many pristine devices per runtime this run will boot. A template only pays off with
    /// two or more (the donor's extra shutdown + boot costs ~15 s) — or when it is persisted
    /// for later runs via an explicit `--template-cache`.
    private var expected: [String: Int] = [:]
    nonisolated(unsafe) static var persistent = false

    func expect(_ runtime: SimRuntime, pristine count: Int) { expected[Self.key(runtime), default: 0] += count }

    static func key(_ runtime: SimRuntime) -> String { "\(runtime.identifier)-\(runtime.buildversion ?? runtime.version)" }
    static func templateData(_ runtime: SimRuntime) -> String { (root as NSString).appendingPathComponent("\(key(runtime))/data") }

    /// Makes sure a pristine device won't run the full first boot: it is seeded from the runtime's
    /// template, or — if there is none yet — becomes the template donor (first boot, shutdown,
    /// snapshot). Concurrent callers for the same runtime wait for the one donor.
    /// Returns true when the device still needs a full first boot.
    @discardableResult
    func prepare(_ device: SimDevice, runtime: SimRuntime) async -> Bool {
        guard device.isPristine else { return false }
        guard Self.enabled, let dataPath = device.dataPath else { return true }
        let key = Self.key(runtime)
        if FileManager.default.fileExists(atPath: Self.templateData(runtime)) {
            return !seed(dataPath, from: Self.templateData(runtime), device: device)
        }
        if !Self.persistent && expected[key, default: 0] < 2 { return true }
        if let pending = inFlight[key] {
            guard let template = await pending.value else { return true }
            return !seed(dataPath, from: template, device: device)
        }
        let task = Task<String?, Never> { await Self.makeTemplate(donor: device, runtime: runtime) }
        inFlight[key] = task
        let made = await task.value
        inFlight[key] = nil
        return made == nil   // the donor has been booted once (or failed and boots normally)
    }

    private func seed(_ dataPath: String, from template: String, device: SimDevice) -> Bool {
        let fm = FileManager.default
        let backup = dataPath + ".pristine"
        do {
            try? fm.removeItem(atPath: backup)
            try fm.moveItem(atPath: dataPath, toPath: backup)
            guard clonefile(template, dataPath, 0) == 0 else {
                try? fm.removeItem(atPath: dataPath)
                try fm.moveItem(atPath: backup, toPath: dataPath)
                Log.debug("clonefile failed (\(String(cString: strerror(errno)))): \(device.name) boots without template")
                return false
            }
            try? fm.removeItem(atPath: backup)
            Log.debug("Seeded \(device.name) from template")
            return true
        } catch {
            Log.debug("Could not seed \(device.name): \(error)")
            return false
        }
    }

    /// First-boots the donor, shuts it down and snapshots its data container. The donor itself
    /// stays a normal (now migrated) device and is simply booted again by the caller.
    private static func makeTemplate(donor: SimDevice, runtime: SimRuntime) async -> String? {
        guard let dataPath = donor.dataPath else { return nil }
        let t = Date()
        Log.info("First boot of \(runtime.name) (one-time per runtime, becomes the template for all other devices)")
        do {
            try await Simctl.boot(donor.udid, firstBoot: true)
            try await Simctl.shutdown(donor.udid)
        } catch {
            Log.debug("Template donor boot failed: \(error)"); return nil
        }
        let final = templateData(runtime)
        let staging = (root as NSString).appendingPathComponent("\(key(runtime)).staging-\(UUID().uuidString)")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: staging, withIntermediateDirectories: true)
        let stagedData = (staging as NSString).appendingPathComponent("data")
        // Cloning needs the same volume; a plain copy is the (slower) fallback.
        if clonefile(dataPath, stagedData, 0) != 0 {
            do { try fm.copyItem(atPath: dataPath, toPath: stagedData) } catch {
                Log.debug("Could not snapshot template: \(error)"); try? fm.removeItem(atPath: staging); return nil
            }
        }
        let finalDir = (final as NSString).deletingLastPathComponent
        if fm.fileExists(atPath: finalDir) { try? fm.removeItem(atPath: staging) } else {
            do { try fm.moveItem(atPath: staging, toPath: finalDir) } catch { try? fm.removeItem(atPath: staging); return nil }
        }
        Log.info("Template for \(runtime.name) ready in \(ms(since: t))")
        return final
    }
}
