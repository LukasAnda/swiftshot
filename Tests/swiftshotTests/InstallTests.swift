import XCTest

final class InstallTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Run by name from PATH through a symlink, as Homebrew installs it: the agents are found next
    /// to the real binary, not in the current directory.
    func testFindsAgentsWhenRunFromPathSymlink() throws {
        let tool = Self.root.appendingPathComponent("bin/swiftshot")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: tool.path), "run `make` first")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-path-\(ProcessInfo.processInfo.processIdentifier)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("bin/swiftshot"), withDestinationURL: tool)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "swiftshot devices"]
        p.currentDirectoryURL = dir
        p.environment = ["PATH": dir.appendingPathComponent("bin").path + ":/usr/bin:/bin", "HOME": NSHomeDirectory()]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        XCTAssertFalse(out.contains("not found"), out)
        XCTAssertEqual(p.terminationStatus, 0, out)
    }
}
