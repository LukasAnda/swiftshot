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
class Pool(private val module: Module, private val java: File, private val workerJar: File, private val log: Log) {
    fun run(groups: List<Map<String, Any?>>, processes: Int, onResult: (Result) -> Unit): Long {
        val queue = ConcurrentLinkedQueue(groups)
        val readyMs = AtomicInteger(0)
        val argfile = argfile()
        val threads = (0 until processes.coerceIn(1, groups.size.coerceAtLeast(1))).map { n ->
            thread(name = "worker-$n") {
                val cds = File(Cache.root, "cds/${argfile.nameWithoutExtension}.jsa")
                cds.parentFile.mkdirs()
                // A class-data-sharing archive of this classpath makes every later start faster. Only
                // the first process writes it; the others read it once it exists.
                val share = when {
                    n == 0 -> listOf("-XX:SharedArchiveFile=${cds.path}", "-XX:+AutoCreateSharedArchive")
                    cds.isFile -> listOf("-XX:SharedArchiveFile=${cds.path}")
                    else -> emptyList()
                }
                val cmd = listOf(java.path, "-Xmx1536m", "-XX:+UseParallelGC", "-XX:+EnableDynamicAgentLoading", "-Djava.awt.headless=true") +
                    share + listOf("-Xlog:cds=off", "-Xlog:cds+dynamic=off", "-Xshare:auto", "@${argfile.path}")
                val p = ProcessBuilder(cmd).redirectError(ProcessBuilder.Redirect.PIPE).start()
                val stderr = StringBuffer()
                val drain = thread(isDaemon = true) { p.errorStream.bufferedReader().forEachLine { stderr.appendLine(it); if (log.verbose) System.err.println("    [w$n] $it") } }
                val toWorker = p.outputStream.bufferedWriter()
                val fromWorker = p.inputStream.bufferedReader()
                try {
                    while (true) {
                        val group = queue.poll() ?: break
                        toWorker.write(Json.write(group)); toWorker.newLine(); toWorker.flush()
                        val pending = (group["shots"] as List<*>).map { (it as Map<*, *>)["out"] as String }.toMutableSet()
                        while (true) {
                            val line = fromWorker.readLine()
                            if (line == null) {
                                val why = stderr.toString().lines().filter { it.isNotBlank() }.takeLast(8).joinToString(" | ")
                                pending.forEach { onResult(Result(it, false, error = "renderer exited: $why")) }
                                return@thread
                            }
                            val f = line.split('\t')
                            when (f[0]) {
                                "done" -> break
                                "ready" -> readyMs.compareAndSet(0, f[1].toInt())
                                "ok" -> { pending -= f[1]; onResult(Result(f[1], true, f[2].toLong(), f[3])) }
                                "error" -> { pending -= f[1]; onResult(Result(f[1], false, error = f.getOrElse(2) { "" })) }
                            }
                        }
                    }
                } finally {
                    runCatching { toWorker.close() }
                    p.waitFor()
                    drain.join(1000)
                }
            }
        }
        threads.forEach { it.join() }
        return readyMs.get().toLong()
    }

    /** `java @file`: the classpath is far too long for a command line. */
    private fun argfile(): File {
        val cp = (listOf(workerJar) + module.classDirs + module.classpath + module.bootClasspath).joinToString(File.pathSeparator) { it.absolutePath }
        val hash = MessageDigest.getInstance("SHA-1").digest((cp + java.path).toByteArray()).joinToString("") { "%02x".format(it) }.take(16)
        val f = File(Cache.root, "args/$hash.args")
        f.parentFile.mkdirs()
        f.writeText("-cp \"${cp.replace("\\", "\\\\")}\"\nswiftshot.android.worker.WorkerKt\n")
        return f
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
