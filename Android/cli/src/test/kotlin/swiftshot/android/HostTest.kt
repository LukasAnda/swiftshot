package swiftshot.android

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import swiftshot.android.shared.Json
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintStream
import java.net.InetSocketAddress
import java.nio.file.Files
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** Git host detection against Shared/testdata/host, and the pull request comment against in-process servers (docs/wiki/Baseline-format.md, "Git host"). */
class HostTest {
    private val testdata = File(System.getProperty("swiftshot.testdata") ?: error("swiftshot.testdata not set"))
    private val tmp: File = Files.createTempDirectory("swiftshot-host").toFile().canonicalFile
    private val servers = mutableListOf<HttpServer>()
    private val token = "tok-s3cret-VALUE"

    @AfterTest fun cleanUp() { servers.forEach { it.stop(0) }; tmp.deleteRecursively() }

    /** What a server saw. */
    private class Seen(val method: String, val target: String, val headers: Map<String, String>, val body: String)

    private class Server(val http: HttpServer, val seen: CopyOnWriteArrayList<Seen>) {
        val url get() = "http://127.0.0.1:${http.address.port}"
    }

    /** A loopback server; [respond] gives (status, body, extra headers) for each request. The reply is sent after the request is recorded. */
    private fun server(respond: (Seen) -> Triple<Int, String, Map<String, String>>): Server {
        val seen = CopyOnWriteArrayList<Seen>()
        val s = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        s.createContext("/") { x: HttpExchange ->
            val r = Seen(x.requestMethod, x.requestURI.rawPath + (x.requestURI.rawQuery?.let { "?$it" } ?: ""),
                x.requestHeaders.entries.associate { it.key.lowercase() to it.value.first() }, x.requestBody.readBytes().toString(Charsets.UTF_8))
            seen += r
            val (status, body, headers) = respond(r)
            headers.forEach { (k, v) -> x.responseHeaders.add(k, v) }
            val bytes = body.toByteArray()
            x.sendResponseHeaders(status, if (bytes.isEmpty()) -1 else bytes.size.toLong())
            if (bytes.isNotEmpty()) x.responseBody.use { it.write(bytes) }
            x.close()
        }
        s.start()
        servers += s
        return Server(s, seen)
    }

    private fun ok(body: String) = Triple(200, body, emptyMap<String, String>())

    private fun host(kind: String, api: String) = when (kind) {
        "github" -> Host("github", api, "owner/name", "https://github.com/owner/name")
        "gitlab" -> Host("gitlab", api, "group/sub/name", "https://gitlab.com/group/sub/name")
        else -> Host("bitbucket", api, "ws/repo", "https://bitbucket.org/ws/repo")
    }

    private fun comment(id: Int, text: String, kind: String) = if (kind == "bitbucket") """{"id":$id,"content":{"raw":${CanonicalJson.compact(text)}}}""" else """{"id":$id,"body":${CanonicalJson.compact(text)}}"""

    /** A page of comments as the host's list endpoint answers it. */
    private fun page(kind: String, items: List<String>, next: Boolean = false) =
        if (kind == "bitbucket") """{"values":[${items.joinToString(",")}]${if (next) ""","next":"https://example.invalid/next"""" else ""}}""" else "[${items.joinToString(",")}]"

    private val kinds = listOf("github", "gitlab", "bitbucket")

    private fun listPath(kind: String) = when (kind) {
        "github" -> "/repos/owner/name/issues/7/comments"
        "gitlab" -> "/projects/group%2Fsub%2Fname/merge_requests/7/notes"
        else -> "/repositories/ws/repo/pullrequests/7/comments"
    }
    private fun itemPath(kind: String, id: Int) = when (kind) {
        "github" -> "/repos/owner/name/issues/comments/$id"
        "gitlab" -> "/projects/group%2Fsub%2Fname/merge_requests/7/notes/$id"
        else -> "/repositories/ws/repo/pullrequests/7/comments/$id"
    }
    private fun bodyOf(kind: String, json: String): String {
        val m = Json.parse(json) as Map<*, *>
        return if (kind == "bitbucket") ((m["content"] as Map<*, *>)["raw"] as String) else m["body"] as String
    }

