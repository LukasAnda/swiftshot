package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** CI detection against the shared fixtures in Shared/testdata/ci (docs/wiki/Baseline-format.md, "CI detection"). */
class CiTest {
    private val root = File(System.getProperty("swiftshot.testdata") ?: error("swiftshot.testdata not set"), "ci")

    private fun detect(env: Map<String, String>, files: Map<String, String> = emptyMap()) = Ci.detect(env) { files[it] }

    @Test fun everyFixtureCaseMatches() {
        val cases = root.listFiles { f -> f.name.endsWith(".json") }!!.sortedBy { it.name }
        assertEquals(22, cases.size, "fixture cases")
        val problems = mutableListOf<String>()
        for (f in cases) {
            val case = Json.parse(f.readText()) as Map<*, *>
            @Suppress("UNCHECKED_CAST")
            val env = case["env"] as Map<String, String>
            val files = (case["files"] as Map<*, *>?).orEmpty().entries.associate { (k, v) -> k as String to (v as? String ?: CanonicalJson.compact(v)) }
            val ci = detect(env, files)
            val got = mapOf(
                "provider" to ci.provider, "commit" to ci.commit, "branch" to ci.branch, "pullRequest" to ci.pullRequest, "fork" to ci.fork,
                "buildUrl" to ci.buildUrl, "repository" to ci.repository, "isCi" to ci.isCi, "warnings" to ci.warnings,
            )
            if (CanonicalJson.compact(got) != CanonicalJson.compact(case["expected"])) problems += "${f.name}:\n  want ${CanonicalJson.compact(case["expected"])}\n  got  ${CanonicalJson.compact(got)}"
        }
        assertEquals(emptyList(), problems, problems.joinToString("\n"))
    }

    @Test fun emptyValuesCountAsUnset() {
        val ci = detect(mapOf("GITLAB_CI" to "true", "CI_COMMIT_SHA" to "abc1234", "CI_MERGE_REQUEST_SOURCE_BRANCH_SHA" to "", "CI_COMMIT_BRANCH" to "", "CI_JOB_URL" to ""))
        assertEquals("abc1234", ci.commit)
        assertNull(ci.branch)
        assertNull(ci.buildUrl)
        assertFalse(detect(mapOf("GITHUB_ACTIONS" to "")).isCi)
    }

    @Test fun swiftshotCiOverridesDetection() {
        val gh = mapOf("GITHUB_ACTIONS" to "true", "GITHUB_SHA" to "abc1234")
        assertFalse(detect(gh + ("SWIFTSHOT_CI" to "0")).isCi)
        assertEquals("github", detect(gh + ("SWIFTSHOT_CI" to "1")).provider)
        assertEquals("github", detect(gh + ("SWIFTSHOT_CI" to "")).provider)
        // A CI of unknown provider: SWIFTSHOT_CI or the generic CI variable.
        for (env in listOf(mapOf("SWIFTSHOT_CI" to "TRUE"), mapOf("CI" to "true"), mapOf("CI" to "1"))) {
            val ci = detect(env)
            assertTrue(ci.isCi, env.toString())
            assertNull(ci.provider)
        }
        assertFalse(detect(mapOf("CI" to "false")).isCi)
    }

    @Test fun firstProviderInTableOrderWins() {
        assertEquals("github", detect(mapOf("GITHUB_ACTIONS" to "true", "JENKINS_URL" to "https://j/", "CIRCLECI" to "true")).provider)
        assertEquals("circleci", detect(mapOf("JENKINS_URL" to "https://j/", "CIRCLECI" to "true")).provider)
    }

    @Test fun malformedGithubEventFallsBackToTheMergeCommit() {
        val env = mapOf("GITHUB_ACTIONS" to "true", "GITHUB_SHA" to "5e6f708", "GITHUB_EVENT_PATH" to "event.json")
        for (text in listOf("{", "[]", "\"x\"", "")) {
            val ci = detect(env, mapOf("event.json" to text))
            assertEquals("5e6f708", ci.commit, text)
            assertEquals(listOf("GITHUB_EVENT_PATH unreadable; recording GITHUB_SHA, which is a merge commit on pull requests"), ci.warnings, text)
        }
        // An unset path is not an error.
        assertEquals(emptyList(), detect(env - "GITHUB_EVENT_PATH").warnings)
    }

    @Test fun githubPushEventHasNoPullRequest() {
        val env = mapOf("GITHUB_ACTIONS" to "true", "GITHUB_SHA" to "abc1234", "GITHUB_EVENT_PATH" to "e.json")
        val ci = detect(env, mapOf("e.json" to """{"ref": "refs/heads/main"}"""))
        assertEquals("abc1234", ci.commit)
        assertNull(ci.pullRequest)
        assertEquals(emptyList(), ci.warnings)
    }

    @Test fun defaultReaderReadsRelativeAndAbsolutePaths() {
        val dir = java.nio.file.Files.createTempDirectory("swiftshot-ci").toFile()
        try {
            val f = File(dir, "event.json").apply { writeText("{}") }
            assertEquals("{}", defaultRead(f.path))
            assertNull(defaultRead(File(dir, "missing.json").path))
            assertNull(defaultRead(dir.path))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test fun jenkinsBranchWithoutOriginPrefixAndAzureRefs() {
        assertEquals("release/1", detect(mapOf("JENKINS_URL" to "https://j/", "GIT_BRANCH" to "origin/release/1")).branch)
        assertEquals("feature/tools", detect(mapOf("TF_BUILD" to "True", "BUILD_SOURCEBRANCH" to "refs/heads/feature/tools", "BUILD_SOURCEBRANCHNAME" to "tools")).branch)
        assertEquals("tools", detect(mapOf("TF_BUILD" to "True", "BUILD_SOURCEBRANCHNAME" to "tools")).branch)
    }
}
