package swiftshot.android

import java.io.File

/** The report directory's files (docs/wiki/Baseline-format.md): result.json, manifest.json, junit.xml, timings.json, and the console summary. */
object BaselineReport {
    private val files = listOf("result.json", "manifest.json", "junit.xml", "timings.json")

    /** Removes what an earlier verify wrote there (only its own files: the directory may be the user's). */
    fun clear(report: File) {
        File(report, "images").deleteRecursively()
        for (f in files) File(report, f).delete()
        report.mkdirs()
    }

    /** timings.json: how long the comparison took (not deterministic, so not part of result.json). */
    fun writeTimings(compareSeconds: Double, report: File) {
        File(report, "timings.json").writeText(CanonicalJson.pretty(mapOf("compareSeconds" to Math.round(compareSeconds * 1000) / 1000.0)))
    }

    fun write(v: Verification, report: File) {
        report.mkdirs()
        File(report, "result.json").writeText(CanonicalJson.pretty(result(v)))
        File(report, "manifest.json").writeText(CanonicalJson.pretty(manifest(v)))
        File(report, "junit.xml").writeText(junit(v))
    }

    fun result(v: Verification): Map<String, Any?> = mapOf(
        "schema" to 1, "status" to v.status, "counts" to v.counts,
        "commit" to v.env.git.commit, "branch" to v.env.git.branch, "version" to v.env.version, "ci" to v.env.ci, "host" to v.host,
        "fingerprint" to v.fingerprint, "fingerprintMismatch" to v.mismatches, "localBaseline" to v.localBaseline,
        "screenshots" to v.entries, "errors" to v.errors, "strayBaselineFiles" to v.strays,
    )

    fun manifest(v: Verification): Map<String, Any?> = mapOf(
        "schema" to 1, "commit" to v.env.git.commit, "branch" to v.env.git.branch, "ci" to v.env.ci, "configHash" to v.configHash,
        "fingerprint" to v.fingerprint,
        "ids" to mapOf("changed" to v.ids("changed"), "added" to v.ids("added"), "removed" to v.ids("removed")),
    )

    fun junit(v: Verification): String {
        val lines = mutableListOf(
            """<?xml version="1.0" encoding="UTF-8"?>""",
            """<testsuite name="swiftshot" tests="${v.entries.size + v.unattributed.size}" failures="${v.failures}" errors="${v.errors.size}">""",
        )
        for (e in v.entries) {
            val classname = if (e.containsKey("platform")) "${e["platform"]}.${e["device"]}.${e["language"]}" else "swiftshot"
            val attrs = """classname="${attr(classname)}" name="${attr(e["id"] as String)}""""
            val failure = when (e["status"]) {
                "error" -> { lines += listOf("  <testcase $attrs>", """    <error message="${attr(e["message"].toString())}"/>""", "  </testcase>"); continue }
                "changed" -> if (e["reason"] == "size") {
                    val (bw, bh) = (e["baselineSize"] as List<*>); val (nw, nh) = (e["newSize"] as List<*>)
                    "changed: size ${bw}x$bh to ${nw}x$nh"
                } else "changed: ${e["pixels"]} pixels"
                "added", "removed" -> e["status"] as String
                else -> { lines += "  <testcase $attrs/>"; continue }
            }
            lines += listOf("  <testcase $attrs>", """    <failure message="${attr(failure)}"/>""", "  </testcase>")
        }
        v.unattributed.forEachIndexed { i, err ->
            lines += listOf("""  <testcase classname="swiftshot" name="error ${i + 1}">""", """    <error message="${attr(err["message"].toString())}"/>""", "  </testcase>")
        }
        lines += "</testsuite>"
        return lines.joinToString("\n") + "\n"
    }

    private fun attr(s: String) = buildString {
        for (c in s) when (c) {
            '&' -> append("&amp;")
            '<' -> append("&lt;")
            '>' -> append("&gt;")
            '"' -> append("&quot;")
            '\t', '\n', '\r' -> append("&#${c.code};")
            else -> if (c >= ' ') append(c)
        }
    }

    /** What verify prints, in order: fingerprint mismatches first, the local-baseline warning, each difference, the totals. */
    fun summary(v: Verification, report: File): List<Pair<String, String>> {
        val out = mutableListOf<Pair<String, String>>()
        for (m in v.mismatches) out += "warn" to "Baseline rendered differently: $m"
        if (v.localBaseline) out += "warn" to "Some baseline images were recorded outside CI (local); record or accept them on CI"
        for (e in v.entries) {
            val id = e["id"]
            when (e["status"]) {
                "changed" -> out += "plain" to "changed  $id  (${if (e["reason"] == "size") "size" else "${e["pixels"]} pixels"})"
                "added", "removed" -> out += "plain" to "${e["status"]}  $id"
                "error" -> out += "error" to "$id: ${e["message"]}"
            }
        }
        for (err in v.unattributed) out += "error" to err["message"].toString()
        val c = v.counts
        val totals = "${c["unchanged"]} unchanged, ${c["changed"]} changed, ${c["added"]} added, ${c["removed"]} removed, ${c["errors"]} errors → $report"
        out += (if (v.status == "passed") "ok" else if (v.status == "failed") "warn" else "error") to "Verify ${v.status}: $totals"
        return out
    }
}
