// `swiftshot init`: writes a ready-to-use swiftshot.json for the project in the current
// directory. Project, app scheme (and watch app scheme), languages and App Store devices are
// read from the project and the installed simulators; the pure parts are static for tests.

import Foundation

enum Setup {
    static func run(_ options: Options) async throws {
        let configPath = "swiftshot.json"
        if FileManager.default.fileExists(atPath: configPath) && !options.force {
            throw CLIError("\(configPath) already exists (pass --force to overwrite it)")
        }
        var workspace = options.workspace, project = options.project
        if workspace == nil && project == nil {
            (workspace, project) = try findProject(in: ".")
        }
        let container = workspace ?? project!
        let projects = workspace.map(projectsInWorkspace) ?? [project!]

        // Schemes: the given one, else every scheme the project lists, classified by build settings.
        var scheme = options.scheme, watchScheme = options.watchScheme, iPad = false
        let base = ["xcrun", "xcodebuild"] + (workspace.map { ["-workspace", $0] } ?? ["-project", project!])
        struct List: Decodable { struct Item: Decodable { let schemes: [String]?; let targets: [String]? }; let project: Item?; let workspace: Item? }
        let listed = try JSONDecoder().decode(List.self, from: Data(try await sh(base + ["-list", "-json"], stdoutOnly: true).utf8))
        var candidates = scheme.map { [$0] } ?? candidateSchemes(listed.project?.schemes ?? listed.workspace?.schemes ?? [])
        // In a workspace, schemes of the app's own targets come first (not every pod's scheme).
        if workspace != nil, scheme == nil {
            var targets = Set<String>()
            for p in projects where !isPods(p) {
                if let out = try? await sh(["xcrun", "xcodebuild", "-list", "-json", "-project", p], stdoutOnly: true),
                   let l = try? JSONDecoder().decode(List.self, from: Data(out.utf8)) { targets.formUnion(l.project?.targets ?? []) }
            }
            let own = candidates.filter(targets.contains)
            if !own.isEmpty { candidates = own }
        }
        if let watchScheme, !candidates.contains(watchScheme) { candidates.append(watchScheme) }
        Log.info("Reading build settings of \(candidates.joined(separator: ", "))…")
        let kinds = try await withThrowingTaskGroup(of: (String, SchemeKind?).self) { group in
            for s in candidates {
                group.addTask {
                    struct Entry: Decodable { let buildSettings: [String: String] }
                    let out = try await sh(base + ["-scheme", s, "-showBuildSettings", "-json"], allowFailure: true, stdoutOnly: true)
                    let entries = (try? JSONDecoder().decode([Entry].self, from: Data(out.utf8))) ?? []
                    return (s, classify(entries.map(\.buildSettings)))
                }
            }
            var result: [String: SchemeKind] = [:]
            for try await (s, kind) in group { result[s] = kind }
            return result
        }
        let name = ((container as NSString).lastPathComponent as NSString).deletingPathExtension
        let iosSchemes = candidates.filter { if case .iosApp = kinds[$0] { return true } else { return false } }
        let watchSchemes = candidates.filter { kinds[$0] == .watchApp }
        if scheme == nil {
            guard let pick = iosSchemes.first(where: { $0 == name }) ?? iosSchemes.first ?? (watchSchemes.isEmpty ? nil : watchSchemes.first) else {
                throw CLIError("No scheme in \(container) builds an iOS app (pass --scheme)")
            }
            scheme = pick
            if iosSchemes.count > 1 { Log.warn("Several app schemes (\(iosSchemes.joined(separator: ", "))); using \(pick), pass --scheme to change") }
        }
        if case .iosApp(let pad) = kinds[scheme!] { iPad = pad }
        let watchOnly = kinds[scheme!] == .watchApp
        if watchScheme == nil, !watchOnly { watchScheme = watchSchemes.first }

        // Languages: knownRegions of the app's project(s), else the string catalogs / .lproj folders.
        var regions: [String] = []
        for p in projects where !isPods(p) {
            if let pbx = try? String(contentsOfFile: (p as NSString).appendingPathComponent("project.pbxproj"), encoding: .utf8) {
                regions += knownRegions(pbx)
            }
        }
        var languages = languages(fromRegions: regions)
        if languages.count <= 1 { languages = self.languages(fromRegions: regions + localizationsOnDisk(".")) }

        let types = try await Simctl.deviceTypes()
        let ios = try await Simctl.runtimes(platform: .ios).map(\.version).max(by: versionLess)
        let watchos = try await Simctl.runtimes(platform: .watchos).map(\.version).max(by: versionLess)
        let devices = pickDevices(types, iosRuntime: ios, watchRuntime: watchos,
                                  iPhone: !watchOnly, iPad: iPad && !watchOnly, watch: watchOnly || watchScheme != nil)

        var fields: [(String, Any)] = [workspace.map { ("workspace", $0) } ?? ("project", project!), ("scheme", scheme!)]
        if let watchScheme { fields.append(("watch_scheme", watchScheme)) }
        fields += [("devices", devices), ("languages", languages), ("appearances", ["light"]),
                   ("output_directory", "fastlane/screenshots"), ("clear_previous_screenshots", true)]
        let json = renderJSON(fields)
        try json.write(toFile: configPath, atomically: true, encoding: .utf8)
        Log.success("Wrote \(configPath)")
        print(json, terminator: "")
        print("\nNext: `swiftshot list` to see the previews it finds, `swiftshot` to render them.")
    }

