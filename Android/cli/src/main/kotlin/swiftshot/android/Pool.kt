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
