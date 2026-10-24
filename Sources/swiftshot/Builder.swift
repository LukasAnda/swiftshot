// Builds the app once for the iOS Simulator. One build serves every device, iOS version
// and language: nothing is rebuilt per configuration, unlike `build-for-testing` + UI tests.

import Foundation

struct BuiltApp {
    let path: String
    let bundleID: String
}

enum Builder {
    static func build(_ options: Options, platform: Platform = .ios) async throws -> BuiltApp {
        let prebuilt = platform == .ios ? options.appPath : options.watchAppPath
        if let app = prebuilt {
            return BuiltApp(path: app, bundleID: try bundleID(ofApp: app))
        }
        guard let scheme = platform == .ios ? options.scheme : (options.watchScheme ?? options.scheme) else {
            throw CLIError("Pass --scheme (with --project/--workspace) or --app <path to a simulator .app>")
        }
        var base = ["xcrun", "xcodebuild"]
        if let ws = options.workspace { base += ["-workspace", ws] }
        else if let pr = options.project { base += ["-project", pr] }
        base += ["-scheme", scheme, "-configuration", options.configuration,
                 "-destination", platform.destination,
                 "-derivedDataPath", options.derivedData]
        let flags = ["CODE_SIGNING_ALLOWED=NO", "COMPILER_INDEX_STORE_ENABLE=NO", "ONLY_ACTIVE_ARCH=YES", "ARCHS=arm64"]
        // Note: a watch-only app is its own scheme; the iOS scheme is never asked to build for watchOS.

        let start = Date()
        Log.info("Building \(scheme) (\(options.configuration)) for \(platform.runtimeName) Simulator…")
        do {
            try await sh(base + ["build", "-quiet"] + flags + options.xcodebuildArgs)
        } catch let error as ShellError {
            throw CLIError("Build failed:\n" + error.output.split(separator: "\n").filter { $0.contains("error") }.prefix(30).joined(separator: "\n"))
        }
        Log.success("Built in \(ms(since: start))")

        let settings = try await sh(base + ["-showBuildSettings", "-json"] + flags, stdoutOnly: true)
        struct Entry: Decodable { let buildSettings: [String: String] }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(settings.utf8))
        guard let app = entries.map(\.buildSettings).first(where: { $0["WRAPPER_EXTENSION"] == "app" }),
              let dir = app["TARGET_BUILD_DIR"], let product = app["FULL_PRODUCT_NAME"] else {
            throw CLIError("Scheme \(scheme) does not build an iOS application")
        }
        let path = (dir as NSString).appendingPathComponent(product)
        return BuiltApp(path: path, bundleID: try bundleID(ofApp: path))
    }

    static func bundleID(ofApp path: String) throws -> String {
        let plist = URL(fileURLWithPath: path).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = dict["CFBundleIdentifier"] as? String else {
            throw CLIError("Cannot read CFBundleIdentifier from \(plist.path)")
        }
        return id
    }
}