    // MARK: - Project

    /// The workspace or project in `dir`, or one level down when `dir` has none.
    static func findProject(in dir: String) throws -> (workspace: String?, project: String?) {
        let fm = FileManager.default
        func entries(_ d: String) -> [String] { ((try? fm.contentsOfDirectory(atPath: d)) ?? []).sorted() }
        func at(_ d: String) -> [String] { entries(d).map { d == "." ? $0 : (d as NSString).appendingPathComponent($0) } }
        if let found = try pickProject(at(dir)) { return found }
        let skip: Set<String> = ["Pods", "Carthage", "DerivedData", "build", "node_modules", "fastlane"]
        let subdirs = entries(dir).filter { !$0.hasPrefix(".") && !skip.contains($0) && !$0.contains(".") }
            .map { dir == "." ? $0 : (dir as NSString).appendingPathComponent($0) }
        var found: [(String?, String?)] = []
        for sub in subdirs { if let f = try? pickProject(at(sub)) { found.append(f) } }
        if found.count == 1 { return found[0] }
        let names = found.map { $0.0 ?? $0.1! }
        if names.isEmpty { throw CLIError("No .xcworkspace or .xcodeproj here or one level down (pass --project or --workspace)") }
        throw CLIError("Several projects found: \(names.joined(separator: ", ")) (pass --project or --workspace)")
    }

    /// Chooses among the entries of one directory: a workspace wins over projects (CocoaPods
    /// workspaces wrap the app project); Pods.xcodeproj never counts. Nil when there is none.
    static func pickProject(_ paths: [String]) throws -> (workspace: String?, project: String?)? {
        let workspaces = paths.filter { $0.hasSuffix(".xcworkspace") }
        let projects = paths.filter { $0.hasSuffix(".xcodeproj") && !isPods($0) }
        if workspaces.count == 1 { return (workspaces[0], nil) }
        if workspaces.count > 1 {
            throw CLIError("Several workspaces: \(workspaces.joined(separator: ", ")) (pass --workspace)")
        }
        if projects.count == 1 { return (nil, projects[0]) }
        if projects.count > 1 {
            throw CLIError("Several projects: \(projects.joined(separator: ", ")) (pass --project or --workspace)")
        }
        return nil
    }

    static func isPods(_ path: String) -> Bool { (path as NSString).lastPathComponent == "Pods.xcodeproj" }

