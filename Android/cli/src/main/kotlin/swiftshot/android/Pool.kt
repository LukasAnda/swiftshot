package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/** One shot's outcome as the worker reported it. */
data class Result(val file: String, val ok: Boolean, val millis: Long = 0, val size: String = "", val error: String = "")

/**
 * Renderer processes for one module. Each loads layoutlib once and then renders whole groups (one
 * device, locale, appearance, font scale and mode) sent to it, so start-up is paid once per
 * process, not per screenshot. Processes run in parallel; a group goes to whichever is free.
 */
class Pool(val module: Module, private val java: File, private val workerJar: File, private val log: Log) {
    private class Proc(val n: Int, val process: Process, val stderr: StringBuffer, val drain: Thread) {
        val toWorker = process.outputStream.bufferedWriter()
        val fromWorker = process.inputStream.bufferedReader()
    }

    private val started = ConcurrentLinkedQueue<Proc>()
    private val count = AtomicInteger(0)
    val argfile: File by lazy { argfile() }

    /** Starts processes ahead of time (while Gradle builds): the JVM and layoutlib's patches load meanwhile. */
    fun warm(processes: Int) = repeat(processes) { started += spawn() }

    /** Stops processes that were started but not needed. */
    fun close() {
        while (true) {
            val p = started.poll() ?: break
            runCatching { p.toWorker.close() }
            p.process.waitFor()
        }
    }

    private fun spawn(): Proc {
        val n = count.getAndIncrement()
        val cds = File(Cache.root, "cds/${argfile.nameWithoutExtension}.jsa")
        cds.parentFile.mkdirs()
        // A class-data-sharing archive of this classpath makes every later start faster. Only
        // the first process writes it; the others read it once it exists.
        val share = when {
            n == 0 -> listOf("-XX:SharedArchiveFile=${cds.path}", "-XX:+AutoCreateSharedArchive")
            cds.isFile -> listOf("-XX:SharedArchiveFile=${cds.path}")
            else -> emptyList()
        }
        // Several renderers per core: each gets a couple of GC and JIT threads instead of one per core.
        val crowded = totalProcesses * 2 > Runtime.getRuntime().availableProcessors()
        val threads = if (crowded) listOf("-XX:ParallelGCThreads=2", "-XX:CICompilerCount=2") else emptyList()
        val cmd = listOf(java.path, "-Xmx1536m", "-XX:+UseParallelGC", "-XX:+EnableDynamicAgentLoading", "-Djava.awt.headless=true") + threads +
            share + listOf("-Xlog:cds=off", "-Xlog:cds+dynamic=off", "-Xshare:auto") +
            (System.getenv("SWIFTSHOT_WORKER_JVM_OPTS")?.split(' ')?.filter { it.isNotBlank() }?.map { it.replace("%n", n.toString()) } ?: emptyList()) +
            listOf("@${argfile.path}")
        val p = ProcessBuilder(cmd).redirectError(ProcessBuilder.Redirect.PIPE).start()
        val stderr = StringBuffer()
        val drain = thread(isDaemon = true) { p.errorStream.bufferedReader().forEachLine { stderr.appendLine(it); if (log.verbose) System.err.println("    [w$n] $it") } }
        return Proc(n, p, stderr, drain)
    }

    /** Set before spawning: renderers in all, so a busy machine gets lighter JVMs. */
    var totalProcesses = 1

    fun run(groups: List<Map<String, Any?>>, processes: Int, onResult: (Result) -> Unit): Long {
        val queue = ConcurrentLinkedQueue(groups)
        val readyMs = AtomicInteger(0)
        val threads = (0 until processes.coerceIn(1, groups.size.coerceAtLeast(1))).map {
            val proc = started.poll() ?: spawn()
            thread(name = "worker-${proc.n}") {
                try {
                    while (true) {
                        val group = queue.poll() ?: break
                        proc.toWorker.write(Json.write(group)); proc.toWorker.newLine(); proc.toWorker.flush()
                        val pending = (group["shots"] as List<*>).map { (it as Map<*, *>)["out"] as String }.toMutableSet()
                        while (true) {
                            val line = proc.fromWorker.readLine()
                            if (line == null) {
                                val why = proc.stderr.toString().lines().filter { it.isNotBlank() }.takeLast(8).joinToString(" | ")
                                pending.forEach { onResult(Result(it, false, error = "renderer exited: $why")) }
                                return@thread
                            }
                            val f = line.split('\t')
                            when (f[0]) {
                                "done" -> break
                                "ready" -> { readyMs.compareAndSet(0, f[1].toInt()); if (log.verbose) log.step("${module.path} renderer ${proc.n} ready in ${f[1]} ms (${f.getOrElse(2) { "" }})") }
                                "ok" -> { pending -= f[1]; onResult(Result(f[1], true, f[2].toLong(), f[3])) }
                                "error" -> { pending -= f[1]; onResult(Result(f[1], false, error = f.getOrElse(2) { "" })) }
                            }
                        }
                    }
                } finally {
                    runCatching { proc.toWorker.close() }
                    proc.process.waitFor()
                    proc.drain.join(1000)
                }
            }
        }
        threads.forEach { it.join() }
        close()
        return readyMs.get().toLong()
    }

