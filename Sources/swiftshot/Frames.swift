// Device frames for a set of screenshots: after a run (`--frame`) or for an existing folder
// (`swiftshot frame <dir>`).
//
//   plain     the device with the screenshot in it, transparent around it (marketing pages).
//             <frame output>/<lang>/<name>_framed.png, by default in "<output>-framed": these are
//             not App Store sizes, and deliver checks every image in a language folder.
//   appstore  an App Store screenshot of the device's display class: background, localized
//             title, the framed device. <output>/<lang>/<name>_framed.png, next to the original:
//             once a language folder has *_framed.png files, deliver uploads those (and watch
//             screenshots) and skips the rest. So a screenshot that stays unframed in such a
//             folder (no bezel for the model, `frame=none`) gets an identical *_framed.png copy,
//             and stale frames of screenshots that are no longer framed are removed.
//
// Apple Watch screenshots stay unframed in App Store mode: App Store Connect takes the bare
// screen (e.g. 422×514), and deliver uploads watch screenshots whether framed ones exist or not.

import CoreGraphics
import Foundation
import ImageIO

enum FrameMode: String, Codable, CaseIterable { case plain, appstore, none }

struct FrameRequest {
    var path: String          // absolute
    var relative: String      // to the screenshots folder: "en-US/iPhone 17 Pro Max-Welcome.png"
    var device: String
    var language: String
    var appearance: String
    var mode: FrameMode
}

struct FrameSettings {
    var root: String
    var plainOutput: String
    var colors: [String] = []
    var framefile: String?
    var background: String?
    var acceptLicense = false

    static func defaultPlainOutput(for root: String) -> String {
        let url = URL(fileURLWithPath: root).standardizedFileURL
        return url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-framed").path
    }
}

final class FrameRun {
    let settings: FrameSettings
    private let lock = NSLock()
    private var warned = Set<String>()
    private var framefiles: [String: Framefile] = [:]
    private var strings: [String: [String: String]] = [:]
    private var backgrounds: [String: CGImage] = [:]

    struct Summary {
        var framed: [String: String] = [:]   // request path -> framed file
        var plain = 0, appStore = 0, copies = 0, partial = 0, watches = 0
        var missing: Set<String> = []
        var errors: [String] = []
        var seconds = 0.0
        var total: Int { plain + appStore }
    }

    init(_ settings: FrameSettings) { self.settings = settings }

    static func framedName(_ relative: String) -> String {
        ((relative as NSString).deletingPathExtension) + "_framed.png"
    }

    func output(_ r: FrameRequest, _ mode: FrameMode) -> String {
        ((mode == .plain ? settings.plainOutput : settings.root) as NSString).appendingPathComponent(FrameRun.framedName(r.relative))
    }

    private func warnOnce(_ key: String, _ message: String) {
        lock.lock(); let first = warned.insert(key).inserted; lock.unlock()
        if first { Log.warn(message) }
    }

    /// Asks for Apple's license (once) and downloads the bezel families these devices need;
    /// call early so the download overlaps with other work.
    func prepare(devices: [String], modes: Set<FrameMode>) async throws -> [String: BezelStore.Pack] {
        let packs = Self.packs(devices: devices, modes: modes)
        if packs.isEmpty { return [:] }
        try BezelStore.ensureLicense(accept: settings.acceptLicense)
        return try await BezelStore.install(packs)
    }

