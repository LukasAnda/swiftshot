import Foundation

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

enum Mode: String, Codable { case virtual, device }

/// Every option can come from the command line or from a JSON config file
/// (`--config swiftshot.json`, or `./swiftshot.json` when present). CLI wins.
struct Options: Codable {
    var command = "run"
    var project: String?
    var workspace: String?
    var scheme: String?
    var configuration = "Debug"
    var appPath: String?
    var derivedData = ".swiftshot/DerivedData"
    var xcodebuildArgs: [String] = []

    var devices: [String] = ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)"]
    var iosVersions: [String] = []          // empty = newest installed runtime
    var languages: [String] = ["en-US"]
    var appearances: [String] = ["light"]
    var previews: [String] = []             // filter; empty = all
    var output = "screenshots"
    var mode: Mode = .virtual
    var format = "png"
    var settleFrames = 3
    var delay = 0.0
    var clearOutput = false
    var shutdownAfter = false
    var downloadRuntimes = false
    var html = true
    var statusBar = true
    var parallelLanguages = 1
    var timeout: TimeInterval = 600
    var screens: [ScreenRule] = []
    var watchScheme: String?
    var watchAppPath: String?
    var watchosVersions: [String] = []
    var contentSize: String?
    var textSizes: [String] = ["default"]
    var fullLength = false
    var allowUnsupportedDevices = false
    var deviceSet: String?
    var templates = true
    var noBoot = true     // iOS virtual rendering without a simulator (--boot: the booted path)
    var emitTable: String?
    var inputFiles: [String] = []   // emit-table: calibration.json files to merge
    var templateCache: String?
    var verbose = false

    enum CodingKeys: String, CodingKey {
        case project, workspace, scheme, configuration, appPath = "app", derivedData = "derived_data",
             xcodebuildArgs = "xcodebuild_args", devices, iosVersions = "ios_versions", languages, appearances,
             previews, output = "output_directory", mode, format, settleFrames = "settle_frames", delay,
             clearOutput = "clear_previous_screenshots", shutdownAfter = "shutdown_simulators",
             downloadRuntimes = "download_missing_runtimes", html, statusBar = "status_bar", parallelLanguages = "parallel_languages", timeout, screens, deviceSet = "device_set", watchScheme = "watch_scheme", watchAppPath = "watch_app",
             watchosVersions = "watchos_versions", contentSize = "content_size", textSizes = "text_sizes", fullLength = "full_length", allowUnsupportedDevices = "allow_unsupported_devices",
             templates = "device_templates", templateCache = "template_cache", noBoot = "no_boot", verbose
    }

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ into: inout T) throws {
            if let v = try c.decodeIfPresent(T.self, forKey: key) { into = v }
        }
        func readOpt<T: Decodable>(_ key: CodingKeys, _ into: inout T?) throws {
            if let v = try c.decodeIfPresent(T.self, forKey: key) { into = v }
        }
        try readOpt(.project, &project); try readOpt(.workspace, &workspace); try readOpt(.scheme, &scheme)
        try read(.configuration, &configuration); try readOpt(.appPath, &appPath); try read(.derivedData, &derivedData)
        try read(.xcodebuildArgs, &xcodebuildArgs); try read(.devices, &devices); try read(.iosVersions, &iosVersions)
        try read(.languages, &languages); try read(.appearances, &appearances); try read(.previews, &previews)
        try read(.output, &output); try read(.mode, &mode); try read(.format, &format)
        try read(.settleFrames, &settleFrames); try read(.delay, &delay); try read(.clearOutput, &clearOutput)
        try read(.shutdownAfter, &shutdownAfter); try read(.downloadRuntimes, &downloadRuntimes); try read(.html, &html); try read(.statusBar, &statusBar)
        try read(.parallelLanguages, &parallelLanguages); try read(.timeout, &timeout); try read(.verbose, &verbose)
        try read(.screens, &screens); try readOpt(.deviceSet, &deviceSet)
        try readOpt(.watchScheme, &watchScheme); try readOpt(.watchAppPath, &watchAppPath); try read(.watchosVersions, &watchosVersions)
        try readOpt(.contentSize, &contentSize); try read(.textSizes, &textSizes); try read(.fullLength, &fullLength); try read(.allowUnsupportedDevices, &allowUnsupportedDevices)
        try read(.templates, &templates); try readOpt(.templateCache, &templateCache); try read(.noBoot, &noBoot)
    }

    static let usage = """
    swiftshot — App Store screenshots straight from your SwiftUI #Previews.

    USAGE
      swiftshot [run|list|devices|calibrate|emit-table] [options]

    COMMANDS
      run         Build, render every preview for every device × iOS × language × appearance (default)
      list        Build and print the previews that were discovered
      devices     Show installed iOS runtimes and the geometry used for each device
      calibrate   Boot the given devices once and measure their real safe areas (cached)
      emit-table  Merge calibration.json files into the built-in device table (maintainers)

    BUILD
      --project <path> | --workspace <path>   Xcode project or workspace
      --scheme <name>                         Scheme that builds the app
      --configuration <name>                  Default: Debug
      --app <path>                            Use an already-built simulator .app instead of building
      --derived-data <path>                   Default: .swiftshot/DerivedData
      --xcodebuild-arg <arg>                  Extra xcodebuild argument (repeatable)

    MATRIX
      --devices "iPhone 17 Pro Max,iPad Pro 13-inch (M5),Apple Watch Ultra 3 (49mm)"
      --ios "26.5,27.1"                       iOS runtime versions (default: newest installed)
      --languages "en-US,de-DE"               Default: en-US
      --appearances "light,dark"              Default: light
      --text-sizes "default,XXXL,AX5"         Dynamic Type sizes to render every preview at: XS S M L XL XXL XXXL
                                              AX1…AX5, or default (the device's own: iOS L, watch L/XL by case
                                              size). Non-default sizes get a "-<size>" file name suffix.
      --full-length                           Grow full-screen previews to their scroll view's whole content
                                              (long lists, forms); per screen: full_length=true
      --previews "Welcome,Onboarding*"        Only these previews (glob); default: all

    APPLE WATCH (add watch devices to --devices)
      --watch-scheme <name>                   Scheme of the watchOS app (default: --scheme if only watches are requested)
      --watch-app <path>                      Prebuilt watchOS simulator .app instead of building
      --watchos "27.0"                        watchOS runtime versions (default: newest installed)

    OUTPUT
      --output <dir>                          Default: ./screenshots (fastlane/deliver layout: <dir>/<lang>/<device>-<preview>.png)
      --format png|jpeg                       Default: png
      --clear                                 Delete previous screenshots first
      --no-html                               Do not write screenshots.html
      --no-status-bar                         Leave out the system status bar (9:41, full battery), which is
                                              drawn like on a device by default

    RENDERING
      --mode virtual|device                   virtual (default): every device rendered without booting a simulator.
                                              device: a booted simulator per device, framebuffer capture (the
                                              reference virtual is checked against).
      --content-size <size>                   Change the default text size itself (no file name suffix)
      --delay <seconds>                       Extra settle time before each capture (async images, animations)
      --settle-frames <n>                     Run-loop frames to wait before capture (default 3)
      --parallel-languages <n>                Run n language processes concurrently per iOS version (clones)
      --allow-unsupported-devices             Also render devices a runtime can't boot, on another host of the
                                              same runtime (best effort; skipped by default)
      --download-missing-runtimes             Download requested iOS runtimes that are not installed
      --shutdown                              Shut simulators down afterwards (default: keep warm)
      --timeout <seconds>                     Kill an app launch that takes longer (default 600)

    PER SCREENSHOT
      --screen "<preview>: key=v1,v2 key=v"     Override settings for previews matching <preview> (glob), repeatable.
                                              keys: appearances, languages, devices, ios, text_sizes, full_length,
                                              delay, skip
                                              e.g. --screen "Welcome: appearances=light,dark languages=en-US"
                                              (or a "screens" array in the JSON config; first match wins)

    CI
      --device-set <dir>                      Use an isolated CoreSimulator device set (simctl --set); created
                                              from scratch, never touches the machine's own simulators
      --template-cache <dir>                  Where per-runtime boot templates live (default ~/Library/Caches/
                                              swiftshot/templates.noindex). Cache it between CI jobs and even the
                                              first boot is skipped.
      --no-templates                          Boot every new simulator from scratch (~35 s each, slow in parallel)
      --boot                                  Render previews in booted simulators. The default renders iOS and
                                              watchOS previews without any simulator: the app runs directly on the
                                              Mac against the runtime (swiftshot-simhost provides Metal/IOSurface).
                                              --mode device always uses booted simulators.

      --config <file>                         JSON config (default ./swiftshot.json if present)
      --verbose
    """

    static func parse(_ argv: [String]) throws -> Options {
        var args = argv
        var options = Options()

        // Config file first, then CLI overrides.
        var configPath: String?
        if let i = args.firstIndex(of: "--config"), i + 1 < args.count {
            configPath = args[i + 1]; args.removeSubrange(i...(i + 1))
        } else if FileManager.default.fileExists(atPath: "swiftshot.json") {
            configPath = "swiftshot.json"
        }
        if let configPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            options = try JSONDecoder().decode(Options.self, from: data)
        }

        if let first = args.first, !first.hasPrefix("-") {
            guard ["run", "list", "devices", "calibrate", "emit-table"].contains(first) else { throw CLIError("Unknown command \(first)\n\n\(usage)") }
            options.command = first
            args.removeFirst()
        }

        func list(_ s: String) -> [String] { s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        var i = 0
        func value() throws -> String {
            i += 1
            guard i < args.count else { throw CLIError("Missing value for \(args[i - 1])") }
            return args[i]
        }
        while i < args.count {
            switch args[i] {
            case "--project": options.project = try value()
            case "--workspace": options.workspace = try value()
            case "--scheme": options.scheme = try value()
            case "--configuration": options.configuration = try value()
            case "--app": options.appPath = try value()
            case "--derived-data": options.derivedData = try value()
            case "--xcodebuild-arg": options.xcodebuildArgs.append(try value())
            case "--devices", "--device": options.devices = list(try value())
            case "--ios", "--ios-versions": options.iosVersions = list(try value())
            case "--languages", "--language": options.languages = list(try value())
            case "--appearances", "--appearance": options.appearances = list(try value())
            case "--previews", "--preview": options.previews = list(try value())
            case "--output", "-o": options.output = try value()
            case "--format": options.format = try value()
            case "--mode":
                guard let m = Mode(rawValue: try value()) else { throw CLIError("--mode must be virtual or device") }
                options.mode = m
            case "--delay": options.delay = Double(try value()) ?? 0
            case "--settle-frames": options.settleFrames = Int(try value()) ?? 3
            case "--parallel-languages": options.parallelLanguages = max(1, Int(try value()) ?? 1)
            case "--timeout": options.timeout = Double(try value()) ?? 600
            case "--screen": options.screens.append(try parseScreenRule(try value()))
            case "--device-set": options.deviceSet = try value()
            case "--template-cache": options.templateCache = try value()
            case "--no-templates": options.templates = false
            case "--no-boot": options.noBoot = true
            case "--boot": options.noBoot = false
            case "--emit-table": options.emitTable = try value()
            case "--watch-scheme": options.watchScheme = try value()
            case "--watch-app": options.watchAppPath = try value()
            case "--watchos": options.watchosVersions = list(try value())
            case "--content-size": options.contentSize = try value()
            case "--text-sizes", "--text-size": options.textSizes = list(try value())
            case "--full-length": options.fullLength = true
            case "--allow-unsupported-devices": options.allowUnsupportedDevices = true
            case "--clear": options.clearOutput = true
            case "--shutdown": options.shutdownAfter = true
            case "--download-missing-runtimes": options.downloadRuntimes = true
            case "--no-html": options.html = false
            case "--no-status-bar": options.statusBar = false
            case "--verbose", "-v": options.verbose = true
            case "--help", "-h": print(usage); exit(0)
            case "--version": print("swiftshot \(swiftshotVersion)"); exit(0)
            default:
                // emit-table takes calibration files as plain arguments.
                guard options.command == "emit-table", !args[i].hasPrefix("-") else { throw CLIError("Unknown option \(args[i])\n\n\(usage)") }
                options.inputFiles.append(args[i])
            }
            i += 1
        }
        for a in options.appearances where !["light", "dark"].contains(a) { throw CLIError("Unknown appearance \(a)") }
        try validateTextSizes(options.textSizes)
        for rule in options.screens { try validateTextSizes(rule.textSizes ?? []) }
        if !["png", "jpeg"].contains(options.format) { throw CLIError("--format must be png or jpeg") }
        return options
    }
}