    /** `java @file`: the classpath is far too long for a command line. */
    private fun argfile(): File {
        val extra = if (module.desktop) Skiko.runtime(module.classpath)?.let(::listOf) ?: emptyList() else module.bootClasspath
        // A library's generated R classes go first, ahead of its compile-time R jar.
        val rClasses = listOfNotNull(RClasses.jar(module))
        val cp = (listOf(workerJar) + rClasses + module.classDirs + module.classpath + extra).joinToString(File.pathSeparator) { it.absolutePath }
        val main = if (module.desktop) "swiftshot.android.desktop.DesktopWorkerKt" else "swiftshot.android.worker.WorkerKt"
        val hash = MessageDigest.getInstance("SHA-1").digest((cp + java.path + main).toByteArray()).joinToString("") { "%02x".format(it) }.take(16)
        val f = File(Cache.root, "args/$hash.args")
        f.parentFile.mkdirs()
        f.writeText("-cp \"${cp.replace("\\", "\\\\")}\"\n$main\n")
        return f
    }

}

/**
 * Skia's native library for the desktop renderer. A shared module's desktop classpath usually
 * has skiko-awt but not the runtime for this OS (that comes with `compose.desktop.currentOs` in the
 * app module), so the matching one is fetched from Maven Central once.
 */
object Skiko {
    fun runtime(classpath: List<File>): File? {
        if (classpath.any { it.name.startsWith("skiko-awt-runtime-") }) return null
        val awt = classpath.firstOrNull { it.name.startsWith("skiko-awt-") && it.name.endsWith(".jar") } ?: return null
        val version = awt.name.removePrefix("skiko-awt-").removeSuffix(".jar")
        val os = System.getProperty("os.name").lowercase()
        val arch = if (System.getProperty("os.arch").lowercase().let { it == "aarch64" || it == "arm64" }) "arm64" else "x64"
        val platform = when {
            os.contains("mac") -> "macos-$arch"
            os.contains("win") -> "windows-$arch"
            else -> "linux-$arch"
        }
        val name = "skiko-awt-runtime-$platform"
        val file = File(Cache.root, "skiko/$name-$version.jar")
        if (file.isFile) return file
        file.parentFile.mkdirs()
        val url = "https://repo1.maven.org/maven2/org/jetbrains/skiko/$name/$version/$name-$version.jar"
        val tmp = File(file.path + ".part")
        java.net.URI(url).toURL().openStream().use { input -> tmp.outputStream().use { input.copyTo(it) } }
        tmp.renameTo(file)
        return file
    }
}

object Java {
    /** A JDK 21+: --java-home, JAVA_HOME, Android Studio's bundled JBR, then `java` on PATH. */
    fun find(o: Options): File {
        val candidates = listOfNotNull(
            o.javaHome, System.getenv("SWIFTSHOT_JAVA_HOME"), System.getenv("JAVA_HOME"),
            "/Applications/Android Studio.app/Contents/jbr/Contents/Home",
            "${System.getProperty("user.home")}/Applications/Android Studio.app/Contents/jbr/Contents/Home",
            "/opt/android-studio/jbr", System.getProperty("java.home"),
        )
        for (home in candidates) {
            val bin = File(home, "bin/java")
            if (bin.canExecute() && version(bin) >= 21) return bin
        }
        throw CliError("Swiftshot needs JDK 21 or later to render Android previews. Set JAVA_HOME or pass --java-home.")
    }

    private fun version(java: File): Int = runCatching {
        val p = ProcessBuilder(java.path, "-version").redirectErrorStream(true).start()
        val text = p.inputStream.bufferedReader().readText(); p.waitFor()
        Regex("version \"(\\d+)").find(text)?.groupValues?.get(1)?.toInt() ?: 0
    }.getOrDefault(0)
}