    func run(_ requests: [FrameRequest], packs preinstalled: [String: BezelStore.Pack]? = nil) async throws -> Summary {
        let start = Date()
        var summary = Summary()
        let active = requests.filter { $0.mode != .none }
        var packs = preinstalled ?? [:]
        if preinstalled == nil { packs = try await prepare(devices: active.map(\.device), modes: Set(active.map(\.mode))) }
        for f in Set(active.compactMap { framefilePath(for: $0) }) {
            if let unsupported = try framefile(f)?.unsupportedKeys, !unsupported.isEmpty {
                Log.warn("\(f): ignoring keys swiftshot does not support: \(unsupported.joined(separator: ", "))")
            }
        }

        // Plan: which bezel image frames which screenshot (needs only the image sizes).
        struct Job { let request: FrameRequest; let mode: FrameMode; let bezel: String; let width: Int; let height: Int }
        var jobs: [Job] = []
        for r in requests where r.mode != .none {
            if r.mode == .appstore && AppStoreSizes.idiom(of: r.device) == "watch" { summary.watches += 1; continue }
            guard let model = BezelCatalog.model(for: r.device), let pack = packs[model.pack] else { summary.missing.insert(r.device); continue }
            guard let (w, h) = Self.imageSize(r.path) else { summary.errors.append("\(r.path): not a readable image"); continue }
            let entries = BezelCatalog.entries(pack.files, for: model)
            let orientation = model.portrait == nil ? nil : (w > h ? model.landscape : model.portrait)
            let candidates = entries.filter { $0.orientation == orientation }
            if candidates.isEmpty && !entries.isEmpty { summary.partial += 1; continue }   // no bezel of that shape: not a full screen
            let colors = Array(Set(candidates.map(\.color)))
            let style = try? style(for: r)
            let wanted = BezelCatalog.colorChoice(settings.colors, device: r.device) ?? style?.frame
            var color = model.defaultColor
            if let wanted {
                if let match = BezelCatalog.matchColor(wanted, in: colors) { color = match } else {
                    warnOnce("color \(r.device) \(wanted)", "\(r.device) has no '\(wanted)' frame (\(colors.sorted().joined(separator: ", "))); using \(model.defaultColor)")
                }
            }
            guard let entry = candidates.first(where: { $0.color == color }) ?? candidates.first(where: { $0.color == model.defaultColor }) ?? candidates.first else {
                summary.missing.insert(r.device); continue
            }
            jobs.append(Job(request: r, mode: r.mode, bezel: (pack.dir as NSString).appendingPathComponent(entry.path), width: w, height: h))
        }

        // Decode each bezel once, in parallel.
        let bezelPaths = Array(Set(jobs.map(\.bezel)))
        var bezels: [String: Result<Bezel, Error>] = [:]
        let results = Self.parallel(bezelPaths.count) { i in Result { try Bezel(path: bezelPaths[i]) } }
        for (path, result) in zip(bezelPaths, results) { bezels[path] = result }

        // Frame, in parallel.
        enum Outcome { case framed(String), partial, failed(String) }
        let outcomes: [Outcome] = Self.parallel(jobs.count) { i in
            let job = jobs[i]
            do {
                let bezel = try bezels[job.bezel]!.get()
                guard Framer.fits(width: job.width, height: job.height, opening: bezel.opening.size) else { return .partial }
                let shot = try Framer.load(job.request.path)
                guard let device = Framer.plain(shot, in: bezel) else { return .failed("\(job.request.path): compositing failed") }
                let out = self.output(job.request, job.mode)
                if job.mode == .plain {
                    try Framer.writePNG(device, to: out)
                } else {
                    let canvas = AppStoreSizes.canvas(width: job.width, height: job.height, idiom: AppStoreSizes.idiom(of: job.request.device))
                    let style = try self.storeStyle(for: job.request, canvas: canvas)
                    guard let image = Framer.appStore(device: device, canvas: canvas, style: style) else { return .failed("\(job.request.path): compositing failed") }
                    try Framer.writePNG(image, to: out)
                }
                return .framed(out)
            } catch {
                return .failed("\(job.request.path): \(error)")
            }
        }
        for (job, outcome) in zip(jobs, outcomes) {
            switch outcome {
            case .framed(let out):
                summary.framed[job.request.path] = out
                if job.mode == .plain { summary.plain += 1 } else { summary.appStore += 1 }
            case .partial:
                summary.partial += 1
                Log.debug("\(job.request.relative): not a full screen (\(job.width)×\(job.height)); left unframed")
            case .failed(let message): summary.errors.append(message)
            }
        }

        // deliver: keep unframed App Store-sized screenshots uploadable in folders with frames.
        // Frames older than their screenshot (an earlier run's) are removed; newer ones (e.g. plain
        // frames made by `swiftshot frame` before an App Store pass) are kept.
        let fm = FileManager.default
        func modified(_ path: String) -> Date? { (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date }
        func removeIfStale(_ frame: String, of shot: String) {
            guard let f = modified(frame) else { return }
            if f < modified(shot) ?? .distantFuture { try? fm.removeItem(atPath: frame) }
        }
        let storeFramed = Set(jobs.filter { $0.mode == .appstore && summary.framed[$0.request.path] != nil }.map(\.request.path))
        let plainFramed = Set(jobs.filter { $0.mode == .plain && summary.framed[$0.request.path] != nil }.map(\.request.path))
        let storeFolders = Set(requests.filter { storeFramed.contains($0.path) }.map { ($0.relative as NSString).deletingLastPathComponent })
        for r in requests where !storeFramed.contains(r.path) {
            let storeOut = output(r, .appstore)
            if storeFolders.contains((r.relative as NSString).deletingLastPathComponent), AppStoreSizes.idiom(of: r.device) != "watch",
               let (w, h) = Self.imageSize(r.path), AppStoreSizes.accepts(width: w, height: h) {
                try? fm.removeItem(atPath: storeOut)
                do { try fm.copyItem(atPath: r.path, toPath: storeOut); summary.copies += 1 } catch { summary.errors.append("\(storeOut): \(error)") }
            } else {
                removeIfStale(storeOut, of: r.path)
            }
        }
        for r in requests where !plainFramed.contains(r.path) { removeIfStale(output(r, .plain), of: r.path) }
        summary.seconds = Date().timeIntervalSince(start)
        return summary
    }

    // MARK: Styles

    private func framefilePath(for r: FrameRequest) -> String? {
        if let explicit = settings.framefile { return explicit }
        return Framefile.find(languageDir: (r.path as NSString).deletingLastPathComponent, root: settings.root)
    }

    private func framefile(_ path: String) throws -> Framefile? {
        lock.lock(); defer { lock.unlock() }
        if let f = framefiles[path] { return f }
        guard FileManager.default.fileExists(atPath: path) else { throw CLIError("Framefile \(path) not found") }
        let f = try Framefile.load(path)
        framefiles[path] = f
        return f
    }

    func style(for r: FrameRequest) throws -> FrameStyle {
        guard let path = framefilePath(for: r), let file = try framefile(path) else { return FrameStyle() }
        return try file.style(for: r.relative)
    }

    private func text(_ name: String, for r: FrameRequest) throws -> String? {
        guard let path = StringsFile.find(name, languageDir: (r.path as NSString).deletingLastPathComponent, root: settings.root) else { return nil }
        lock.lock(); let cached = strings[path]; lock.unlock()
        let table = try cached ?? StringsFile.load(path)
        lock.lock(); strings[path] = table; lock.unlock()
        return StringsFile.lookup(table, fileName: (r.path as NSString).lastPathComponent)
    }

    private func background(_ path: String) throws -> CGImage {
        lock.lock(); let cached = backgrounds[path]; lock.unlock()
        if let cached { return cached }
        let image = try Framer.load(path)
        lock.lock(); backgrounds[path] = image; lock.unlock()
        return image
    }

    /// Background: --frame-background, the Framefile's, or a light/dark grey by appearance.
    /// Text colour: the Framefile's, or black/white for contrast with the background.
    func storeStyle(for r: FrameRequest, canvas: (width: Int, height: Int)) throws -> Framer.StoreStyle {
        let style = try style(for: r)
        let short = Double(min(canvas.width, canvas.height))
        let spec = settings.background ?? style.background ?? (r.appearance == "dark" ? "#1C1C1E" : "#F2F2F7")
        let background: Framer.StoreStyle.Background
        if let color = Framer.color(spec) { background = .color(color) } else { background = .image(try self.background(spec)) }
        let autoText = Framer.luminance(background) > 0.4 ? "#1D1D1F" : "#FFFFFF"
        // frameit: font_scale_factor × width. Default: from the canvas area, so a landscape
        // canvas doesn't get a bigger title than a portrait one.
        let titleSize = style.title.fontSize ?? style.fontScaleFactor.map { $0 * Double(canvas.width) }
            ?? 0.055 * Double(canvas.width * canvas.height).squareRoot()
        func make(_ t: FrameStyle.Text, _ text: String?, size: Double, bold: Bool, fallbackColor: String) -> Framer.StoreStyle.Text? {
            guard let text, !text.isEmpty else { return nil }
            return .init(text: text, color: Framer.color(t.color ?? fallbackColor)!, font: Framer.font(t.font(for: r.language), size: size, bold: bold, language: r.language))
        }
        let titleColor = style.title.color ?? autoText
        let padding = style.padding.map { ($0.h.resolve(short), $0.v.resolve(short)) } ?? (0.07 * short, 0.07 * short)
        return Framer.StoreStyle(
            background: background,
            title: make(style.title, try text("title.strings", for: r) ?? style.title.text, size: titleSize, bold: true, fallbackColor: titleColor),
            keyword: make(style.keyword, try text("keyword.strings", for: r) ?? style.keyword.text, size: style.keyword.fontSize ?? titleSize,
                          bold: style.keyword.font == nil, fallbackColor: style.keyword.color ?? titleColor),
            padding: padding, titleBelowImage: style.titleBelowImage, stackTitle: style.stackTitle,
            showCompleteFrame: style.showCompleteFrame, titleMinHeight: style.titleMinHeight?.resolve(short) ?? 0,
            interlineSpacing: style.interlineSpacing ?? 0)
    }

    // MARK: Helpers

    /// The bezel families these devices need (watches only for plain frames).
    static func packs(devices: [String], modes: Set<FrameMode>) -> Set<String> {
        Set(devices.compactMap { device -> String? in
            guard let m = BezelCatalog.model(for: device) else { return nil }
            if AppStoreSizes.idiom(of: device) == "watch" { return modes.contains(.plain) ? m.pack : nil }
            return modes.contains(.plain) || modes.contains(.appstore) ? m.pack : nil
        })
    }

    static func imageSize(_ path: String) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    /// `body` for 0..<count on up to 8 threads (each framing holds ~100 MB of bitmaps at most).
    static func parallel<T>(_ count: Int, _ body: (Int) -> T) -> [T] {
        guard count > 0 else { return [] }
        var results = [T?](repeating: nil, count: count)
        let lock = NSLock()
        var next = 0
        let workers = min(count, max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))
        results.withUnsafeMutableBufferPointer { buffer in
            let out = buffer
            DispatchQueue.concurrentPerform(iterations: workers) { _ in
                while true {
                    lock.lock(); let i = next; next += 1; lock.unlock()
                    if i >= count { return }
                    out[i] = body(i)
                }
            }
        }
        return results.map { $0! }
    }