    /// The .xcodeproj files a workspace references (relative to the workspace's folder).
    static func projectsInWorkspace(_ workspace: String) -> [String] {
        let dir = (workspace as NSString).deletingLastPathComponent
        guard let xml = try? String(contentsOfFile: (workspace as NSString).appendingPathComponent("contents.xcworkspacedata"), encoding: .utf8) else { return [] }
        return workspaceProjectRefs(xml).map { dir.isEmpty ? $0 : (dir as NSString).appendingPathComponent($0) }
    }

    static func workspaceProjectRefs(_ xml: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"location\s*=\s*"(?:group|container):([^"]+\.xcodeproj)""#)
        return regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { Range($0.range(at: 1), in: xml).map { String(xml[$0]) } }
    }

    // MARK: - Schemes

    enum SchemeKind: Equatable { case iosApp(iPad: Bool), watchApp }

    /// Test, Pods and framework-ish schemes are not worth asking xcodebuild about.
    static func candidateSchemes(_ schemes: [String]) -> [String] {
        schemes.filter { !$0.hasPrefix("Pods-") && !$0.hasSuffix("Tests") && !$0.hasSuffix("UITests") }
    }

    /// What a scheme builds, from its `-showBuildSettings -json` entries: an iOS app (and
    /// whether it runs on iPad), a watchOS app, or nothing screenshot-worthy. An iOS app that
    /// embeds a watch app counts as the iOS app.
    static func classify(_ targets: [[String: String]]) -> SchemeKind? {
        let apps = targets.filter {
            ($0["WRAPPER_EXTENSION"] == "app" || $0["PRODUCT_TYPE"] == "com.apple.product-type.application")
                && !($0["PRODUCT_TYPE"] ?? "").contains("watchapp2-container")
        }
        func platform(_ s: [String: String]) -> String { (s["PLATFORM_NAME"] ?? (s["SDKROOT"].map { ($0 as NSString).lastPathComponent } ?? "")).lowercased() }
        if let ios = apps.first(where: { platform($0).hasPrefix("iphone") }) {
            let families = (ios["TARGETED_DEVICE_FAMILY"] ?? "1").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return .iosApp(iPad: families.contains("2"))
        }
        if apps.contains(where: { platform($0).hasPrefix("watch") }) { return .watchApp }
        return nil
    }

    // MARK: - Languages

    /// `knownRegions = ( Base, en, "zh-Hans", );` from a project.pbxproj; the development
    /// region first.
    static func knownRegions(_ pbxproj: String) -> [String] {
        guard let start = pbxproj.range(of: "knownRegions = ("),
              let end = pbxproj.range(of: ")", range: start.upperBound..<pbxproj.endIndex) else { return [] }
        var regions = pbxproj[start.upperBound..<end.lowerBound]
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty }
        if let r = pbxproj.range(of: #"developmentRegion = "?([A-Za-z0-9_-]+)"?;"#, options: .regularExpression) {
            let dev = pbxproj[r].replacingOccurrences(of: "developmentRegion = ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\";"))
            if let i = regions.firstIndex(of: dev) { regions.insert(regions.remove(at: i), at: 0) }
        }
        return regions
    }

    /// App Store Connect names for the bare codes it only knows with a region (fastlane deliver's
    /// folder names); codes it uses bare (ja, sk, zh-Hans…) stay as they are.
    static let appStoreLocales = ["ar": "ar-SA", "de": "de-DE", "en": "en-US", "es": "es-ES", "fr": "fr-FR",
                                  "nl": "nl-NL", "pt": "pt-PT", "nb": "no"]

    /// Regions to fastlane language names: no Base, App Store Connect names, the rest as found.
    static func languages(fromRegions regions: [String]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for r in regions where r != "Base" && !r.isEmpty {
            let name = appStoreLocales[r] ?? r
            if seen.insert(name).inserted { result.append(name) }
        }
        return result.isEmpty ? ["en-US"] : result
    }

