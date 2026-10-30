import Foundation
@testable import swiftshot

/// The repository root (this file is Tests/swiftshotTests/TestSupport.swift).
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Shared/testdata/baseline: the fixtures both implementations are tested against.
let fixtures = repoRoot.appendingPathComponent("Shared/testdata/baseline")

/// A fresh temporary directory (canonical path), removed by the caller.
func temporaryDirectory(_ name: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name)-\(UUID().uuidString)").resolvingSymlinksInPath()
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

func bytes(_ url: URL) -> [UInt8] { (try? [UInt8](Data(contentsOf: url))) ?? [] }

func readJSON(_ url: URL) throws -> JSON { try JSON.parse(String(decoding: try Data(contentsOf: url), as: UTF8.self)) }

/// Every file under [dir] by its `/`-separated relative path.
func files(_ dir: URL) -> [String: URL] {
    var out: [String: URL] = [:]
    guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return out }
    let base = dir.resolvingSymlinksInPath().path + "/"
    for case let f as URL in e where (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
        let p = f.resolvingSymlinksInPath().path
        out[p.hasPrefix(base) ? String(p.dropFirst(base.count)) : f.lastPathComponent] = f
    }
    return out
}

func copyTree(_ from: URL, _ to: URL) throws {
    try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: from, to: to)
}

/// The fixture cases (directories with expected/result.json), sorted by name.
func fixtureCases() -> [URL] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []
    return names.sorted().map { fixtures.appendingPathComponent($0) }
        .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("expected/result.json").path) }
}