func validateTextSizes(_ sizes: [String]) throws {
    for s in sizes where s.lowercased() != "default" && !s.hasPrefix("UICTContentSizeCategory") && !textSizeNames.contains(s.uppercased()) {
        throw CLIError("Unknown text size \(s) (use default, \(textSizeNames.joined(separator: ", ")))")
    }
}

func parseScreenRule(_ text: String) throws -> ScreenRule {
    guard let colon = text.firstIndex(of: ":") else { throw CLIError("--screen expects \"<preview>: key=value ...\"") }
    var rule = ScreenRule(preview: text[..<colon].trimmingCharacters(in: .whitespaces))
    for pair in text[text.index(after: colon)...].split(separator: " ") where !pair.isEmpty {
        let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard kv.count == 2 else { throw CLIError("--screen: bad setting '\(pair)'") }
        let values = kv[1].split(separator: ",").map(String.init)
        switch kv[0] {
        case "appearances", "appearance": rule.appearances = values
        case "languages", "language": rule.languages = values
        case "devices", "device": rule.devices = values
        case "ios", "ios_versions": rule.iosVersions = values
        case "text_sizes", "text-sizes", "text_size", "text-size": rule.textSizes = values
        case "full_length", "full-length": rule.fullLength = kv[1] == "true"
        case "delay": rule.delay = Double(kv[1])
        case "skip": rule.skip = kv[1] == "true"
        default: throw CLIError("--screen: unknown key '\(kv[0])'")
        }
    }
    return rule
}

/// "de-DE" -> "de_DE", "en" -> "en_US"-ish defaults are left to the OS; we only reshape the tag.
func localeIdentifier(for language: String) -> String {
    language.replacingOccurrences(of: "-", with: "_")
}