    @Test fun remotesFixture() {
        val cases = Json.parse(File(testdata, "host/remotes.json").readText()) as List<*>
        assertEquals(35, cases.size, "fixture cases")
        val problems = mutableListOf<String>()
        for ((i, c) in cases.withIndex()) {
            val case = c as Map<*, *>
            @Suppress("UNCHECKED_CAST")
            val h = Host.detect(case["remote"] as String?, case["env"] as Map<String, String>)
            val got = h?.let { mapOf("kind" to it.kind, "api" to it.api, "project" to it.project, "web" to it.web) }
            if (CanonicalJson.compact(got) != CanonicalJson.compact(case["expected"])) problems += "#$i ${case["remote"]}:\n  want ${CanonicalJson.compact(case["expected"])}\n  got  ${CanonicalJson.compact(got)}"
        }
        assertEquals(emptyList(), problems, problems.joinToString("\n"))
    }

    @Test fun authHeaders() {
        assertEquals("Authorization" to "Bearer t", host("github", "x").authHeader("t"))
        assertEquals("PRIVATE-TOKEN" to "t", host("gitlab", "x").authHeader("t"))
        assertEquals("Authorization" to "Bearer t", host("bitbucket", "x").authHeader("t"))
        assertEquals("Authorization" to "Basic " + Base64.getEncoder().encodeToString("me@example.com:t".toByteArray()), host("bitbucket", "x").authHeader("me@example.com:t"))
    }

    @Test fun pushHeaders() {
        fun basic(s: String) = "Authorization: Basic " + Base64.getEncoder().encodeToString(s.toByteArray())
        assertEquals(basic("x-access-token:t"), host("github", "x").pushHeader("t"))
        assertEquals(basic("oauth2:t"), host("gitlab", "x").pushHeader("t"))
        assertEquals(basic("gitlab-ci-token:t"), host("gitlab", "x").pushHeader("t", jobToken = "t"))
        assertEquals(basic("oauth2:t"), host("gitlab", "x").pushHeader("t", jobToken = "other"))
        assertEquals(basic("x-token-auth:t"), host("bitbucket", "x").pushHeader("t"))
        assertEquals(basic("me@example.com:t"), host("bitbucket", "x").pushHeader("me@example.com:t"))
    }

    @Test fun createsCommentWhenNoneExists() {
        for (kind in kinds) {
            val s = server { r -> if (r.method == "GET") ok(page(kind, listOf(comment(1, "hello", kind)))) else Triple(201, "{}", emptyMap()) }
            val result = host(kind, s.url).upsertComment("7", "<!-- swiftshot -->\nbody é", token, JavaHttp)
            assertEquals("created", result.action, kind)
            assertEquals(2, s.seen.size, kind)
            val get = s.seen[0]
            assertTrue(get.target.startsWith(listPath(kind) + "?"), get.target)
            assertTrue(get.target.contains(if (kind == "bitbucket") "pagelen=100&page=1" else "per_page=100&page=1"), get.target)
            if (kind == "gitlab") assertTrue(get.target.contains("sort=asc"), get.target)
            val post = s.seen[1]
            assertEquals("POST", post.method, kind)
            assertEquals(listPath(kind), post.target, kind)
            assertEquals("<!-- swiftshot -->\nbody é", bodyOf(kind, post.body), kind)
            val auth = host(kind, "x").authHeader(token)
            assertEquals(auth.second, post.headers[auth.first.lowercase()], kind)
        }
    }

