import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = Android.handOffIfNeeded(Array(CommandLine.arguments.dropFirst()))
let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0
Task {
    exitCode = await Command.run(arguments)
    semaphore.signal()
}
semaphore.wait()
exit(exitCode)
