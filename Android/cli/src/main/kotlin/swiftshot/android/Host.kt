package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.io.IOException
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import java.util.Base64

/** A reply to [Http.send]; the body is read as text. */
class HttpReply(val status: Int, val body: String)

/** The one HTTP call the git host needs; tests give it their own. Throws [IOException] when there is no reply. */
interface Http {
    fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpReply
}

/** The real [Http]: a redirect is a reply like any other, never followed (a token would follow it). */
object JavaHttp : Http {
    private val client = HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NEVER).connectTimeout(Duration.ofSeconds(30)).build()

    override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpReply {
        val request = HttpRequest.newBuilder(URI(url)).timeout(Duration.ofSeconds(60))
            .method(method, if (body == null) HttpRequest.BodyPublishers.noBody() else HttpRequest.BodyPublishers.ofString(body))
        headers.forEach { (k, v) -> request.header(k, v) }
        val response = try {
            client.send(request.build(), HttpResponse.BodyHandlers.ofInputStream())
        } catch (e: InterruptedException) { throw e } catch (e: Exception) { throw IOException("no response") }
        return response.body().use { HttpReply(response.statusCode(), String(it.readNBytes(16 shl 20), Charsets.UTF_8)) }
    }
}

/** What [Host.upsertComment] did: [action] is `created` or `updated`; [failure] is a status code or a short reason, never a body. */
data class CommentResult(val action: String?, val failure: String?) {
    val ok get() = failure == null
}

/**
 * The git host of the repository (docs/wiki/Baseline-format.md, "Git host"): where verify comments on the pull
 * request. [api] is the API base, [project] the path in the remote, [web] the project's web address.
 */
data class Host(val kind: String, val api: String, val project: String, val web: String) {
    companion object {
        private val KINDS = setOf("github", "gitlab", "bitbucket")
        private class Remote(val scheme: String?, val host: String, val port: String?, val path: List<String>)

        /** `https://[user@]host[:port]/a/b[.git]`, `ssh://git@host[:port]/a/b[.git]`, `git@host:a/b[.git]`. */
        private fun parse(remote: String): Remote? {
            val s = remote.trim()
            val url = Regex("^([A-Za-z][A-Za-z0-9+.-]*)://(?:[^@/]*@)?(\\[[^]]+]|[^/:@]+)(?::(\\d+))?/(.+)$").matchEntire(s)
            val scp = if (url == null) Regex("^[^@/:\\s]+@([^/:\\s]+):(?!//)(.+)$").matchEntire(s) else null
            val (scheme, host, port, rawPath) = when {
                url != null -> listOf(url.groupValues[1].lowercase(), url.groupValues[2], url.groupValues[3], url.groupValues[4])
                scp != null -> listOf("", scp.groupValues[1], "", scp.groupValues[2])
                else -> return null
            }
            val path = rawPath.substringBefore('?').trimEnd('/').removeSuffix(".git").split('/').filter { it.isNotEmpty() }
            if (path.size < 2 || path.any { it == "." || it == ".." }) return null
            return Remote(scheme.takeIf { it.isNotEmpty() }, host.lowercase(), port.takeIf { it.isNotEmpty() }, path)
        }

        /** The host of [remoteUrl] (`git remote get-url origin`); null when it isn't a known one. [env] is the process environment. */
        fun detect(remoteUrl: String?, env: Map<String, String>): Host? {
            fun v(k: String) = env[k]?.takeIf { it.isNotEmpty() }
            val r = remoteUrl?.let(::parse) ?: return null
            fun sameHost(url: String?) = url != null && runCatching { URI(url).host?.lowercase() }.getOrNull() == r.host
            val enterprise = v("GITHUB_ACTIONS").equals("true", true) && sameHost(v("GITHUB_SERVER_URL"))
            val kind = v("SWIFTSHOT_GIT_HOST")?.lowercase()?.takeIf { it in KINDS } ?: when {
                r.host == "github.com" -> "github"
                r.host == "bitbucket.org" -> "bitbucket"
                r.host == "gitlab.com" -> "gitlab"
                enterprise -> "github"
                sameHost(v("CI_API_V4_URL")) -> "gitlab"
                else -> return null
            }
            val web = if (r.scheme == "http" || r.scheme == "https") r.scheme else "https"
            val base = "$web://${r.host}" + (if (web == r.scheme && r.port != null) ":${r.port}" else "")
            val project = r.path.joinToString("/")
            if (kind != "gitlab" && r.path.size != 2) return null
            val api = v("SWIFTSHOT_HOST_API") ?: when (kind) {
                "github" -> (if (enterprise) v("GITHUB_API_URL") else null) ?: if (r.host == "github.com") "https://api.github.com" else "$base/api/v3"
                "bitbucket" -> "https://api.bitbucket.org/2.0"
                else -> v("CI_API_V4_URL")?.takeIf { sameHost(it) } ?: "$base/api/v4"
            }
            return Host(kind, api.trimEnd('/'), project, "$base/$project")
        }

        private fun basic(s: String) = "Basic " + Base64.getEncoder().encodeToString(s.toByteArray())

        /** A URL path segment, percent-encoded. */
        internal fun encode(s: String): String = buildString {
            for (b in s.toByteArray()) {
                val c = b.toInt() and 0xff
                if (c.toChar() in 'A'..'Z' || c.toChar() in 'a'..'z' || c.toChar() in '0'..'9' || c.toChar() in "-._~") append(c.toChar()) else append("%%%02X".format(c))
            }
        }
    }