    @Test fun updatesExistingMarkedComment() {
        for (kind in kinds) {
            val full = (1..100).map { comment(it, "chatter $it", kind) }
            val s = server { r ->
                when {
                    r.method == "GET" && r.target.contains("&page=1") -> ok(page(kind, full, next = true))
                    r.method == "GET" && r.target.contains("&page=2") -> ok(page(kind, listOf(comment(555, "text <!-- swiftshot -->", kind), comment(777, "<!-- swiftshot -->\nold", kind))))
                    else -> ok("{}")
                }
            }
            val result = host(kind, s.url).upsertComment("7", "<!-- swiftshot -->\nnew", token, JavaHttp)
            assertEquals("updated", result.action, kind)
            val write = s.seen.last()
            assertEquals(if (kind == "github") "PATCH" else "PUT", write.method, kind)
            assertEquals(itemPath(kind, 777), write.target, kind)
            assertEquals("<!-- swiftshot -->\nnew", bodyOf(kind, write.body), kind)
            assertEquals(3, s.seen.size, kind)
        }
    }

    @Test fun ignoresUnmarkedComments() {
        for (kind in kinds) {
            val s = server { r -> if (r.method == "GET") ok(page(kind, listOf(comment(1, "no marker", kind), comment(2, " <!-- swiftshot -->\nnot first", kind), comment(3, "x\n<!-- swiftshot -->", kind)))) else Triple(201, "{}", emptyMap()) }
            assertEquals("created", host(kind, s.url).upsertComment("7", "<!-- swiftshot -->\nb", token, JavaHttp).action, kind)
            assertEquals("POST", s.seen.last().method, kind)
        }
    }

    @Test fun scansAtMostTenPages() {
        val s = server { r -> if (r.method == "GET") ok(page("github", (1..100).map { comment(it, "c", "github") })) else Triple(201, "{}", emptyMap()) }
        assertEquals("created", host("github", s.url).upsertComment("7", "<!-- swiftshot -->\nb", token, JavaHttp).action)
        assertEquals(11, s.seen.size)
        assertTrue(s.seen[9].target.contains("page=10"))
    }

    @Test fun failuresAreReported() {
        for (kind in kinds) {
            for (status in listOf(401, 404, 500)) {
                val s = server { Triple(status, "no", emptyMap()) }
                val r = host(kind, s.url).upsertComment("7", "<!-- swiftshot -->\nb", token, JavaHttp)
                assertEquals("$status", r.failure, kind)
            }
            val s = server { r -> if (r.method == "GET") ok(page(kind, emptyList())) else Triple(403, "no", emptyMap()) }
            assertEquals("403", host(kind, s.url).upsertComment("7", "<!-- swiftshot -->\nb", token, JavaHttp).failure, kind)
            val bad = server { ok("{not json") }
            assertEquals("200", host(kind, bad.url).upsertComment("7", "<!-- swiftshot -->\nb", token, JavaHttp).failure, kind)
        }
    }

    @Test fun connectionRefusedIsAFailure() {
        val dead = server { ok("[]") }.also { it.http.stop(0) }
        val r = host("github", dead.url).upsertComment("7", "<!-- swiftshot -->\nb", token, JavaHttp)
        assertEquals("no response", r.failure)
    }

    @Test fun redirectNotFollowed() {
        val elsewhere = server { ok("[]") }
        for (kind in kinds) {
            val s = server { Triple(302, "", mapOf("Location" to elsewhere.url + "/stolen")) }
            val r = host(kind, s.url).upsertComment("7", "<!-- swiftshot -->\nb", token, JavaHttp)
            assertEquals("302", r.failure, kind)
        }
        assertEquals(0, elsewhere.seen.size)
    }

    @Test fun httpRefusedForToken() {
        val requests = mutableListOf<String>()
        val http = object : Http { override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpReply { requests += url; return HttpReply(200, "[]") } }
        val r = host("github", "http://git.example.com/api").upsertComment("7", "<!-- swiftshot -->\nb", token, http)
        assertEquals("https only", r.failure)
        assertEquals(emptyList(), requests)
        assertEquals(listOf("https://git.example.com/api/repos/owner/name/issues/7/comments?per_page=100&page=1"),
            run { host("github", "https://git.example.com/api").upsertComment("7", "<!-- swiftshot -->\nb", token, http); requests.take(1) })
    }

