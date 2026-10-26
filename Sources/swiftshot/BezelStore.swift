// Downloads Apple's Product Bezels on first use and keeps their PNGs in a cache.
//
// A family's disk image (7 MB for an iPad, up to 450 MB for iPhone Duo: most of it is Photoshop
// files) is downloaded once, mounted read-only, its PNG folder copied out, and the image deleted.
// hdiutil checks the disk image's checksums when it mounts it; every copied PNG is recorded with
// its size and SHA-256 in manifest.json, and a family whose files don't match is fetched again.
//
//   ~/Library/Caches/swiftshot/frames/<catalog version>/<family>/PNG/…      (--frame-cache)
//
// The disk images carry Apple's Design Resources license, which the user accepts once.

import CryptoKit
import Foundation

enum BezelStore {
    nonisolated(unsafe) static var base: String = ProcessInfo.processInfo.environment["SWIFTSHOT_FRAME_CACHE"]
        ?? (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches/swiftshot/frames")
    static var root: String { (base as NSString).appendingPathComponent(BezelCatalog.version) }
    static var licenseMarker: String { (base as NSString).appendingPathComponent("apple-design-resources-license-accepted") }

    /// An installed family: its directory and its PNGs (relative paths).
    struct Pack { let dir: String; let files: [String] }

    struct Manifest: Codable {
        struct File: Codable { let path: String; let size: Int; let sha256: String }
        let pack: String
        let url: String
        let etag: String?
        let files: [File]
    }

    // MARK: License

    static var licenseAccepted: Bool { FileManager.default.fileExists(atPath: licenseMarker) }

    /// Makes sure the user accepted Apple's license before anything is downloaded: once per
    /// machine (or cache), with `--accept-bezel-license` or by answering the prompt.
    static func ensureLicense(accept: Bool, interactive: Bool = isatty(0) == 1 && isatty(2) == 1) throws {
        if licenseAccepted { return }
        let notice = """
        Device frames use Apple's Product Bezels (developer.apple.com/design/resources), which
        swiftshot downloads from Apple. They come under the Apple Design Resources License:
          \(BezelCatalog.licenseURL)
        Use them as Apple's marketing guidelines describe: developer.apple.com/app-store/marketing/guidelines
        """
        if !accept {
            guard interactive else {
                throw CLIError("\(notice)\nPass --accept-bezel-license (or \"accept_bezel_license\": true) to accept it. It is asked once.")
            }
            FileHandle.standardError.write("\(notice)\nDo you accept the license? [y/N] ".data(using: .utf8)!)
            guard let answer = readLine(), ["y", "yes"].contains(answer.trimmingCharacters(in: .whitespaces).lowercased()) else {
                throw CLIError("Apple's license was not accepted; no frames.")
            }
        }
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        try "Accepted \(ISO8601DateFormatter().string(from: Date())): \(BezelCatalog.licenseURL)\n"
            .write(toFile: licenseMarker, atomically: true, encoding: .utf8)
    }

    // MARK: Packs

    /// The installed family, if its manifest and files are intact.
    static func installed(_ pack: String) -> Pack? {
        let dir = (root as NSString).appendingPathComponent(pack)
        guard let data = FileManager.default.contents(atPath: (dir as NSString).appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), !manifest.files.isEmpty else { return nil }
        for file in manifest.files {
            let size = (try? FileManager.default.attributesOfItem(atPath: (dir as NSString).appendingPathComponent(file.path)))?[.size] as? Int
            if size != file.size { return nil }
        }
        return Pack(dir: dir, files: manifest.files.map(\.path))
    }

    /// Installs the families that aren't cached yet (in parallel) and returns all of them.
    /// Another swiftshot process installing the same family is waited for, not duplicated.
    static func install(_ packs: Set<String>) async throws -> [String: Pack] {
        try await withThrowingTaskGroup(of: (String, Pack).self) { group in
            for pack in packs {
                group.addTask {
                    if let ready = installed(pack) { return (pack, ready) }
                    return (pack, try await withLock(pack) {
                        if let ready = installed(pack) { return ready }   // another process just did it
                        return try await download(pack)
                    })
                }
            }
            var result: [String: Pack] = [:]
            for try await (name, pack) in group { result[name] = pack }
            return result
        }
    }

    private static func withLock<T>(_ pack: String, _ body: () async throws -> T) async throws -> T {
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let fd = open((root as NSString).appendingPathComponent(".\(pack).lock"), O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw CLIError("Cannot create a lock in \(root)") }
        defer { close(fd) }
        // flock blocks the thread: wait off the cooperative pool.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            Thread.detachNewThread { flock(fd, LOCK_EX); c.resume() }
        }
        defer { flock(fd, LOCK_UN) }
        return try await body()
    }