    /** The header an API call carries. GitLab's job token can't write notes, so only a user's or project's token fits here. */
    fun authHeader(token: String): Pair<String, String> = when {
        kind == "gitlab" -> "PRIVATE-TOKEN" to token
        kind == "bitbucket" && ':' in token -> "Authorization" to basic(token)
        else -> "Authorization" to "Bearer $token"
    }

    /** The value of `http.extraHeader` for `git push`; [jobToken] is `CI_JOB_TOKEN`, which GitLab wants under another user name. */
    fun pushHeader(token: String, jobToken: String? = null): String = "Authorization: " + when (kind) {
        "github" -> basic("x-access-token:$token")
        "gitlab" -> basic((if (token == jobToken) "gitlab-ci-token" else "oauth2") + ":$token")
        else -> basic(if (':' in token) token else "x-token-auth:$token")
    }

    private val path get() = project.split('/').joinToString("/", transform = Companion::encode)

    private fun listUrl(pr: String, page: Int) = when (kind) {
        "github" -> "$api/repos/$path/issues/$pr/comments?per_page=100&page=$page"
        "gitlab" -> "$api/projects/${project.split('/').joinToString("%2F", transform = Companion::encode)}/merge_requests/$pr/notes?per_page=100&page=$page&sort=asc"
        else -> "$api/repositories/$path/pullrequests/$pr/comments?pagelen=100&page=$page"
    }

    private fun itemUrl(pr: String, id: String) = when (kind) {
        "github" -> "$api/repos/$path/issues/comments/$id"
        else -> listUrl(pr, 1).substringBefore('?') + "/$id"
    }

    /**
     * The comments of a page as (id, text), and whether there may be a next page. A comment whose id isn't a whole
     * number that fits 64 bits is skipped.
     */
    private fun comments(json: String): Pair<List<Pair<String, String>>, Boolean>? = runCatching {
        val root = Json.parse(json)
        val items = (if (kind == "bitbucket") (root as Map<*, *>)["values"] else root) as List<*>
        val parsed = items.mapNotNull { c ->
            c as Map<*, *>
            val text = if (kind == "bitbucket") (c["content"] as Map<*, *>)["raw"] else c["body"]
            val id = when (val n = c["id"] as Number) {
                is Long -> n
                else -> n.toDouble().takeIf { it.isFinite() && it == Math.floor(it) && it >= -9.223372036854775808E18 && it < 9.223372036854775808E18 }?.toLong()
            }
            id?.let { it.toString() to (text as? String ?: "") }
        }
        parsed to (if (kind == "bitbucket") (root as Map<*, *>)["next"] != null else items.size >= 100)
    }.getOrNull()