    @Test fun pullRequestMustBeANumber() {
        val s = server { ok("[]") }
        assertEquals("invalid pull request", host("github", s.url).upsertComment("7/../x", "b", token, JavaHttp).failure)
        assertEquals(0, s.seen.size)
    }

    // The verify step: when, and what is printed

    private class Capture : Log(false) {
        val lines = mutableListOf<String>()
        override fun ok(s: String) { lines += s }
        override fun warn(s: String) { lines += s }
        override fun plain(s: String) { lines += s }
        fun text() = lines.joinToString("\n")
    }

    private var repos = 0

    private fun repoWithOrigin(url: String): File {
        val dir = File(tmp, "repo${repos++}").also { it.mkdirs() }
        for (args in listOf(listOf("init", "-q"), listOf("remote", "add", "origin", url)))
            assertEquals(0, ProcessBuilder(listOf("git") + args).directory(dir).redirectErrorStream(true).start().also { it.inputStream.readBytes() }.waitFor())
        return dir
    }

    private val gitlabCi = Ci("gitlab", "abc", "feature/x", "7", false, "https://ci.example/job/1", null, true)

    private fun post(ci: Ci?, env: Map<String, String>, log: Log, http: Http, dir: File? = repoWithOrigin("https://gitlab.com/group/name.git")) =
        PullRequestComment.post("<!-- swiftshot -->\nbody", ci, env, dir, log, http)

    private class Recording(val replies: (String) -> HttpReply = { HttpReply(200, "[]") }) : Http {
        val requests = mutableListOf<String>()
        override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpReply { requests += "$method $url"; return replies(method) }
    }

    @Test fun noCommentWithoutTokenOrPr() {
        val http = Recording()
        val log = Capture()
        post(gitlabCi, emptyMap(), log, http)
        post(gitlabCi, mapOf("SWIFTSHOT_HOST_TOKEN" to ""), log, http)
        post(gitlabCi.copy(pullRequest = null), mapOf("SWIFTSHOT_HOST_TOKEN" to token), log, http)
        post(null, mapOf("SWIFTSHOT_HOST_TOKEN" to token), log, http)
        assertEquals(emptyList(), http.requests)
        assertEquals(emptyList(), log.lines)
    }

    @Test fun unknownHostIsOneInfoLineWithoutTheToken() {
        val http = Recording()
        val log = Capture()
        post(gitlabCi, mapOf("SWIFTSHOT_HOST_TOKEN" to token), log, http, repoWithOrigin("https://git.corp.example/g/n.git"))
        assertEquals(emptyList(), http.requests)
        assertEquals(1, log.lines.size, log.text())
        assertFalse(token in log.text())
    }

    @Test fun commentFailureIsWarning() {
        for (reply in listOf(HttpReply(401, "x"), HttpReply(500, "x"))) {
            val log = Capture()
            post(gitlabCi, mapOf("SWIFTSHOT_HOST_TOKEN" to token), log, Recording { reply })
            assertEquals(listOf("couldn't comment on the pull request (gitlab ${reply.status})"), log.lines)
        }
        val refused = server { ok("[]") }.also { it.http.stop(0) }
        val log = Capture()
        post(gitlabCi, mapOf("SWIFTSHOT_HOST_TOKEN" to token, "SWIFTSHOT_HOST_API" to refused.url), log, JavaHttp)
        assertEquals(listOf("couldn't comment on the pull request (gitlab no response)"), log.lines)
    }

    @Test fun postsToTheHostOfTheRemote() {
        val s = server { r -> if (r.method == "GET") ok("[]") else Triple(201, "{}", emptyMap()) }
        val log = Capture()
        post(gitlabCi, mapOf("SWIFTSHOT_HOST_TOKEN" to token, "SWIFTSHOT_HOST_API" to s.url), log, JavaHttp)
        assertEquals(emptyList(), log.lines)
        assertEquals(listOf("GET", "POST"), s.seen.map { it.method })
        assertEquals("/projects/group%2Fname/merge_requests/7/notes", s.seen[1].target)
        assertEquals(token, s.seen[1].headers["private-token"])
    }