    private static func download(_ pack: String) async throws -> Pack {
        let fm = FileManager.default
        let url = BezelCatalog.url(pack)
        let work = (root as NSString).appendingPathComponent(".tmp-\(pack)-\(UUID().uuidString)")
        try fm.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: work) }

        let start = Date()
        Log.info("Downloading Apple's bezels: \(pack.replacingOccurrences(of: "Bezel-", with: "").replacingOccurrences(of: "-", with: " ")) (once)…")
        let (temp, response) = try await URLSession.shared.download(from: url)
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            try? fm.removeItem(at: temp)
            throw CLIError("Downloading \(url.absoluteString) failed (HTTP \(http?.statusCode ?? 0))")
        }
        let dmg = (work as NSString).appendingPathComponent("bezels.dmg")
        try fm.moveItem(at: temp, to: URL(fileURLWithPath: dmg))
        let bytes = (try fm.attributesOfItem(atPath: dmg)[.size] as? Int) ?? 0
        if response.expectedContentLength > 0, Int64(bytes) != response.expectedContentLength {
            throw CLIError("Downloading \(url.absoluteString) was cut short (\(bytes) of \(response.expectedContentLength) bytes)")
        }

        // The disk image shows Apple's license on mount; the user accepted it (ensureLicense).
        let mount = (work as NSString).appendingPathComponent("mnt")
        try fm.createDirectory(atPath: mount, withIntermediateDirectories: true)
        try attach(dmg, at: mount)
        let staged = (work as NSString).appendingPathComponent(pack)
        var files: [Manifest.File] = []
        do {
            defer { detach(mount) }
            let mountURL = URL(fileURLWithPath: mount).resolvingSymlinksInPath()
            let pngRoot = mountURL.appendingPathComponent("PNG")
            guard let walker = fm.enumerator(at: pngRoot, includingPropertiesForKeys: nil) else { throw CLIError("\(pack): no PNG folder in the disk image") }
            for case let file as URL in walker where file.pathExtension.lowercased() == "png" {
                let relative = "PNG/" + file.resolvingSymlinksInPath().path.dropFirst(pngRoot.resolvingSymlinksInPath().path.count + 1)
                let target = (staged as NSString).appendingPathComponent(relative)
                try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                let data = try Data(contentsOf: file)
                try data.write(to: URL(fileURLWithPath: target))
                files.append(.init(path: relative, size: data.count, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
            }
        }
        guard !files.isEmpty else { throw CLIError("\(pack): the disk image has no PNG bezels") }
        let manifest = Manifest(pack: pack, url: url.absoluteString, etag: http?.value(forHTTPHeaderField: "ETag"),
                                files: files.sorted { $0.path < $1.path })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: URL(fileURLWithPath: (staged as NSString).appendingPathComponent("manifest.json")))
        let dir = (root as NSString).appendingPathComponent(pack)
        try? fm.removeItem(atPath: dir)
        try fm.moveItem(atPath: staged, toPath: dir)
        Log.success("\(pack): \(files.count) bezels, \(bytes / 1_000_000) MB downloaded in \(ms(since: start))")
        return Pack(dir: dir, files: manifest.files.map(\.path))
    }

    private static func attach(_ dmg: String, at mount: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount, dmg]
        let input = Pipe(), output = Pipe()
        p.standardInput = input; p.standardOutput = output; p.standardError = output
        try p.run()
        input.fileHandleForWriting.write("Y\n".data(using: .utf8)!)
        try? input.fileHandleForWriting.close()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CLIError("hdiutil could not mount \(dmg): \(text.suffix(400))") }
    }

    private static func detach(_ mount: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["detach", mount, "-force", "-quiet"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
}
