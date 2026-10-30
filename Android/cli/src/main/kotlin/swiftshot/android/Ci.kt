package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File

/** A file's text, a relative path from the working directory; null when it can't be read. */
fun defaultRead(path: String): String? = runCatching { File(path).takeIf { it.isFile }?.readText() }.getOrNull()

/**
 * Where a run happens, from the CI's environment (docs/wiki/Baseline-format.md, "CI detection"). [isCi] is false
 * when no CI was found or `SWIFTSHOT_CI` says there is none; [provider] is null for a CI of unknown provider.
 * [warnings] are printed by verify. [repository] is the clone URL or slug the CI gives (not written to reports).
 */
data class Ci(
    val provider: String?, val commit: String?, val branch: String?, val pullRequest: String?, val fork: Boolean?,
    val buildUrl: String?, val repository: String?, val isCi: Boolean = provider != null, val warnings: List<String> = emptyList(),
) {
    companion object {
        const val EVENT_WARNING = "GITHUB_EVENT_PATH unreadable; recording GITHUB_SHA, which is a merge commit on pull requests"
        private val NONE = Ci(null, null, null, null, null, null, null)

        /** [env] is the whole environment; [readFile] reads the GitHub event file. Empty values count as unset. */
        fun detect(env: Map<String, String>, readFile: (String) -> String? = ::defaultRead): Ci {
            fun v(k: String) = env[k]?.takeIf { it.isNotEmpty() }
            fun flag(k: String) = v(k).equals("true", ignoreCase = true)
            fun first(vararg s: String?) = s.firstOrNull { !it.isNullOrEmpty() }
            fun join(format: String, vararg keys: String): String? {
                val parts = keys.map { v(it) ?: return null }
                return String.format(format, *parts.toTypedArray())
            }
            fun after(prefix: String, s: String?) = s?.removePrefix(prefix)

            val override = v("SWIFTSHOT_CI")
            if (override != null && !override.equals("true", true) && override != "1") return NONE

            return when {
                flag("GITHUB_ACTIONS") -> github(env, readFile)
                flag("GITLAB_CI") -> {
                    val source = v("CI_MERGE_REQUEST_SOURCE_PROJECT_ID")
                    val target = v("CI_MERGE_REQUEST_PROJECT_ID")
                    Ci("gitlab", first(v("CI_MERGE_REQUEST_SOURCE_BRANCH_SHA"), v("CI_COMMIT_SHA")),
                        first(v("CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"), v("CI_COMMIT_BRANCH")), v("CI_MERGE_REQUEST_IID"),
                        if (source != null && target != null) source != target else null, v("CI_JOB_URL"), v("CI_PROJECT_URL"), true)
                }
                v("BITBUCKET_BUILD_NUMBER") != null -> {
                    val pr = v("BITBUCKET_PR_ID")
                    Ci("bitbucket", v("BITBUCKET_COMMIT"), v("BITBUCKET_BRANCH"), pr, if (pr != null) false else null,
                        join("%s/pipelines/results/%s", "BITBUCKET_GIT_HTTP_ORIGIN", "BITBUCKET_BUILD_NUMBER"), v("BITBUCKET_GIT_HTTP_ORIGIN"), true)
                }
                flag("BITRISE_IO") -> {
                    val from = v("BITRISEIO_PULL_REQUEST_REPOSITORY_URL")
                    val repo = v("GIT_REPOSITORY_URL")
                    Ci("bitrise", first(v("BITRISE_GIT_COMMIT"), v("GIT_CLONE_COMMIT_HASH")), v("BITRISE_GIT_BRANCH"), v("BITRISE_PULL_REQUEST"),
                        if (from != null && repo != null) from != repo else null, v("BITRISE_BUILD_URL"), repo, true)
                }
                v("CM_BUILD_ID") != null -> {
                    val pr = flag("CM_PULL_REQUEST")
                    Ci("codemagic", v("CM_COMMIT"), if (pr) first(v("CM_PULL_REQUEST_SOURCE"), v("CM_BRANCH")) else v("CM_BRANCH"),
                        v("CM_PULL_REQUEST_NUMBER"), null, null, null, true)
                }
                flag("CIRCLECI") -> {
                    val url = v("CIRCLE_PULL_REQUEST")
                    Ci("circleci", v("CIRCLE_SHA1"), v("CIRCLE_BRANCH"), url?.trimEnd('/')?.substringAfterLast('/'),
                        if (v("CIRCLE_PR_NUMBER") != null) true else if (url != null) false else null,
                        v("CIRCLE_BUILD_URL"), v("CIRCLE_REPOSITORY_URL"), true)
                }
                flag("TF_BUILD") -> {
                    val collection = v("SYSTEM_COLLECTIONURI")
                    val project = v("SYSTEM_TEAMPROJECT")
                    val build = v("BUILD_BUILDID")
                    Ci("azure", first(v("SYSTEM_PULLREQUEST_SOURCECOMMITID"), v("BUILD_SOURCEVERSION")),
                        first(after("refs/heads/", v("SYSTEM_PULLREQUEST_SOURCEBRANCH")), after("refs/heads/", v("BUILD_SOURCEBRANCH")), v("BUILD_SOURCEBRANCHNAME")),
                        first(v("SYSTEM_PULLREQUEST_PULLREQUESTNUMBER"), v("SYSTEM_PULLREQUEST_PULLREQUESTID")),
                        when (v("SYSTEM_PULLREQUEST_ISFORK")?.lowercase()) { "true" -> true; "false" -> false; else -> null },
                        if (collection != null && project != null && build != null) "${collection.trimEnd('/')}/$project/_build/results?buildId=$build" else null,
                        v("BUILD_REPOSITORY_URI"), true)
                }
                v("JENKINS_URL") != null -> {
                    val id = v("CHANGE_ID")
                    Ci("jenkins", v("GIT_COMMIT"), first(v("CHANGE_BRANCH"), v("BRANCH_NAME"), after("origin/", v("GIT_BRANCH"))), id,
                        if (v("CHANGE_FORK") != null) true else if (id != null) false else null, v("BUILD_URL"), v("GIT_URL"), true)
                }
                override != null || v("CI").let { it.equals("true", true) || it == "1" } -> Ci(null, null, null, null, null, null, null, true)
                else -> NONE
            }
        }

        /** GitHub Actions: the pull request's head commit, number and fork flag are only in the event file. */
        private fun github(env: Map<String, String>, readFile: (String) -> String?): Ci {
            fun v(k: String) = env[k]?.takeIf { it.isNotEmpty() }
            val warnings = mutableListOf<String>()
            var event: Map<*, *>? = null
            v("GITHUB_EVENT_PATH")?.let { path ->
                event = readFile(path)?.let { text -> runCatching { Json.parse(text) as? Map<*, *> }.getOrNull() }
                if (event == null) warnings += EVENT_WARNING
            }
            fun dig(o: Any?, vararg keys: String): Any? = keys.fold(o) { m, k -> (m as? Map<*, *>)?.get(k) }
            fun text(o: Any?) = (o as? String)?.takeIf { it.isNotEmpty() }
            val pull = dig(event, "pull_request")
            val head = text(dig(pull, "head", "repo", "full_name"))
            val base = text(dig(pull, "base", "repo", "full_name"))
            val server = v("GITHUB_SERVER_URL")
            val repo = v("GITHUB_REPOSITORY")
            val run = v("GITHUB_RUN_ID")
            return Ci("github", text(dig(pull, "head", "sha")) ?: v("GITHUB_SHA"), v("GITHUB_HEAD_REF") ?: v("GITHUB_REF_NAME"),
                (dig(pull, "number") as? Long)?.toString(), if (head != null && base != null) head != base else null,
                if (server != null && repo != null && run != null) "$server/$repo/actions/runs/$run" else null,
                if (server != null && repo != null) "$server/$repo" else null, true, warnings)
        }
    }
}
