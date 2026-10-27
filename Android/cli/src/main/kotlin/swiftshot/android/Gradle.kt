package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.util.zip.ZipFile

/** What the init script reports for one module (see swiftshot-android.init.gradle). */
class Module(val json: Map<*, *>) {
    val path = json["module"] as String
    val packageName = json["packageName"] as String
    val wear = json["wear"] as Boolean
    val classDirs = (json["classDirs"] as List<*>).map { File(it as String) }
    val classpath = (json["classpath"] as List<*>).map { File(it as String) }
    /** The SDK's android.jar: classes layoutlib leaves out (android.os.Build). Last, so layoutlib wins. */
    val bootClasspath = (json["bootClasspath"] as List<*>? ?: emptyList<Any>()).map { File(it as String) }
    val layoutlibRuntime = File(json["layoutlibRuntime"] as String)
    val layoutlibResources = File(json["layoutlibResources"] as String)
    val hasTooling get() = classpath.any { it.path.contains("ui-tooling") && !it.path.contains("ui-tooling-preview") && !it.path.contains("ui-tooling-data") } ||
        (json["components"] as List<*>).any { (it as String).startsWith("androidx.compose.ui:ui-tooling:") || (it as String).startsWith("androidx.compose.ui:ui-tooling-android:") }

    fun environment(appTestDir: File) = linkedMapOf(
        "appTestDir" to appTestDir.path,
        "packageName" to packageName,
        "compileSdk" to json["compileSdk"],
        "targetSdk" to (json["targetSdk"] ?: json["compileSdk"]),
        "resourcePackageNames" to json["resourcePackageNames"],
        "localResourceDirs" to json["localResourceDirs"],
        "moduleResourceDirs" to json["moduleResourceDirs"],
        "libraryResourceDirs" to json["libraryResourceDirs"],
        "assetDirs" to json["assetDirs"],
        "libraryAssetDirs" to json["libraryAssetDirs"],
    )
}

object Gradle {
    /** Runs `swiftshotPrepare` in the project and returns the modules it described. */
    fun prepare(o: Options, log: Log): List<Module> {
        val root = File(o.projectDir).absoluteFile.normalize()
        val gradlew = File(root, "gradlew")
        require(gradlew.isFile) { "No gradlew in $root. Pass --project-dir or run from the Gradle project's root." }
        val init = File.createTempFile("swiftshot-android", ".init.gradle").apply {
            deleteOnExit()
            writeText(Gradle::class.java.getResourceAsStream("/swiftshot-android.init.gradle")!!.bufferedReader().readText())
        }
        val tasks = if (o.modules.isEmpty()) listOf("swiftshotPrepare") else o.modules.map { "${it.trimEnd(':')}:swiftshotPrepare" }
        val cmd = listOf(gradlew.path, "-I", init.path) + tasks +
            listOf("-Pswiftshot.variant=${o.variant}", "--console=plain", "-q", "--no-configuration-cache") + o.gradleArgs
        log.step("Building ${tasks.joinToString(" ")} (${o.variant})…")
        val p = ProcessBuilder(cmd).directory(root).redirectErrorStream(true).apply {
            o.javaHome?.let { environment()["JAVA_HOME"] = it }
        }.start()
        val modules = mutableListOf<File>()
        val output = StringBuilder()
        p.inputStream.bufferedReader().forEachLine { line ->
            if (line.startsWith("swiftshot-module ")) modules += File(line.removePrefix("swiftshot-module "))
            else { output.appendLine(line); if (o.verbose) System.err.println("  $line") }
        }
        val status = p.waitFor()
        if (status != 0) throw CliError("Gradle failed (exit $status):\n${output.toString().trim().lines().takeLast(40).joinToString("\n")}")
        if (modules.isEmpty()) throw CliError("No Android application or library module found in $root.")
        return modules.map { Module(Json.parse(it.readText()) as Map<*, *>) }
    }

    /** layoutlib's runtime and resources jars, unpacked once into the cache. */
    fun unpack(jar: File): File {
        val dir = File(Cache.root, "layoutlib/${jar.nameWithoutExtension}")
        val marker = File(dir, ".complete")
        if (marker.isFile) return dir
        dir.deleteRecursively()
        dir.mkdirs()
        ZipFile(jar).use { z ->
            for (e in z.entries()) {
                val f = File(dir, e.name).normalize()
                require(f.path.startsWith(dir.path)) { "bad entry ${e.name}" }
                if (e.isDirectory) { f.mkdirs(); continue }
                f.parentFile.mkdirs()
                z.getInputStream(e).use { input -> f.outputStream().use { input.copyTo(it) } }
                if (f.path.contains("/bin/") || f.name.endsWith(".so") || f.name.endsWith(".dylib")) f.setExecutable(true)
            }
        }
        marker.writeText("ok")
        return dir
    }
}

object Cache {
    val root: File by lazy {
        val env = System.getenv("SWIFTSHOT_CACHE")
        val home = System.getProperty("user.home")
        File(env ?: if (System.getProperty("os.name").lowercase().contains("mac")) "$home/Library/Caches/swiftshot/android" else (System.getenv("XDG_CACHE_HOME") ?: "$home/.cache") + "/swiftshot/android")
    }
}

class CliError(message: String) : Exception(message)
