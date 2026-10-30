import Foundation

/// A command line, start to exit status. verify and record: 0/1/2 as docs/wiki/Baseline-format.md says, 64 for
/// usage errors; accept: 0 applied, 1 refused, 64 usage or invalid report; every other command 0 or 1.
enum Command {
    static func run(_ arguments: [String]) async -> Int32 {
        let baselineCommand = ["verify", "record", "accept"].contains(Options.command(arguments))
        let options: Options
        do { options = try Options.parse(arguments) } catch {
            fail(error)
            return baselineCommand || error is UsageError ? 64 : 1
        }
        Log.verbose = options.verbose
        switch options.command {
        case "accept":
            return Accept.run(from: options.from, only: options.only, push: options.push, author: options.author,
                              baseline: URL(fileURLWithPath: options.baselineDirectory), log: Console())
        case "verify", "record":
            return await baseline(options)
        default:
            do {
                if options.command == "init" { try await Setup.run(options); return 0 }
                if options.command == "frame" { try await FrameRun.command(options); return 0 }
                let runner = try Runner(options: options)
                switch options.command {
                case "list": try await runner.list()
                case "devices": try await runner.devices()
                case "calibrate": try await runner.calibrate()
                case "emit-table": try await runner.emitTable()
                default: try await runner.run()
                }
                return 0
            } catch {
                fail(error)
                return 1
            }
        }
    }

    static func fail(_ error: Error) {
        FileHandle.standardError.write("\u{001B}[31merror:\u{001B}[0m \(error)\n".data(using: .utf8)!)
    }

    /// verify and record: the normal run into the output directory (PNG, no frames), then the comparison with the
    /// baseline or the recording into it. A run that fails as a whole (a build error) is a report with one error
    /// without id: verify then exits 2 and reports no removals. `render` is the run (tests replace it).
    static func baseline(_ options: Options, render: (Options) async throws -> Void = { try await Runner(options: $0).run() }) async -> Int32 {
        let output = URL(fileURLWithPath: options.output).standardizedFileURL
        let report = output.appendingPathComponent("swiftshot-report.json")
        try? FileManager.default.removeItem(at: report)
        do {
            try await render(options)
        } catch {
            Log.failure("\(error)")
            if !FileManager.default.fileExists(atPath: report.path) { try? Report.writeFailure(to: output.path, message: "\(error)") }
        }
        if !FileManager.default.fileExists(atPath: report.path) { try? Report.writeFailure(to: output.path, message: "the run wrote no report") }
        let baseline = URL(fileURLWithPath: options.baselineDirectory).standardizedFileURL
        let reportDir = URL(fileURLWithPath: options.reportPath)
        do {
            if options.command == "record" { return try Baseline.record(output: output, baseline: baseline, ci: BaselineEnv.ci(), log: Console()) }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            return try Baseline.verify(output: output, baseline: baseline, report: reportDir, config: CompareConfig.from(options),
                                       env: BaselineEnv.detect(cwd), log: Console())
        } catch {
            // No result: nothing of an earlier verify may stay behind to be read as this one's.
            if options.command == "verify" { try? BaselineReport.clear(reportDir) }
            fail(error)
            return error is UsageError ? 64 : 2
        }
    }
}
