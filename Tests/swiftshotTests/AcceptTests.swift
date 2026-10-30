import XCTest
import zlib
@testable import swiftshot

/// `accept` (docs/wiki/Baseline-format.md) in temporary git repositories, with a local bare remote for `--push`.
final class AcceptTests: XCTestCase {
    var tmp: URL!
    var repo: URL { tmp.appendingPathComponent("repo") }
    var baseline: URL { repo.appendingPathComponent("screenshots-baseline") }
    /// Neither the user's nor the system's git config: no signing, hooks or identity leak into the tests.
    let gitEnv = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]
    var console = Console(capture: true)
    var errors: String { console.text }

    override func setUp() { tmp = temporaryDirectory("swiftshot-accept"); console = Console(capture: true) }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    @discardableResult
    func git(_ dir: URL, _ args: String...) throws -> String {
        let r = Proc.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.com"] + args, cwd: dir, env: gitEnv)
        guard r.code == 0 else { throw CLIError("git \(args.joined(separator: " ")): \(r.out)\(r.err)") }
        return r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func head() throws -> String { try git(repo, "rev-parse", "HEAD") }
    func commits() throws -> Int { Int(try git(repo, "rev-list", "--count", "HEAD"))! }

    func repoWith(_ c: String) throws {
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git(repo, "init", "-q", "-b", "main")
        try copyTree(fixtures.appendingPathComponent("\(c)/baseline"), baseline)
        try "app\n".write(to: repo.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        try git(repo, "add", "-A")
        try git(repo, "commit", "-q", "-m", "initial")
    }

    /// [c]'s expected report directory, its manifest pointing at [commit].
    func report(_ c: String, commit: String? = nil, name: String? = nil) throws -> URL {
        let dir = tmp.appendingPathComponent("reports/\(name ?? c)")
        try copyTree(fixtures.appendingPathComponent("\(c)/expected"), dir)
        let sha = try commit ?? head()
        try setManifest(dir) { $0["commit"] = .string(sha) }
        return dir
    }

    func setManifest(_ dir: URL, _ change: (inout [String: JSON]) -> Void) throws {
        let f = dir.appendingPathComponent("manifest.json")
        var m = try readJSON(f).object!
        change(&m)
        try JSON.object(m).pretty().write(to: f, atomically: true, encoding: .utf8)
    }

    func images() throws -> [String: JSON] { try readJSON(baseline.appendingPathComponent("baseline.json"))["images"]!.object! }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func accept(_ from: URL..., only: Set<String>? = nil, push: Bool = false, author: String? = nil, token: String? = nil, urls: [String] = []) -> Int32 {
        Accept.run(from: from.map(\.path) + urls, only: only, push: push, author: author, baseline: baseline, log: console, token: token, gitEnv: gitEnv)
    }

    func status() throws -> String { try git(repo, "status", "--porcelain") }
    func statusLines() throws -> Set<String> { Set(try status().split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }) }

    func testAppliesChangedImageWithManifestFingerprintAndLeavesTheRestAlone() throws {
        try repoWith("changed-pixels")
        let settingsBefore = bytes(baseline.appendingPathComponent("en-US/Pixel 9-Settings.png"))
        let before = try images()
        let start = try commits()
        XCTAssertEqual(accept(try report("changed-pixels")), 0, errors)
        XCTAssertEqual(bytes(fixtures.appendingPathComponent("changed-pixels/output/en-US/Pixel 9-Home.png")), bytes(baseline.appendingPathComponent("en-US/Pixel 9-Home.png")))
        XCTAssertEqual(settingsBefore, bytes(baseline.appendingPathComponent("en-US/Pixel 9-Settings.png")))
        let after = try images()
        XCTAssertEqual(before["en-US/Pixel 9-Settings"], after["en-US/Pixel 9-Settings"])
        let home = after["en-US/Pixel 9-Home"]!
        XCTAssertEqual(home["local"], .bool(true))
        XCTAssertEqual(home["fingerprint"], .string("241d8bd3b005"))
        XCTAssertEqual(home.pretty(), JSON.object(["appearance": .string("light"), "device": .string("Pixel 9"), "fingerprint": .string("241d8bd3b005"), "fontScale": .int(1),
                                                  "language": .string("en-US"), "local": .bool(true), "module": .string(":app"), "platform": .string("android"), "preview": .string("Home")]).pretty())
        let text = try String(contentsOf: baseline.appendingPathComponent("baseline.json"), encoding: .utf8)
        XCTAssertEqual(try JSON.parse(text).pretty(), text)
        XCTAssertEqual(try commits(), start)
        XCTAssertEqual(try statusLines(), ["M screenshots-baseline/baseline.json", "M \"screenshots-baseline/en-US/Pixel 9-Home.png\""])
    }

    func testAcceptedImagesGetTheirOwnRuntimesBuild() throws {
        try repoWith("multi-runtime")
        let r = try report("multi-runtime")
        let id = "en-US/iPhone 17 Pro-Settings-iOS26.5"
        let resultFile = r.appendingPathComponent("result.json")
        var result = try readJSON(resultFile).object!
        result["screenshots"] = .array(result["screenshots"]!.array!.map { e in
            guard e["id"] == .string(id), var o = e.object else { return e }
            o["status"] = .string("changed"); return .object(o)
        })
        try JSON.object(result).pretty().write(to: resultFile, atomically: true, encoding: .utf8)
        try setManifest(r) { $0["ids"] = .object(["added": .array([]), "changed": .array([.string(id)]), "removed": .array([])]) }
        try FileManager.default.createDirectory(at: r.appendingPathComponent("images/new/en-US"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("multi-runtime/output/\(id).png"), to: r.appendingPathComponent("images/new/\(id).png"))
        XCTAssertEqual(accept(r), 0, errors)
        let fps = try readJSON(baseline.appendingPathComponent("baseline.json"))["fingerprints"]!
        let fp = fps[try images()[id]!["fingerprint"]!.string!]!
        XCTAssertEqual(fp["runtime"], .string("23F80"))
        XCTAssertNil(fp["runtimes"])
        XCTAssertEqual(fps[try images()["en-US/iPhone 17 Pro-Home-iOS26.0"]!["fingerprint"]!.string!]!["runtime"], .string("23A343"))
    }

    func testCiReportWritesNonLocalImages() throws {
        try repoWith("changed-pixels")
        let r = try report("changed-pixels")
        try setManifest(r) { $0["ci"] = .bool(true) }
        XCTAssertEqual(accept(r), 0, errors)
        XCTAssertEqual(try images()["en-US/Pixel 9-Home"]!["local"], .bool(false))
    }

    func testAddsNewImages() throws {
        try repoWith("added")
        XCTAssertEqual(accept(try report("added")), 0, errors)
        XCTAssertTrue(exists(baseline.appendingPathComponent("en-US/Pixel 9-Onboarding.png")))
        XCTAssertEqual(try images()["en-US/Pixel 9-Onboarding"]!["preview"], .string("Onboarding"))
    }

    func testDeletesRemovedImagesAndDropsUnreferencedFingerprints() throws {
        try repoWith("split-run-ios")
        try FileManager.default.removeItem(at: baseline.appendingPathComponent("en-US/iPhone 17 Pro-Home.png"))
        let bj = baseline.appendingPathComponent("baseline.json")
        var j = try readJSON(bj).object!
        var imgs = j["images"]!.object!; imgs["en-US/iPhone 17 Pro-Home"] = nil; j["images"] = .object(imgs)
        try JSON.object(j).pretty().write(to: bj, atomically: true, encoding: .utf8)
        try git(repo, "commit", "-qam", "one iOS image")
        XCTAssertEqual(accept(try report("split-run-ios")), 0, errors)
        XCTAssertFalse(exists(baseline.appendingPathComponent("en-US/iPhone 17 Pro-Settings.png")))
        XCTAssertNil(try images()["en-US/iPhone 17 Pro-Settings"])
        XCTAssertEqual(Set(try readJSON(bj)["fingerprints"]!.object!.keys), ["241d8bd3b005"])
    }

    func testErrorIdsAreNeverTouched() throws {
        try repoWith("render-error")
        let before = files(baseline).mapValues(bytes)
        XCTAssertEqual(accept(try report("render-error")), 0, errors)
        XCTAssertEqual(files(baseline).mapValues(bytes), before)
        XCTAssertTrue(errors.contains("Nothing to accept"))
    }

    func testOnlyRestrictsToTheGivenIds() throws {
        try repoWith("tolerance")
        let clockBefore = bytes(baseline.appendingPathComponent("en-US/Pixel 9-Clock Large.png"))
        XCTAssertEqual(accept(try report("tolerance"), only: ["en-US/Pixel 9-Settings"]), 0, errors)
        XCTAssertEqual(clockBefore, bytes(baseline.appendingPathComponent("en-US/Pixel 9-Clock Large.png")))
        XCTAssertEqual(bytes(fixtures.appendingPathComponent("tolerance/output/en-US/Pixel 9-Settings.png")), bytes(baseline.appendingPathComponent("en-US/Pixel 9-Settings.png")))
    }

    func testUnknownOnlyIdIsAUsageErrorAndWritesNothing() throws {
        try repoWith("tolerance")
        XCTAssertEqual(accept(try report("tolerance"), only: ["en-US/Pixel 9-Settings", "en-US/Pixel 9-Nope"]), 64)
        XCTAssertTrue(errors.contains("en-US/Pixel 9-Nope"))
        XCTAssertEqual(try status(), "")
    }

    func testTwoReportsFromSplitRunsApplyTogether() throws {
        try repoWith("split-run-android")
        XCTAssertEqual(accept(try report("split-run-android"), try report("split-run-ios")), 0, errors)
        XCTAssertEqual(bytes(fixtures.appendingPathComponent("split-run-android/output/en-US/Pixel 9-Settings.png")), bytes(baseline.appendingPathComponent("en-US/Pixel 9-Settings.png")))
        XCTAssertFalse(exists(baseline.appendingPathComponent("en-US/iPhone 17 Pro-Settings.png")))
        XCTAssertEqual(Set(try images().keys), ["en-US/Pixel 9-Home", "en-US/Pixel 9-Settings", "en-US/iPhone 17 Pro-Home"])
    }

    func testConflictingReportsAreAUsageError() throws {
        try repoWith("changed-pixels")
        let a = try report("changed-pixels", name: "a")
        let b = try report("changed-pixels", name: "b")
        let target = b.appendingPathComponent("images/new/en-US/Pixel 9-Home.png")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("changed-pixels/output/en-US/Pixel 9-Settings.png"), to: target)
        XCTAssertEqual(accept(a, b), 64)
        XCTAssertTrue(errors.contains("en-US/Pixel 9-Home"))
        XCTAssertEqual(try status(), "")
        XCTAssertEqual(accept(a, try report("changed-pixels", name: "c")), 0, errors)
    }

    func testStaleReportIsRefused() throws {
        try repoWith("changed-pixels")
        let old = try head()
        try "changed\n".write(to: repo.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        try git(repo, "commit", "-qam", "more work")
        XCTAssertEqual(accept(try report("changed-pixels", commit: old)), 1)
        XCTAssertTrue(errors.contains(old))
        XCTAssertTrue(errors.contains(try head()))
        XCTAssertEqual(try status(), "")
    }

    func testUnknownManifestCommitIsRefused() throws {
        try repoWith("changed-pixels")
        XCTAssertEqual(accept(try report("changed-pixels", commit: "0123456789abcdef0123456789abcdef01234567")), 1)
        XCTAssertEqual(try status(), "")
    }

    func testOnlyAcceptCommitsSinceTheReportAreAllowed() throws {
        try repoWith("split-run-android")
        let verified = try head()
        try FileManager.default.copyItem(at: baseline.appendingPathComponent("en-US/Pixel 9-Home.png"), to: baseline.appendingPathComponent("en-US/Pixel 9-Home-copy.png"))
        try git(repo, "add", "-A")
        try git(repo, "commit", "-q", "-m", "Update screenshot baseline (1 added)", "-m", "Swiftshot-Accept: 1111111111111111111111111111111111111111")
        XCTAssertEqual(accept(try report("split-run-android", commit: verified)), 0, errors)
        try git(repo, "checkout", "-q", "--", ".")
        try "x\n".write(to: repo.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        try git(repo, "commit", "-qam", "work")
        XCTAssertEqual(accept(try report("split-run-ios", commit: verified)), 1)
    }

    func remote() throws {
        let remote = tmp.appendingPathComponent("remote.git")
        try git(tmp, "init", "-q", "--bare", "-b", "main", remote.path)
        try git(repo, "remote", "add", "origin", remote.path)
        try git(repo, "push", "-q", "-u", "origin", "main")
    }

    func testPushCommitsOnceAsTheBotAndPushes() throws {
        try repoWith("split-run-android")
        try remote()
        let verified = try head()
        XCTAssertEqual(accept(try report("split-run-android"), try report("split-run-ios"), push: true), 0, errors)
        XCTAssertEqual(try git(repo, "rev-list", "--count", "\(verified)..HEAD"), "1")
        XCTAssertEqual(try git(repo, "log", "-1", "--format=%an <%ae>"), "swiftshot <swiftshot@users.noreply.github.com>")
        XCTAssertEqual(try git(repo, "log", "-1", "--format=%cn <%ce>"), "swiftshot <swiftshot@users.noreply.github.com>")
        XCTAssertEqual(try git(repo, "log", "-1", "--format=%s"), "Update screenshot baseline (1 changed, 1 removed)")
        XCTAssertEqual(try git(repo, "log", "-1", "--format=%(trailers:key=Swiftshot-Accept,valueonly)"), verified)
        XCTAssertEqual(try git(tmp.appendingPathComponent("remote.git"), "rev-parse", "main"), try head())
        XCTAssertEqual(try status(), "")
        XCTAssertEqual(accept(try report("split-run-android", commit: verified, name: "again"), push: true), 0, errors)
        XCTAssertEqual(try git(repo, "rev-list", "--count", "\(verified)..HEAD"), "1")
    }

    func testAuthorOverride() throws {
        try repoWith("added")
        let remote = tmp.appendingPathComponent("remote.git")
        try git(tmp, "init", "-q", "--bare", "-b", "main", remote.path)
        try git(repo, "remote", "add", "origin", remote.path)
        try git(repo, "push", "-q", "origin", "main")
        XCTAssertEqual(accept(try report("added"), push: true, author: "Release Bot <bot@example.com>"), 0, errors)
        XCTAssertEqual(try git(repo, "log", "-1", "--format=%an <%ae>"), "Release Bot <bot@example.com>")
        XCTAssertEqual(try git(repo, "log", "-1", "--format=%s"), "Update screenshot baseline (1 added)")
        XCTAssertEqual(try git(remote, "rev-parse", "main"), try head())
        XCTAssertEqual(accept(try report("added", name: "bad"), push: true, author: "no email"), 64)
    }

    func testCommitMessageCounts() {
        XCTAssertEqual(Accept.message(changed: 3, added: 1, removed: 0), "Update screenshot baseline (3 changed, 1 added)")
        XCTAssertEqual(Accept.message(changed: 0, added: 0, removed: 2), "Update screenshot baseline (2 removed)")
        XCTAssertEqual(Accept.message(changed: 1, added: 2, removed: 3), "Update screenshot baseline (1 changed, 2 added, 3 removed)")
    }

    func testNothingToApplyWithPushMakesNoCommit() throws {
        try repoWith("unchanged")
        let start = try commits()
        XCTAssertEqual(accept(try report("unchanged"), push: true), 0, errors)
        XCTAssertEqual(try commits(), start)
    }

    func testReportIdsMustStayInsideTheBaseline() throws {
        try repoWith("changed-pixels")
        let r = try report("changed-pixels")
        try setManifest(r) { $0["ids"] = .object(["added": .array([]), "changed": .array([.string("../escape")]), "removed": .array([])]) }
        XCTAssertEqual(accept(r), 64)
        XCTAssertEqual(try status(), "")
    }

    // MARK: zips

    func zip(_ dir: URL, _ out: URL, prefix: String = "", extra: [(String, [UInt8])] = []) throws -> URL {
        var w = ZipWriter()
        for (path, f) in files(dir).sorted(by: { $0.key < $1.key }) { w.add(prefix + path, bytes(f)) }
        for (name, data) in extra { w.add(name, data) }
        try Data(w.finish()).write(to: out)
        return out
    }

    func testAcceptsAZipOfTheReport() throws {
        try repoWith("changed-pixels")
        XCTAssertEqual(accept(try zip(try report("changed-pixels"), tmp.appendingPathComponent("report.zip"))), 0, errors)
        XCTAssertEqual(bytes(fixtures.appendingPathComponent("changed-pixels/output/en-US/Pixel 9-Home.png")), bytes(baseline.appendingPathComponent("en-US/Pixel 9-Home.png")))
    }

    func testAcceptsAZipWithOneTopLevelDirectory() throws {
        try repoWith("changed-pixels")
        XCTAssertEqual(accept(try zip(try report("changed-pixels"), tmp.appendingPathComponent("report.zip"), prefix: "screenshots-report/")), 0, errors)
    }

    func testZipSlipIsRejected() throws {
        try repoWith("changed-pixels")
        let z = try zip(try report("changed-pixels"), tmp.appendingPathComponent("report.zip"), extra: [("../../evil.txt", Array("x".utf8))])
        XCTAssertEqual(accept(z), 64)
        XCTAssertFalse(exists(tmp.appendingPathComponent("evil.txt")))
        XCTAssertFalse(exists(tmp.deletingLastPathComponent().appendingPathComponent("evil.txt")))
        XCTAssertTrue(errors.contains("evil.txt"))
        XCTAssertEqual(try status(), "")
    }

    func testSymlinkInZipIsRejected() throws {
        try repoWith("changed-pixels")
        var w = ZipWriter()
        for (path, f) in files(try report("changed-pixels")) { w.add(path, bytes(f)) }
        w.add("link", Array("/etc/passwd".utf8), unixMode: 0o120777)
        let z = tmp.appendingPathComponent("report.zip")
        try Data(w.finish()).write(to: z)
        XCTAssertEqual(accept(z), 64)
        XCTAssertTrue(errors.contains("link"))
    }

    func testDamagedZipsAreUsageErrors() throws {
        try repoWith("changed-pixels")
        let good = bytes(try zip(try report("changed-pixels"), tmp.appendingPathComponent("good.zip")))
        let cut = tmp.appendingPathComponent("cut.zip"); try Data(good.prefix(good.count / 2)).write(to: cut)
        XCTAssertEqual(accept(cut), 64)
        let junk = tmp.appendingPathComponent("junk.zip"); try Data("PK not really".utf8).write(to: junk)
        XCTAssertEqual(accept(junk), 64)
        var bad = good
        for k in 60..<120 { bad[k] ^= 0x5a }
        let badURL = tmp.appendingPathComponent("bad.zip"); try Data(bad).write(to: badURL)
        XCTAssertEqual(accept(badURL), 64)
        var named = bytes(try zip(try report("changed-pixels", name: "n"), tmp.appendingPathComponent("named.zip"), extra: [("aXb", [1])]))
        for k in 0...(named.count - 3) where named[k] == 97 && named[k + 1] == 88 && named[k + 2] == 98 { named[k + 1] = 0xff }
        let namedURL = tmp.appendingPathComponent("named.zip"); try Data(named).write(to: namedURL)
        XCTAssertEqual(accept(namedURL), 64)
        XCTAssertEqual(try status(), "")
    }

    func testTooManyEntriesOrTooLargeAreRejected() throws {
        // The limits themselves (200 000 entries, 2 GB) are too large for a test; the reader checks them first.
        XCTAssertEqual(Zip.maxEntries, 200_000)
        XCTAssertEqual(Zip.maxBytes, 2 * 1024 * 1024 * 1024)
        let dir = tmp.appendingPathComponent("big")
        var w = ZipWriter()
        w.add("a.txt", [UInt8](repeating: 65, count: 5000))
        let z = tmp.appendingPathComponent("big.zip"); try Data(w.finish()).write(to: z)
        XCTAssertThrowsError(try Zip.extract(z, to: dir, label: "big.zip", maxBytes: 4000)) { XCTAssertTrue("\($0)".contains("larger than"), "\($0)") }
        XCTAssertThrowsError(try Zip.extract(z, to: tmp.appendingPathComponent("big2"), label: "big.zip", maxEntries: 0)) { XCTAssertTrue("\($0)".contains("entries"), "\($0)") }
    }

    // Crafted zips whose sizes and offsets overflow or overrun: a usage error, never a crash.

    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }
    private func le32(_ v: UInt64) -> [UInt8] { (0..<4).map { UInt8(v >> (8 * UInt64($0)) & 255) } }
    private func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8(v >> (8 * UInt64($0)) & 255) } }

    /// A zip64 end record (at `z64At`) with the given central directory size and offset, then its locator and the end record.
    private func zip64End(prefix: [UInt8], count: UInt64, size: UInt64, offset: UInt64) -> [UInt8] {
        let z64At = UInt64(prefix.count)
        let z64 = le32(0x0606_4b50) + le64(44) + le16(45) + le16(45) + le32(0) + le32(0) + le64(count) + le64(count) + le64(size) + le64(offset)
        let locator = le32(0x0706_4b50) + le32(0) + le64(z64At) + le32(1)
        let end = le32(0x0605_4b50) + le16(0) + le16(0) + le16(0xffff) + le16(0xffff) + le32(0xffff_ffff) + le32(0xffff_ffff) + le16(0)
        return prefix + z64 + locator + end
    }

    /// A central directory entry; `extra` is its extra field.
    private func centralEntry(name: String, compressed: UInt64, size: UInt64, offset: UInt64, extra: [UInt8]) -> [UInt8] {
        let n = Array(name.utf8)
        return le32(0x0201_4b50) + le16(45) + le16(45) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(compressed) + le32(size)
            + le16(n.count) + le16(extra.count) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + n + extra
    }

    private func assertUsageError(_ data: [UInt8], _ what: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let z = tmp.appendingPathComponent("crafted.zip")
        try Data(data).write(to: z)
        XCTAssertThrowsError(try Zip.extract(z, to: tmp.appendingPathComponent("out-\(UUID().uuidString)"), label: "crafted.zip"), what, file: file, line: line) {
            XCTAssertTrue($0 is UsageError, "\(what): \($0)", file: file, line: line)
        }
    }

    func testZip64CentralDirectorySizeThatOverflows() throws {
        // offset + size wraps around UInt64.
        try assertUsageError(zip64End(prefix: [], count: 1, size: UInt64.max - 4, offset: 10), "huge central directory size")
    }

    func testZip64EntrySizeThatOverflowsPastItsData() throws {
        // A real local header at 0; the zip64 extra gives a compressed size that wraps start + size.
        let local = le32(0x0403_4b50) + le16(45) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0) + le32(0) + le16(1) + le16(0) + Array("a".utf8)
        let extra = le16(1) + le16(16) + le64(1) + le64(UInt64.max - 8)
        let cd = centralEntry(name: "a", compressed: 0xffff_ffff, size: 0xffff_ffff, offset: 0, extra: extra)
        try assertUsageError(zip64End(prefix: local + cd, count: 1, size: UInt64(cd.count), offset: UInt64(local.count)), "huge entry size")
        // And a local header offset near UInt64.max.
        let far = centralEntry(name: "a", compressed: 1, size: 1, offset: 0xffff_ffff, extra: le16(1) + le16(8) + le64(UInt64.max - 2))
        try assertUsageError(zip64End(prefix: local + far, count: 1, size: UInt64(far.count), offset: UInt64(local.count)), "huge local offset")
    }

    func testZip64ExtraFieldLongerThanTheExtraArea() throws {
        // The zip64 field says 24 bytes, but the entry's extra area (and the central directory) ends after 8.
        let extra = le16(1) + le16(24) + le64(5)
        let cd = centralEntry(name: "a", compressed: 0xffff_ffff, size: 0xffff_ffff, offset: 0xffff_ffff, extra: extra)
        try assertUsageError(zip64End(prefix: cd, count: 1, size: UInt64(cd.count), offset: 0), "zip64 field past the extra area")
    }

    func testBaselineJsonIsWrittenWithoutLeftovers() throws {
        try repoWith("changed-pixels")
        XCTAssertEqual(accept(try report("changed-pixels")), 0, errors)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: baseline.path).sorted(), ["baseline.json", "en-US"])
    }

    func testMalformedBaselineJsonIsAUsageErrorNamingIt() throws {
        try repoWith("changed-pixels")
        try #"{"fingerprints": {}, "images": [], "schema": 1}"#.write(to: baseline.appendingPathComponent("baseline.json"), atomically: true, encoding: .utf8)
        try git(repo, "commit", "-qam", "broken")
        XCTAssertEqual(accept(try report("changed-pixels")), 64)
        XCTAssertTrue(errors.contains("baseline.json"))
        XCTAssertEqual(try status(), "")
    }

    func testMalformedResultJsonIsAUsageErrorNamingIt() throws {
        try repoWith("changed-pixels")
        let r = try report("changed-pixels")
        try "[1]".write(to: r.appendingPathComponent("result.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(accept(r), 64)
        XCTAssertTrue(errors.contains("result.json"))
    }

    func testPushCommitsOnlyWhatAcceptWrote() throws {
        try repoWith("changed-pixels")
        try remote()
        let verified = try head()
        let settings = baseline.appendingPathComponent("en-US/Pixel 9-Settings.png")
        try Data(bytes(settings) + [1]).write(to: settings)
        try Data([2]).write(to: baseline.appendingPathComponent("en-US/Pixel 9-Stray.png"))
        XCTAssertEqual(accept(try report("changed-pixels"), push: true), 0, errors)
        XCTAssertEqual(try git(repo, "rev-list", "--count", "\(verified)..HEAD"), "1")
        XCTAssertEqual(Set(try git(repo, "-c", "core.quotePath=false", "show", "--name-only", "--format=", "HEAD").split(separator: "\n").map(String.init)),
                       ["screenshots-baseline/baseline.json", "screenshots-baseline/en-US/Pixel 9-Home.png"])
        XCTAssertEqual(try statusLines(), ["M \"screenshots-baseline/en-US/Pixel 9-Settings.png\"", "?? \"screenshots-baseline/en-US/Pixel 9-Stray.png\""])
        XCTAssertEqual(accept(try report("changed-pixels", commit: verified, name: "again"), push: true), 0, errors)
        XCTAssertEqual(try git(repo, "rev-list", "--count", "\(verified)..HEAD"), "1")
    }

    func testPushWithARemovedImageGitNeverTracked() throws {
        try repoWith("removed")
        try remote()
        try git(repo, "rm", "-q", "--cached", "screenshots-baseline/en-US/Pixel 9-Legacy.png")
        try git(repo, "commit", "-qm", "untrack")
        try git(repo, "push", "-q")
        XCTAssertEqual(accept(try report("removed"), push: true), 0, errors)
        XCTAssertEqual(try git(repo, "show", "--name-only", "--format=", "HEAD"), "screenshots-baseline/baseline.json")
    }

    // MARK: downloads

    func testDownloadsAZipWithTheArtifactToken() throws {
        try repoWith("changed-pixels")
        let data = bytes(try zip(try report("changed-pixels"), tmp.appendingPathComponent("report.zip")))
        let server = try TestHTTPServer { request in
            switch request.path {
            case "/artifact.zip": return (200, [:], data)
            case "/redirect": return (302, ["Location": "http://localhost:\(request.port)/artifact.zip"], [])
            default: return (404, [:], [])
            }
        }
        defer { server.stop() }
        XCTAssertEqual(accept(token: "secret", urls: ["http://127.0.0.1:\(server.port)/artifact.zip"]), 0, errors)
        XCTAssertEqual(server.authorizations, ["Bearer secret"])
        try git(repo, "checkout", "-q", "--", ".")
        server.authorizations = []
        XCTAssertEqual(accept(token: "secret", urls: ["http://127.0.0.1:\(server.port)/redirect"]), 0, errors)
        // Another host (localhost, not 127.0.0.1): the token stays behind.
        XCTAssertEqual(server.authorizations, ["Bearer secret", ""])
        XCTAssertEqual(accept(urls: ["http://127.0.0.1:\(server.port)/missing.zip"]), 64)
        XCTAssertFalse(errors.contains("secret"))
    }

    // MARK: options

    func testAcceptOptions() throws {
        let config = tmp.appendingPathComponent("empty.json"); try "{}".write(to: config, atomically: true, encoding: .utf8)
        let o = try Options.parse(["--config", config.path, "accept", "--from", "a", "--from", "b.zip", "--only", "x,y", "--only", "z", "--push", "--author", "A <a@b.c>"])
        XCTAssertEqual(o.command, "accept")
        XCTAssertEqual(o.from, ["a", "b.zip"])
        XCTAssertEqual(o.only, ["x", "y", "z"])
        XCTAssertTrue(o.push)
        XCTAssertEqual(o.author, "A <a@b.c>")
        XCTAssertThrowsError(try Options.parse(["--config", config.path, "accept"])) { XCTAssertTrue($0 is UsageError) }
        XCTAssertThrowsError(try Options.parse(["--config", config.path, "run", "--push"]))
    }
}

// MARK: helpers

/// Writes a zip (deflated entries, or stored when [stored]); [unixMode] marks an entry made by Unix with that mode.
struct ZipWriter {
    private var body: [UInt8] = []
    private var central: [UInt8] = []
    private var count = 0

    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }
    private func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }

    private func deflateRaw(_ data: [UInt8]) -> [UInt8] {
        var s = z_stream()
        deflateInit2_(&s, 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        var out = [UInt8](repeating: 0, count: Int(deflateBound(&s, uLong(data.count))) + 16)
        var input = data
        let n: Int = input.withUnsafeMutableBufferPointer { inp in
            out.withUnsafeMutableBufferPointer { o in
                s.next_in = inp.baseAddress; s.avail_in = uInt(inp.count)
                s.next_out = o.baseAddress; s.avail_out = uInt(o.count)
                deflate(&s, Z_FINISH)
                return Int(s.total_out)
            }
        }
        deflateEnd(&s)
        return Array(out[0..<n])
    }

    mutating func add(_ name: String, _ data: [UInt8], unixMode: UInt32? = nil, stored: Bool = false) {
        let nameBytes = Array(name.utf8)
        let crc = UInt32(crc32(0, data, uInt(data.count)))
        let packed = stored ? data : deflateRaw(data)
        let method = stored ? 0 : 8
        let offset = UInt32(body.count)
        body += le32(0x0403_4b50) + le16(20) + le16(0x800) + le16(method) + le16(0) + le16(0) + le32(crc) + le32(UInt32(packed.count)) + le32(UInt32(data.count))
            + le16(nameBytes.count) + le16(0) + nameBytes + packed
        let madeBy = unixMode == nil ? 20 : (3 << 8 | 20)
        central += le32(0x0201_4b50) + le16(madeBy) + le16(20) + le16(0x800) + le16(method) + le16(0) + le16(0) + le32(crc) + le32(UInt32(packed.count)) + le32(UInt32(data.count))
            + le16(nameBytes.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32((unixMode ?? 0) << 16) + le32(offset) + nameBytes
        count += 1
    }

    func finish() -> [UInt8] {
        body + central + le32(0x0605_4b50) + le16(0) + le16(0) + le16(count) + le16(count) + le32(UInt32(central.count)) + le32(UInt32(body.count)) + le16(0)
    }
}

/// A one-thread HTTP/1.0 server on 127.0.0.1 for the download tests; records each request's Authorization ("" when none).
final class TestHTTPServer {
    struct Request { let path: String; let port: Int }
    let port: Int
    private let fd: Int32
    private let lock = NSLock()
    private var _auth: [String] = []
    var authorizations: [String] {
        get { lock.lock(); defer { lock.unlock() }; return _auth }
        set { lock.lock(); _auth = newValue; lock.unlock() }
    }

    init(handler: @escaping (Request) -> (Int, [String: String], [UInt8])) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 8) == 0 else { throw CLIError("test server: bind failed") }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        self.fd = fd
        port = Int(UInt16(bigEndian: addr.sin_port))
        let listener = fd, port = self.port
        Thread.detachNewThread { [weak self] in
            while true {
                let c = accept(listener, nil, nil)
                if c < 0 { return }
                var request = [UInt8]()
                var buf = [UInt8](repeating: 0, count: 4096)
                while !request.containsHeaderEnd {
                    let n = read(c, &buf, buf.count)
                    if n <= 0 { break }
                    request += buf[0..<n]
                }
                let text = String(decoding: request, as: UTF8.self)
                let lines = text.components(separatedBy: "\r\n")
                let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let auth = lines.first { $0.lowercased().hasPrefix("authorization:") }.map { String($0.dropFirst("authorization:".count)).trimmingCharacters(in: .whitespaces) } ?? ""
                if path != "/missing.zip" { self?.lock.lock(); self?._auth.append(auth); self?.lock.unlock() }
                let (code, headers, body) = handler(Request(path: path, port: port))
                var head = "HTTP/1.1 \(code) X\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
                for (k, v) in headers { head += "\(k): \(v)\r\n" }
                let out = Array((head + "\r\n").utf8) + body
                var sent = 0
                while sent < out.count {
                    let n = out[sent...].withUnsafeBufferPointer { write(c, $0.baseAddress, $0.count) }
                    if n <= 0 { break }
                    sent += n
                }
                close(c)
            }
        }
    }

    func stop() { shutdown(fd, SHUT_RDWR); close(fd) }
}

private extension Array where Element == UInt8 {
    var containsHeaderEnd: Bool {
        guard count >= 4 else { return false }
        for i in 0...(count - 4) where self[i] == 13 && self[i + 1] == 10 && self[i + 2] == 13 && self[i + 3] == 10 { return true }
        return false
    }
}
