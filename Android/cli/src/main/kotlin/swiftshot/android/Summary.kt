package swiftshot.android

/** `summary.md` (docs/wiki/Baseline-format.md): the report in a few lines of Markdown, for a CI's summary page and the pull request comment. */
object Summary {
    /** First line; finds the comment again on the next run. */
    const val MARKER = "<!-- swiftshot -->"
    private const val MAX_ROWS = 200
    private const val MAX_BYTES = 60_000
    private val ORDER = listOf("error", "changed", "added", "removed")

    fun acceptHint(provider: String?): String = when (provider) {
        "github" -> "Comment `/swiftshot accept` on this pull request to accept every change, or `/swiftshot accept <id> …` for some."
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

    /** The rows a run has to show, as (status, id): errors, changed, added, removed; each by id in UTF-8 byte order. */
    fun rows(v: Verification): List<Pair<String, String>> =
        v.entries.filter { it["status"] in ORDER }.map { it["status"] as String to it["id"] as String }
            .sortedWith(compareBy<Pair<String, String>> { ORDER.indexOf(it.first) }.thenComparing({ it.second }, CanonicalJson.utf8))

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
                val lines = mutableListOf("| Status | Screenshot |", "|---|---|")
                for ((status, id) in rows.take(shown)) lines += "| $status | `${id.replace("|", "\\|").replace('`', '\'')}` |"
                if (shown < rows.size) lines += "| | …and ${rows.size - shown} more |"
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