    /// The log line for a summary.
    static func report(_ s: Summary, settings: FrameSettings) {
        for e in s.errors { Log.warn(e) }
        if !s.missing.isEmpty {
            Log.warn("No Apple bezel for \(s.missing.sorted().joined(separator: ", ")): left unframed")
        }
        var parts: [String] = []
        if s.plain > 0 { parts.append("\(s.plain) plain → \(settings.plainOutput)") }
        if s.appStore > 0 { parts.append("\(s.appStore) App Store → \(settings.root)") }
        var notes: [String] = []
        if s.partial > 0 { notes.append("\(s.partial) partial-size left unframed") }
        if s.watches > 0 { notes.append("\(s.watches) Apple Watch kept as the bare screen for App Store Connect") }
        if s.copies > 0 { notes.append("\(s.copies) unframed copied as _framed.png for deliver") }
        let line = "\(s.total) frames in \(String(format: "%.1f", s.seconds))s" + (parts.isEmpty ? "" : ": " + parts.joined(separator: ", "))
            + (notes.isEmpty ? "" : " (\(notes.joined(separator: "; ")))")
        if s.errors.isEmpty { Log.success(line) } else { Log.failure(line) }
    }
}

/// `path` relative to `base` ("../screenshots-framed/en-US/x_framed.png").
func relativePath(_ path: String, from base: URL) -> String {
    let a = URL(fileURLWithPath: path).standardizedFileURL.pathComponents, b = base.standardizedFileURL.pathComponents
    let common = zip(a, b).prefix { $0 == $1 }.count
    return (Array(repeating: "..", count: b.count - common) + a[common...]).joined(separator: "/")
}