    /**
     * Writes [body] (which starts with [Summary.MARKER]) as a comment on pull request [pr]: the first comment that
     * starts with the marker is updated, else a new one is made. Looks at most 10 pages of 100. Nothing is sent over
     * plain http unless the host is this machine; no reply body is ever kept.
     */
    fun upsertComment(pr: String, body: String, token: String, http: Http): CommentResult {
        fun fail(why: String) = CommentResult(null, why)
        if (!Regex("[0-9]{1,18}").matches(pr)) return fail("invalid pull request")
        val origin = runCatching { URI(api) }.getOrNull()
        if (origin?.host == null || !(origin.scheme.equals("https", true) || (origin.scheme.equals("http", true) && origin.host.lowercase() in Accept.LOOPBACK))) return fail("https only")
        val (authName, authValue) = authHeader(token)
        val headers = mapOf(authName to authValue, "Accept" to "application/json", "Content-Type" to "application/json", "User-Agent" to "swiftshot")
        fun call(method: String, url: String, payload: String? = null) = try { http.send(method, url, headers, payload) } catch (e: IOException) { null }
        var existing: String? = null
        for (page in 1..10) {
            val reply = call("GET", listUrl(pr, page)) ?: return fail("no response")
            if (reply.status !in 200..299) return fail("${reply.status}")
            val (items, more) = comments(reply.body) ?: return fail("${reply.status}")
            existing = items.firstOrNull { it.second.startsWith(Summary.MARKER) }?.first
            if (existing != null || !more) break
        }
        val payload = CanonicalJson.compact(if (kind == "bitbucket") mapOf("content" to mapOf("raw" to body)) else mapOf("body" to body))
        val update = existing != null
        val reply = if (update) call(if (kind == "github") "PATCH" else "PUT", itemUrl(pr, existing!!), payload) else call("POST", listUrl(pr, 1).substringBefore('?'), payload)
        reply ?: return fail("no response")
        return if (reply.status in 200..299) CommentResult(if (update) "updated" else "created", null) else fail("${reply.status}")
    }
}

/** verify's last step: the comment on the pull request (docs/wiki/Baseline-format.md, "Git host"). */
object PullRequestComment {
    /**
     * Comments [body] when `SWIFTSHOT_HOST_TOKEN` is set and the CI run is for a pull request. A failure is one
     * warning and never changes verify's exit code; the token is never printed. [projectDir] is where `git` finds the origin.
     */
    fun post(body: String, ci: Ci?, env: Map<String, String>, projectDir: File?, log: Log, http: Http = JavaHttp) {
        val token = env["SWIFTSHOT_HOST_TOKEN"]?.takeIf { it.isNotEmpty() } ?: return
        val pr = ci?.pullRequest ?: return
        try {
            val host = Host.detect(origin(projectDir), env)
            if (host == null) {
                log.plain("SWIFTSHOT_HOST_TOKEN is set but the git host of origin is unknown; set SWIFTSHOT_GIT_HOST to github, gitlab or bitbucket")
                return
            }
            val result = host.upsertComment(pr, body, token, http)
            if (!result.ok) log.warn("couldn't comment on the pull request (${host.kind} ${result.failure})")
        } catch (e: InterruptedException) {
            throw e
        } catch (e: Exception) {
            log.warn("couldn't comment on the pull request")
        }
    }

    /** `git remote get-url origin` in the repository containing [dir]; null when there is none. */
    private fun origin(dir: File?): String? = runCatching {
        val p = ProcessBuilder("git", "remote", "get-url", "origin").directory(dir).redirectErrorStream(false).start()
        p.errorStream.close()
        val out = p.inputStream.bufferedReader().readText().trim()
        if (p.waitFor() == 0) out.takeIf { it.isNotEmpty() } else null
    }.getOrNull()
}