    @Test fun tokenNeverInOutput() {
        val s = server { Triple(403, """{"message":"bad token $token"}""", emptyMap()) }
        val err = ByteArrayOutputStream()
        val out = ByteArrayOutputStream()
        val oldErr = System.err
        val oldOut = System.out
        System.setErr(PrintStream(err, true))
        System.setOut(PrintStream(out, true))
        val log = Capture()
        try {
            post(gitlabCi, mapOf("SWIFTSHOT_HOST_TOKEN" to token, "SWIFTSHOT_HOST_API" to s.url), log, JavaHttp)
            post(gitlabCi, mapOf("SWIFTSHOT_HOST_TOKEN" to token, "SWIFTSHOT_HOST_API" to "http://git.example.com/api"), log, JavaHttp)
        } finally { System.setErr(oldErr); System.setOut(oldOut) }
        assertTrue(log.lines.isNotEmpty())
        val all = log.text() + err.toString() + out.toString()
        assertFalse(token in all, all)
    }

    @Test fun verifyExitCodeIsUnchangedByAFailingComment() {
        val case = File(testdata, "baseline/changed-pixels")
        val vars = mapOf("SWIFTSHOT_COMMIT" to "0123456789abcdef0123456789abcdef01234567", "SWIFTSHOT_BRANCH" to "feature/x",
            "GITLAB_CI" to "true", "CI_MERGE_REQUEST_IID" to "7", "CI_JOB_URL" to "https://ci.example/job/1")
        val env = BaselineEnv.detect(tmp, vars, { null }, "1.0.0-test")
        assertEquals("7", env.ci?.pullRequest)
        val config = CompareConfig.from(Options.parse(listOf("--project-dir", tmp.path, "--config", File(case, "config.json").path)))
        val s = server { Triple(401, "no", emptyMap()) }
        val log = Capture()
        val code = Baseline.verify(File(case, "output"), File(case, "baseline"), File(tmp, "verify-report"), config, env, log,
            vars + mapOf("SWIFTSHOT_HOST_TOKEN" to token, "SWIFTSHOT_HOST_API" to s.url), PrintStream(ByteArrayOutputStream()), repoWithOrigin("https://gitlab.com/group/name.git"))
        assertEquals(1, code)
        assertTrue("couldn't comment on the pull request (gitlab 401)" in log.lines, log.text())
        assertEquals("<!-- swiftshot -->", File(tmp, "verify-report/summary.md").readLines().first())
        assertNotNull(s.seen.firstOrNull())
    }

    @Test fun commentBodyIsTheSummary() {
        val case = File(testdata, "baseline/changed-pixels")
        val vars = mapOf("SWIFTSHOT_COMMIT" to "0123456789abcdef0123456789abcdef01234567", "SWIFTSHOT_BRANCH" to "feature/x",
            "GITLAB_CI" to "true", "CI_MERGE_REQUEST_IID" to "7", "CI_JOB_URL" to "https://ci.example/job/1")
        val env = BaselineEnv.detect(tmp, vars, { null }, "1.0.0-test")
        val config = CompareConfig.from(Options.parse(listOf("--project-dir", tmp.path, "--config", File(case, "config.json").path)))
        val s = server { r -> if (r.method == "GET") ok("[]") else Triple(201, "{}", emptyMap()) }
        Baseline.verify(File(case, "output"), File(case, "baseline"), File(tmp, "verify-report"), config, env, Capture(),
            vars + mapOf("SWIFTSHOT_HOST_TOKEN" to token, "SWIFTSHOT_HOST_API" to s.url), PrintStream(ByteArrayOutputStream()), repoWithOrigin("https://gitlab.com/group/name.git"))
        assertEquals(File(tmp, "verify-report/summary.md").readText(), bodyOf("gitlab", s.seen.last().body))
    }
}