extension AppStoreSizes {
    static func accepts(width: Int, height: Int) -> Bool {
        let s = (min(width, height), max(width, height))
        return classes.contains { $0.sizes.contains { $0 == s } }
    }
}

extension FrameRun {
    static func settings(_ options: Options, root: String) -> FrameSettings {
        if let cache = options.frameCache { BezelStore.base = URL(fileURLWithPath: cache).standardizedFileURL.path }
        let root = URL(fileURLWithPath: root).standardizedFileURL.path
        return FrameSettings(root: root, plainOutput: options.frameOutput.map { URL(fileURLWithPath: $0).standardizedFileURL.path } ?? FrameSettings.defaultPlainOutput(for: root),
                             colors: options.frameColors, framefile: options.framefile.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
                             background: options.frameBackground.map { Framer.color($0) != nil ? $0 : URL(fileURLWithPath: $0).standardizedFileURL.path },
                             acceptLicense: options.acceptBezelLicense)
    }

    /// The modes a run uses: the global one and any per-screen ones.
    static func modes(_ options: Options) -> Set<FrameMode> {
        Set(([options.frame] + options.screens.map { $0.frame.flatMap { FrameMode(rawValue: $0) } }).compactMap { $0 }.filter { $0 != .none })
    }

    static func mode(_ options: Options, preview: String?) -> FrameMode {
        if let preview, let f = options.screens.first(where: { $0.matches(preview) })?.frame, let m = FrameMode(rawValue: f) { return m }
        return options.frame ?? .none
    }

