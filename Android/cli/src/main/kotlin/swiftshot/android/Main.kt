package swiftshot.android

import java.io.File
import java.util.Locale
import kotlin.system.exitProcess

val VERSION: String = Options::class.java.`package`?.implementationVersion ?: "dev"

fun main(args: Array<String>) {
    if (args.firstOrNull() == "--version") { println("swiftshot $VERSION (android)"); return }
    val log = Log(args.contains("-v") || args.contains("--verbose"))
    exitProcess(cli(args.toList(), log))
}

/** The exit status of a command line. verify and record: 0/1/2 as the baseline format says, 64 for usage errors. */
fun cli(args: List<String>, log: Log): Int {
    if (Options.command(args) in setOf("verify", "record", "accept")) {
        val o = try { Options.parse(args) } catch (e: Exception) {
            if (e !is CliError && e !is IllegalArgumentException && e !is IllegalStateException) throw e
            log.error(e.message ?: "invalid option"); return 64
        }
        // accept renders nothing; its exit codes are its own (0 applied, 1 refused, 64 usage).
        if (o.command == "accept") return Accept.run(o.from, o.only, o.push, o.author, o.baselineDir(isFlutter(o)), log)
        return try {
            o.notes.forEach(log::warn)
            baselineCommand(o, log)
        } catch (e: CliError) {
            log.error(e.message ?: "failed"); 2
        } catch (e: IllegalArgumentException) {
            log.error(e.message ?: "invalid option"); 64
        } catch (e: IllegalStateException) {
            log.error(e.message ?: "failed"); 2
        }
    }
    return try {
        val o = Options.parse(args)
        o.notes.forEach(log::warn)
        when (o.command) {
            "devices" -> { devices(); 0 }
            "init", "auto-setup" -> Init.run(o, o.force, log)
            "emit-devices" -> {
                val jar = o.commandArgs.getOrNull(0) ?: "/Applications/Android Studio.app/Contents/plugins/android/lib/sdklib.jar"
                Devices.emit(File(jar), File(o.commandArgs.getOrNull(1) ?: "devices.json")); 0
            }
            // A Flutter project (pubspec.yaml on the Flutter SDK, no Gradle build at its root).
            else -> if (isFlutter(o)) Flutter(o, log).run() else Runner(o, log).run()
        }
    } catch (e: CliError) {
        log.error(e.message ?: "failed"); 1
    } catch (e: IllegalArgumentException) {
        log.error(e.message ?: "invalid option"); 1
    } catch (e: IllegalStateException) {
        log.error(e.message ?: "failed"); 1
    }
}

private fun isFlutter(o: Options) = !File(o.projectDir, "gradlew").isFile && Flutter.isProject(File(o.projectDir))

/**
 * verify and record: the normal run into the output directory (PNG, no frames), then the comparison with the
 * baseline or the recording into it. A run that fails as a whole (a build error) is a report with one error
 * without id: verify then exits 2 and reports no removals.
 */
private fun baselineCommand(o: Options, log: Log): Int {
    val flutter = isFlutter(o)
    val output = o.outputDir(flutter)
    File(output, "swiftshot-report.json").delete()
    try {
        if (flutter) Flutter(o, log).run() else Runner(o, log).run()
    } catch (e: CliError) {
        log.error(e.message ?: "failed")
        RunReport.writeFailure(output, if (flutter) "flutter" else "android", e.message ?: "the run failed", log.seconds)
    }
    if (!File(output, "swiftshot-report.json").isFile) RunReport.writeFailure(output, if (flutter) "flutter" else "android", "the run wrote no report", log.seconds)
    val baseline = o.baselineDir(flutter)
    return if (o.command == "record") Baseline.record(output, baseline, BaselineEnv.ci(), log)
    else Baseline.verify(output, baseline, o.reportDir(flutter), CompareConfig.from(o), BaselineEnv.detect(File(o.projectDir)), log)
}

private fun devices() {
    for ((type, list) in Devices.all.groupBy { it.type }) {
        println(type.replaceFirstChar { it.uppercase() })
        for (d in list) println(String.format(Locale.ROOT, "  %-34s %5d×%-5d px  %4d dpi  %5.0f×%-5.0f dp%s", d.name, d.width, d.height, d.density, d.widthDp, d.heightDp, if (d.round) "  round" else ""))
    }
    println("iPhone and iPad (Flutter projects)")
    for (d in AppleDevices.all) println(String.format(Locale.ROOT, "  %-34s %5d×%-5d pt  @%-4s safe area t%d b%d", d.name, d.width, d.height,
        if (d.scale % 1.0 == 0.0) "${d.scale.toInt()}x" else "${d.scale}x", d.top, d.bottom))
}
