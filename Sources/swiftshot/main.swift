import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0
Task {
    do {
        let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
        Log.verbose = options.verbose
        if options.command == "init" { try await Setup.run(options); semaphore.signal(); return }
        if options.command == "frame" { try await FrameRun.command(options); semaphore.signal(); return }
        let runner = try Runner(options: options)
        switch options.command {
        case "list": try await runner.list()
        case "devices": try await runner.devices()
        case "calibrate": try await runner.calibrate()
        case "emit-table": try await runner.emitTable()
        default: try await runner.run()
        }
    } catch {
        FileHandle.standardError.write("\u{001B}[31merror:\u{001B}[0m \(error)\n".data(using: .utf8)!)
        exitCode = 1
    }
    semaphore.signal()
}
semaphore.wait()
exit(exitCode)
