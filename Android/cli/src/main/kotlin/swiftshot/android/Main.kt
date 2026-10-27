package swiftshot.android

import java.io.File
import java.util.Locale
import kotlin.system.exitProcess

val VERSION: String = Options::class.java.`package`?.implementationVersion ?: "dev"

fun main(args: Array<String>) {
    if (args.firstOrNull() == "--version") { println("swiftshot $VERSION (android)"); return }
    val log = Log(args.contains("-v") || args.contains("--verbose"))
    val status = try {
        val o = Options.parse(args.toList())
        o.notes.forEach(log::warn)
        when (o.command) {
            "devices" -> { devices(); 0 }
            "init", "auto-setup" -> Init.run(o, o.force, log)
            "emit-devices" -> {
                val jar = o.commandArgs.getOrNull(0) ?: "/Applications/Android Studio.app/Contents/plugins/android/lib/sdklib.jar"
                Devices.emit(File(jar), File(o.commandArgs.getOrNull(1) ?: "devices.json")); 0
            }
            // A Flutter project (pubspec.yaml on the Flutter SDK, no Gradle build at its root).
            else -> if (!File(o.projectDir, "gradlew").isFile && Flutter.isProject(File(o.projectDir))) Flutter(o, log).run() else Runner(o, log).run()
        }
    } catch (e: CliError) {
        log.error(e.message ?: "failed"); 1
    } catch (e: IllegalArgumentException) {
        log.error(e.message ?: "invalid option"); 1
    } catch (e: IllegalStateException) {
        log.error(e.message ?: "failed"); 1
    }
    exitProcess(status)
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