    /// Requests for a screenshot folder in the deliver layout (<dir>/<lang>/*.png). Devices and
    /// previews come from swiftshot-report.json when there is one, else from the file names.
    static func requests(in dir: String, options: Options, knownDevices: [String]) throws -> [FrameRequest] {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: dir).standardizedFileURL.path
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { throw CLIError("\(dir) is not a folder") }
        struct Report: Decodable { let screenshots: [ShotRecord] }
        let report = (fm.contents(atPath: (root as NSString).appendingPathComponent("swiftshot-report.json")))
            .flatMap { try? JSONDecoder().decode(Report.self, from: $0) }
        let byFile = Dictionary((report?.screenshots ?? []).map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
        var requests: [FrameRequest] = []
        for lang in try fm.contentsOfDirectory(atPath: root).sorted() where !lang.hasPrefix(".") {
            let langDir = (root as NSString).appendingPathComponent(lang)
            guard fm.fileExists(atPath: langDir, isDirectory: &isDir), isDir.boolValue else { continue }
            for file in try fm.contentsOfDirectory(atPath: langDir).sorted()
            where file.lowercased().hasSuffix(".png") && !file.lowercased().hasSuffix("_framed.png") && !file.hasPrefix(".") {
                let relative = "\(lang)/\(file)"
                let record = byFile[relative]
                let name = (file as NSString).deletingPathExtension
                let device = record?.device ?? BezelCatalog.device(inFileName: name, known: knownDevices) ?? name
                var preview = record?.preview
                if preview == nil, name.count > device.count + 1 {
                    preview = String(name.dropFirst(device.count + 1))
                        .replacingOccurrences(of: #"(-(light|dark))?(-[A-Z0-9]+)?(-iOS[0-9.]+)?$"#, with: "", options: .regularExpression)
                }
                let appearance = record?.appearance ?? (name.range(of: #"-dark(-|$)"#, options: .regularExpression) != nil ? "dark" : "light")
                requests.append(FrameRequest(path: (langDir as NSString).appendingPathComponent(file), relative: relative, device: device,
                                             language: lang, appearance: appearance, mode: mode(options, preview: preview)))
            }
        }
        return requests
    }

    /// `swiftshot frame [<dir>]`
    static func command(_ options: Options) async throws {
        let dir = options.inputFiles.first ?? options.output
        let settings = settings(options, root: dir)
        let simulatorNames = (try? await Simctl.deviceTypes().map(\.name)) ?? []
        let requests = try requests(in: dir, options: options, knownDevices: Array(BezelCatalog.models.keys) + simulatorNames)
        if requests.isEmpty { throw CLIError("No screenshots in \(dir) (expected <dir>/<language>/*.png)") }
        let summary = try await FrameRun(settings).run(requests)
        report(summary, settings: settings)
        if !summary.errors.isEmpty { throw CLIError("\(summary.errors.count) screenshot(s) could not be framed") }
    }
}
