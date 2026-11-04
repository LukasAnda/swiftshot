package swiftshot.android

/** `summary.md` (docs/wiki/Baseline-format.md): the report in a few lines of Markdown, for a CI's summary page and the pull request comment. */
object Summary {
    /** First line; finds the comment again on the next run. */
    const val MARKER = "<!-- swiftshot -->"
    private const val MAX_ROWS = 200
    private const val MAX_BYTES = 60_000
    private val ORDER = listOf("error", "changed", "added", "removed")

    fun acceptHint(provider: String?): String = when (provider) {
        "github" -> "Comment `/swiftshot accept` on this pull request to accept every change, or put screenshot ids one per line below it to accept some."
        "gitlab" -> "Run the manual `swiftshot-accept` job in this pipeline to accept the changes."
        "bitbucket" -> "Run the `swiftshot-accept` custom pipeline on this branch to accept the changes."
        "bitrise" -> "Run the `swiftshot-accept` workflow on this branch to accept the changes."
        "codemagic" -> "Start the `swiftshot-accept` workflow on this branch to accept the changes."
        "circleci" -> "Approve the `accept-screenshots` job in this workflow to accept the changes."
        "azure" -> "Approve the `Accept screenshots` stage in this run to accept the changes."
        "jenkins" -> "Approve the `Accept screenshots` stage in this build to accept the changes."
        else -> "Accept the changes with `swiftshot accept --from <this report>`."
    }

    private fun heading(status: String) = when (status) {
        "passed" -> "Screenshots match the baseline"
        "failed" -> "Screenshots differ from the baseline"
        else -> "Screenshot run had errors"
    }

    fun counts(v: Verification): String = v.counts.let {
        "${it["changed"]} changed · ${it["added"]} added · ${it["removed"]} removed · ${it["errors"]} errors · ${it["unchanged"]} unchanged"
    }

    /** The share of the canvas that differs: integers only, one decimal rounded half up; `<0.1%` above zero but below 0.1, `>99.9%` below the whole canvas but above 99.9. */
    fun percent(pixels: Long, total: Long): String {
        if (total <= 0) return ""
        if (pixels > 0 && pixels * 1000 < total) return "<0.1%"
        if (pixels < total && pixels * 1000 > total * 999) return ">99.9%"
        val tenths = (pixels * 2000 + total) / (2 * total)
        return "${tenths / 10}.${tenths % 10}%"
    }

    /** The Pixels cell of an entry: a changed one's percentage, blank otherwise. */
    private fun pixels(e: Map<String, Any?>): String {
        if (e["status"] != "changed") return ""
        val p = e["pixels"] as? Number ?: return ""
        val c = e["canvasSize"] as? List<*> ?: return ""
        return percent(p.toLong(), (c[0] as Number).toLong() * (c[1] as Number).toLong())
    }

    /** The rows a run has to show, as (status, id, Pixels cell): errors, changed, added, removed; each by id in UTF-8 byte order. */
    fun rows(v: Verification): List<Triple<String, String, String>> =
        v.entries.filter { it["status"] in ORDER }.mapNotNull { e -> (e["id"] as? String)?.let { Triple(e["status"] as String, it, pixels(e)) } }
            .sortedWith(compareBy<Triple<String, String, String>> { ORDER.indexOf(it.first) }.thenComparing({ it.second }, CanonicalJson.utf8))

    fun markdown(v: Verification, ci: Ci?): String {
        val notes = v.mismatches.map { "> **Note:** Baseline rendered differently: $it" } +
            (if (v.localBaseline) listOf("> **Note:** Some baseline images were recorded outside CI (local); record or accept them on CI") else emptyList())
        val rows = rows(v)
        val tail = listOfNotNull(
            ci?.buildUrl?.let { "[Full report]($it)" },
            if (v.status == "failed") acceptHint(ci?.provider) else null,
        )
        fun build(shown: Int): String {
            val blocks = mutableListOf("$MARKER\n### ${heading(v.status)}", counts(v))
            if (notes.isNotEmpty()) blocks += notes.joinToString("\n")
            if (rows.isNotEmpty()) {
                val lines = mutableListOf("| Status | Screenshot | Pixels |", "|---|---|---|")
                for ((status, id, pixels) in rows.take(shown)) lines += "| $status | `${id.replace("|", "\\|").replace('`', '\'')}` |${if (pixels.isEmpty()) "" else " ${pixels.replace(">", "\\>")}"} |"
                if (shown < rows.size) lines += "| | …and ${rows.size - shown} more | |"
                blocks += lines.joinToString("\n")
            }
            blocks += tail
            return blocks.joinToString("\n\n") + "\n"
        }
        var shown = minOf(MAX_ROWS, rows.size)
        while (shown > 0 && build(shown).toByteArray().size > MAX_BYTES) shown--
        return build(shown)
    }
}
