package swiftshot.android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** `summary.md` (docs/wiki/Baseline-format.md); the fixture cases compare it byte for byte in BaselineTest. */
class SummaryTest {
    private fun ci(provider: String?, buildUrl: String? = null) = Ci(provider, null, null, null, null, buildUrl, null, true)

    private fun verification(entries: List<Map<String, Any?>>, ci: Ci? = null, mismatches: List<String> = emptyList(), local: Boolean = false, unattributed: List<Map<String, Any?>> = emptyList()): Verification {
        val errors = entries.filter { it["status"] == "error" }.map { mapOf("id" to it["id"], "message" to it["message"]) } + unattributed
        return Verification(entries, errors, unattributed, emptyMap(), mismatches, local, 0, BaselineEnv(GitInfo(null, null), "1.0.0-test", ci), "hash")
    }

    private fun e(status: String, id: String, message: String? = null) = mapOf("id" to id, "status" to status) + (message?.let { mapOf("message" to it) } ?: emptyMap())

    @Test fun acceptHintPerProvider() {
        assertEquals("Comment `/swiftshot accept` on this pull request to accept every change, or `/swiftshot accept <id> …` for some.", Summary.acceptHint("github"))
        assertEquals("Run the manual `swiftshot-accept` job in this pipeline to accept the changes.", Summary.acceptHint("gitlab"))
        assertEquals("Run the manual `Accept screenshots` step in this pipeline to accept the changes.", Summary.acceptHint("bitbucket"))
        assertEquals("Run the `swiftshot-accept` workflow on this branch to accept the changes.", Summary.acceptHint("bitrise"))
        assertEquals("Start the `swiftshot-accept` workflow on this branch to accept the changes.", Summary.acceptHint("codemagic"))
        assertEquals("Approve the `accept-screenshots` job in this workflow to accept the changes.", Summary.acceptHint("circleci"))
        assertEquals("Approve the `Accept screenshots` stage in this run to accept the changes.", Summary.acceptHint("azure"))
        assertEquals("Approve the `Accept screenshots` stage in this build to accept the changes.", Summary.acceptHint("jenkins"))
        assertEquals("Accept the changes with `swiftshot accept --from <this report>`.", Summary.acceptHint(null))
        assertEquals("Accept the changes with `swiftshot accept --from <this report>`.", Summary.acceptHint("somewhere"))
    }

    @Test fun passedHasNoTableAndNoHint() {
        assertEquals("<!-- swiftshot -->\n### Screenshots match the baseline\n\n0 changed · 0 added · 0 removed · 0 errors · 1 unchanged\n",
            Summary.markdown(verification(listOf(e("unchanged", "en-US/A"))), null))
    }

    @Test fun rowsAreOrderedByStatusThenUtf8IdAndEscaped() {
        val v = verification(listOf(e("added", "b"), e("removed", "a"), e("changed", "z|y`x"), e("error", "m", "boom"), e("added", "😀"), e("added", "～"), e("unchanged", "u")), ci("gitlab"))
        assertEquals(
            "<!-- swiftshot -->\n### Screenshot run had errors\n\n1 changed · 3 added · 1 removed · 1 errors · 1 unchanged\n\n" +
                "| Status | Screenshot |\n|---|---|\n| error | `m` |\n| changed | `z\\|y'x` |\n| added | `b` |\n| added | `～` |\n| added | `😀` |\n| removed | `a` |\n",
            Summary.markdown(v, ci("gitlab")))
    }

    @Test fun failedHintFollowsTheFullReportLink() {
        val c = ci("github", "https://example.com/run/1")
        val text = Summary.markdown(verification(listOf(e("added", "a")), c), c)
        assertTrue(text.endsWith("| added | `a` |\n\n[Full report](https://example.com/run/1)\n\n${Summary.acceptHint("github")}\n"), text)
        val passed = Summary.markdown(verification(listOf(e("unchanged", "a")), c), c)
        assertTrue(passed.endsWith("1 unchanged\n\n[Full report](https://example.com/run/1)\n"), passed)
    }

    @Test fun notesComeFromMismatchesThenLocalBaseline() {
        val text = Summary.markdown(verification(listOf(e("unchanged", "a")), mismatches = listOf("x: baseline 1, this run 2"), local = true), null)
        assertTrue("\n\n> **Note:** Baseline rendered differently: x: baseline 1, this run 2\n> **Note:** Some baseline images were recorded outside CI (local); record or accept them on CI\n" in text, text)
    }

    @Test fun manyRowsAreCappedAtTwoHundredAndSixtyThousandBytes() {
        val few = Summary.markdown(verification((1..250).map { e("added", "id%03d".format(it)) }), null)
        assertTrue("| added | `id200` |" in few && "id201" !in few && "| | …and 50 more |" in few, few)
        val long = "x".repeat(400)
        val text = Summary.markdown(verification((1..300).map { e("added", "%s%03d".format(long, it)) }), null)
        assertTrue(text.toByteArray().size <= 60_000, "${text.toByteArray().size}")
        val shown = Regex("\\| added \\|").findAll(text).count()
        assertTrue(shown in 100..199, "$shown")
        assertTrue("| | …and ${300 - shown} more |" in text)
        assertFalse(text.contains("\r"))
    }
}