    /// Languages of the .xcstrings catalogs and .lproj folders under `dir` (build output and
    /// dependencies skipped).
    static func localizationsOnDisk(_ dir: String) -> [String] {
        let skip: Set<String> = ["Pods", "Carthage", "DerivedData", "build", "node_modules", ".build", ".swiftshot", ".git"]
        guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { return [] }
        var found: [String] = []
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if skip.contains(name) || name.hasSuffix(".xcodeproj") { walker.skipDescendants(); continue }
            if url.pathExtension == "lproj" { found.append(url.deletingPathExtension().lastPathComponent); walker.skipDescendants() }
            if url.pathExtension == "xcstrings", let data = try? Data(contentsOf: url) { found += catalogLanguages(data) }
        }
        return found
    }

    static func catalogLanguages(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var langs = (json["sourceLanguage"] as? String).map { [$0] } ?? []
        for case let entry as [String: Any] in (json["strings"] as? [String: Any] ?? [:]).values {
            langs += ((entry["localizations"] as? [String: Any]) ?? [:]).keys.sorted()
        }
        return langs
    }

    // MARK: - Devices

    /// App Store sizes from the device types installed here: the newest Pro Max (6.9"), the
    /// newest 13-inch iPad Pro, the newest Apple Watch Ultra; each must run on the newest runtime.
    static func pickDevices(_ types: [SimDeviceType], iosRuntime: String?, watchRuntime: String?,
                            iPhone: Bool, iPad: Bool, watch: Bool) -> [String] {
        func runs(_ t: SimDeviceType, _ runtime: String?) -> Bool {
            guard let runtime else { return true }
            return !versionLess(runtime, t.minRuntimeVersionString ?? "0") && !versionLess(t.maxRuntimeVersionString ?? "99999", runtime)
        }
        /// The highest-numbered name matching `pattern` (its first capture group is the number).
        func newest(_ pattern: String, runtime: String?) -> String? {
            let regex = try! NSRegularExpression(pattern: "^" + pattern + "$")
            return types.filter { runs($0, runtime) }.compactMap { t -> (Int, String)? in
                guard let m = regex.firstMatch(in: t.name, range: NSRange(t.name.startIndex..., in: t.name)) else { return nil }
                let n = Range(m.range(at: 1), in: t.name).flatMap { Int(t.name[$0]) } ?? 1
                return (n, t.name)
            }.max(by: { $0.0 < $1.0 })?.1
        }
        var devices: [String] = []
        if iPhone { devices.append(newest(#"iPhone (\d+) Pro Max"#, runtime: iosRuntime) ?? "iPhone 17 Pro Max") }
        if iPad {
            devices.append(newest(#"iPad Pro 13-inch \(M(\d+)\)"#, runtime: iosRuntime)
                ?? newest(#"iPad Pro \(12\.9-inch\) \((\d+)th generation\)"#, runtime: iosRuntime) ?? "iPad Pro 13-inch (M5)")
        }
        if watch { devices.append(newest(#"Apple Watch Ultra(?: (\d+))? \(49mm\)"#, runtime: watchRuntime) ?? "Apple Watch Ultra 3 (49mm)") }
        return devices
    }

    /// "26.5" < "27.0.0", numerically per component.
    static func versionLess(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    // MARK: - Output

    /// Pretty JSON in a fixed key order, arrays on one line (like the README's examples).
    static func renderJSON(_ fields: [(String, Any)]) -> String {
        func encode(_ v: Any) -> String {
            switch v {
            case let s as String: return String(decoding: try! JSONEncoder().encode(s), as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
            case let b as Bool: return b ? "true" : "false"
            case let a as [String]: return "[" + a.map(encode).joined(separator: ", ") + "]"
            default: return "null"
            }
        }
        return "{\n" + fields.map { "  \(encode($0.0)): \(encode($0.1))" }.joined(separator: ",\n") + "\n}\n"
    }
}
