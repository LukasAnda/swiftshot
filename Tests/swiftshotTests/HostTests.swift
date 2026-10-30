import XCTest
@testable import swiftshot

/// A loopback HTTP/1.1 server that records whole requests (method, target, headers, body) and answers each after
/// recording it. One thread; every response closes the connection.
/// Foundation has a `Host` too; the module's own is the git host.
typealias GitHost = swiftshot.Host

final class RecordingServer {
    struct Seen { let method: String; let target: String; let headers: [String: String]; let body: String }
    struct Reply { var status = 200; var body = ""; var headers: [String: String] = [:] }
    let port: Int
    var url: String { "http://127.0.0.1:\(port)" }
    private let fd: Int32
    private let lock = NSLock()
    private var _seen: [Seen] = []
    var seen: [Seen] { lock.lock(); defer { lock.unlock() }; return _seen }

    init(_ respond: @escaping (Seen) -> Reply) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 8) == 0 else { throw CLIError("test server: bind failed") }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        self.fd = fd
        port = Int(UInt16(bigEndian: addr.sin_port))
        Thread.detachNewThread { [weak self] in
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { return }
                var data = [UInt8]()
                var buf = [UInt8](repeating: 0, count: 8192)
                func headerEnd() -> Int? {
                    guard data.count >= 4 else { return nil }
                    for i in 0...(data.count - 4) where data[i] == 13 && data[i + 1] == 10 && data[i + 2] == 13 && data[i + 3] == 10 { return i + 4 }
                    return nil
                }
                while headerEnd() == nil { let n = read(c, &buf, buf.count); if n <= 0 { break }; data += buf[0..<n] }
                let end = headerEnd() ?? data.count
                let lines = String(decoding: data[0..<end], as: UTF8.self).components(separatedBy: "\r\n")
                let first = lines.first?.split(separator: " ").map(String.init) ?? []
                var headers: [String: String] = [:]
                for l in lines.dropFirst() { if let i = l.firstIndex(of: ":") { headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
                let length = Int(headers["content-length"] ?? "") ?? 0
                while data.count - end < length { let n = read(c, &buf, buf.count); if n <= 0 { break }; data += buf[0..<n] }
                let seen = Seen(method: first.first ?? "", target: first.count > 1 ? first[1] : "/", headers: headers, body: String(decoding: data[min(end, data.count)...], as: UTF8.self))
                self?.lock.lock(); self?._seen.append(seen); self?.lock.unlock()
                let reply = respond(seen)
                let payload = Array(reply.body.utf8)
                var head = "HTTP/1.1 \(reply.status) X\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n"
                for (k, v) in reply.headers { head += "\(k): \(v)\r\n" }
                let out = Array((head + "\r\n").utf8) + payload
                var sent = 0
                while sent < out.count { let n = out[sent...].withUnsafeBufferPointer { write(c, $0.baseAddress, $0.count) }; if n <= 0 { break }; sent += n }
                close(c)
            }
        }
    }

    func stop() { shutdown(fd, SHUT_RDWR); close(fd) }
}

/// Git host detection against Shared/testdata/host, and the pull request comment against in-process servers (docs/wiki/Baseline-format.md, "Git host").
final class HostTests: XCTestCase {
    var tmp: URL!
    var servers: [RecordingServer] = []
    let token = "tok-s3cret-VALUE"
    let marked = "<!-- swiftshot -->\nb"
    override func setUp() { tmp = temporaryDirectory("swiftshot-host") }
    override func tearDown() { servers.forEach { $0.stop() }; servers = []; try? FileManager.default.removeItem(at: tmp) }

    let kinds = ["github", "gitlab", "bitbucket"]

    func server(_ respond: @escaping (RecordingServer.Seen) -> RecordingServer.Reply) throws -> RecordingServer {
        let s = try RecordingServer(respond)
        servers.append(s)
        return s
    }
    func ok(_ body: String) -> RecordingServer.Reply { .init(status: 200, body: body) }

    func host(_ kind: String, _ api: String) -> GitHost {
        switch kind {
        case "github": return GitHost(kind: "github", api: api, project: "owner/name", web: "https://github.com/owner/name")
        case "gitlab": return GitHost(kind: "gitlab", api: api, project: "group/sub/name", web: "https://gitlab.com/group/sub/name")
        default: return GitHost(kind: "bitbucket", api: api, project: "ws/repo", web: "https://bitbucket.org/ws/repo")
        }
    }

    func comment(_ id: Int, _ text: String, _ kind: String) -> String {
        let t = JSON.string(text).compact()
        return kind == "bitbucket" ? "{\"id\":\(id),\"content\":{\"raw\":\(t)}}" : "{\"id\":\(id),\"body\":\(t)}"
    }
    func page(_ kind: String, _ items: [String], next: Bool = false) -> String {
        kind == "bitbucket" ? "{\"values\":[\(items.joined(separator: ","))]\(next ? ",\"next\":\"https://example.invalid/next\"" : "")}" : "[\(items.joined(separator: ","))]"
    }
    func listPath(_ kind: String) -> String {
        switch kind {
        case "github": return "/repos/owner/name/issues/7/comments"
        case "gitlab": return "/projects/group%2Fsub%2Fname/merge_requests/7/notes"
        default: return "/repositories/ws/repo/pullrequests/7/comments"
        }
    }
    func itemPath(_ kind: String, _ id: Int) -> String {
        switch kind {
        case "github": return "/repos/owner/name/issues/comments/\(id)"
        case "gitlab": return "/projects/group%2Fsub%2Fname/merge_requests/7/notes/\(id)"
        default: return "/repositories/ws/repo/pullrequests/7/comments/\(id)"
        }
    }
    func bodyOf(_ kind: String, _ json: String) throws -> String {
        let m = try JSON.parse(json)
        return kind == "bitbucket" ? m["content"]!["raw"]!.string! : m["body"]!.string!
    }

    func testRemotesFixture() throws {
        let cases = try readJSON(repoRoot.appendingPathComponent("Shared/testdata/host/remotes.json")).array!
        XCTAssertEqual(cases.count, 35, "fixture cases")
        var problems: [String] = []
        for (i, c) in cases.enumerated() {
            var env: [String: String] = [:]
            for (k, v) in c["env"]!.object! { env[k] = v.string! }
            let h = GitHost.detect(c["remote"]!.string, env: env)
            let got: JSON = h.map { .object(["kind": .string($0.kind), "api": .string($0.api), "project": .string($0.project), "web": .string($0.web)]) } ?? .null
            if got.compact() != c["expected"]!.compact() { problems.append("#\(i) \(c["remote"]!.text):\n  want \(c["expected"]!.compact())\n  got  \(got.compact())") }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testAuthHeaders() {
        XCTAssertTrue(host("github", "x").authHeader("t") == ("Authorization", "Bearer t"))
        XCTAssertTrue(host("gitlab", "x").authHeader("t") == ("PRIVATE-TOKEN", "t"))
        XCTAssertTrue(host("bitbucket", "x").authHeader("t") == ("Authorization", "Bearer t"))
        XCTAssertTrue(host("bitbucket", "x").authHeader("me@example.com:t") == ("Authorization", "Basic " + Data("me@example.com:t".utf8).base64EncodedString()))
    }

    func testPushHeaders() {
        func basic(_ s: String) -> String { "Authorization: Basic " + Data(s.utf8).base64EncodedString() }
        XCTAssertEqual(host("github", "x").pushHeader("t"), basic("x-access-token:t"))
        XCTAssertEqual(host("gitlab", "x").pushHeader("t"), basic("oauth2:t"))
        XCTAssertEqual(host("gitlab", "x").pushHeader("t", jobToken: "t"), basic("gitlab-ci-token:t"))
        XCTAssertEqual(host("gitlab", "x").pushHeader("t", jobToken: "other"), basic("oauth2:t"))
        XCTAssertEqual(host("bitbucket", "x").pushHeader("t"), basic("x-token-auth:t"))
        XCTAssertEqual(host("bitbucket", "x").pushHeader("me@example.com:t"), basic("me@example.com:t"))
    }

    func testCreatesCommentWhenNoneExists() throws {
        for kind in kinds {
            let s = try server { r in r.method == "GET" ? self.ok(self.page(kind, [self.comment(1, "hello", kind)])) : .init(status: 201, body: "{}") }
            let result = host(kind, s.url).upsertComment(pr: "7", body: "<!-- swiftshot -->\nbody é", token: token, http: URLSessionHttp())
            XCTAssertEqual(result.action, "created", kind)
            XCTAssertEqual(s.seen.count, 2, kind)
            let get = s.seen[0]
            XCTAssertTrue(get.target.hasPrefix(listPath(kind) + "?"), get.target)
            XCTAssertTrue(get.target.contains(kind == "bitbucket" ? "pagelen=100&page=1" : "per_page=100&page=1"), get.target)
            if kind == "gitlab" { XCTAssertTrue(get.target.contains("sort=asc"), get.target) }
            let post = s.seen[1]
            XCTAssertEqual(post.method, "POST", kind)
            XCTAssertEqual(post.target, listPath(kind), kind)
            XCTAssertEqual(try bodyOf(kind, post.body), "<!-- swiftshot -->\nbody é", kind)
            let auth = host(kind, "x").authHeader(token)
            XCTAssertEqual(post.headers[auth.0.lowercased()], auth.1, kind)
        }
    }

    func testUpdatesExistingMarkedComment() throws {
        for kind in kinds {
            let full = (1...100).map { comment($0, "chatter \($0)", kind) }
            let s = try server { r in
                if r.method == "GET" && r.target.contains("&page=1") { return self.ok(self.page(kind, full, next: true)) }
                if r.method == "GET" && r.target.contains("&page=2") { return self.ok(self.page(kind, [self.comment(555, "text <!-- swiftshot -->", kind), self.comment(777, "<!-- swiftshot -->\nold", kind)])) }
                return self.ok("{}")
            }
            let result = host(kind, s.url).upsertComment(pr: "7", body: "<!-- swiftshot -->\nnew", token: token, http: URLSessionHttp())
            XCTAssertEqual(result.action, "updated", kind)
            let write = s.seen.last!
            XCTAssertEqual(write.method, kind == "github" ? "PATCH" : "PUT", kind)
            XCTAssertEqual(write.target, itemPath(kind, 777), kind)
            XCTAssertEqual(try bodyOf(kind, write.body), "<!-- swiftshot -->\nnew", kind)
            XCTAssertEqual(s.seen.count, 3, kind)
        }
    }

    func testIgnoresUnmarkedComments() throws {
        for kind in kinds {
            let s = try server { r in
                r.method == "GET" ? self.ok(self.page(kind, [self.comment(1, "no marker", kind), self.comment(2, " <!-- swiftshot -->\nnot first", kind), self.comment(3, "x\n<!-- swiftshot -->", kind)])) : .init(status: 201, body: "{}")
            }
            XCTAssertEqual(host(kind, s.url).upsertComment(pr: "7", body: marked, token: token, http: URLSessionHttp()).action, "created", kind)
            XCTAssertEqual(s.seen.last?.method, "POST", kind)
        }
    }

    func testScansAtMostTenPages() throws {
        let s = try server { r in r.method == "GET" ? self.ok(self.page("github", (1...100).map { self.comment($0, "c", "github") })) : .init(status: 201, body: "{}") }
        XCTAssertEqual(host("github", s.url).upsertComment(pr: "7", body: marked, token: token, http: URLSessionHttp()).action, "created")
        XCTAssertEqual(s.seen.count, 11)
        XCTAssertTrue(s.seen[9].target.contains("page=10"))
    }

    func testFailuresAreReported() throws {
        for kind in kinds {
            for status in [401, 404, 500] {
                let s = try server { _ in .init(status: status, body: "no") }
                XCTAssertEqual(host(kind, s.url).upsertComment(pr: "7", body: marked, token: token, http: URLSessionHttp()).failure, "\(status)", kind)
            }
            let s = try server { r in r.method == "GET" ? self.ok(self.page(kind, [])) : .init(status: 403, body: "no") }
            XCTAssertEqual(host(kind, s.url).upsertComment(pr: "7", body: marked, token: token, http: URLSessionHttp()).failure, "403", kind)
            let bad = try server { _ in self.ok("{not json") }
            XCTAssertEqual(host(kind, bad.url).upsertComment(pr: "7", body: marked, token: token, http: URLSessionHttp()).failure, "200", kind)
        }
    }

    func testConnectionRefusedIsAFailure() throws {
        let dead = try server { _ in self.ok("[]") }
        dead.stop()
        XCTAssertEqual(host("github", dead.url).upsertComment(pr: "7", body: marked, token: token, http: URLSessionHttp()).failure, "no response")
    }

    func testRedirectNotFollowed() throws {
        let elsewhere = try server { _ in self.ok("[]") }
        for kind in kinds {
            let s = try server { _ in .init(status: 302, body: "", headers: ["Location": elsewhere.url + "/stolen"]) }
            XCTAssertEqual(host(kind, s.url).upsertComment(pr: "7", body: marked, token: token, http: URLSessionHttp()).failure, "302", kind)
        }
        XCTAssertEqual(elsewhere.seen.count, 0)
    }

    final class Recording: Http, @unchecked Sendable {
        var requests: [String] = []
        let reply: (String) -> HttpReply
        init(_ reply: @escaping (String) -> HttpReply = { _ in HttpReply(status: 200, body: "[]") }) { self.reply = reply }
        func send(method: String, url: String, headers: [String: String], body: String?) throws -> HttpReply { requests.append("\(method) \(url)"); return reply(method) }
    }

    func testHttpRefusedForToken() {
        let http = Recording()
        XCTAssertEqual(host("github", "http://git.example.com/api").upsertComment(pr: "7", body: marked, token: token, http: http).failure, "https only")
        XCTAssertEqual(http.requests, [])
        _ = host("github", "https://git.example.com/api").upsertComment(pr: "7", body: marked, token: token, http: http)
        XCTAssertEqual(http.requests.first, "GET https://git.example.com/api/repos/owner/name/issues/7/comments?per_page=100&page=1")
    }

    func testPullRequestMustBeANumber() throws {
        let s = try server { _ in self.ok("[]") }
        XCTAssertEqual(host("github", s.url).upsertComment(pr: "7/../x", body: "b", token: token, http: URLSessionHttp()).failure, "invalid pull request")
        XCTAssertEqual(s.seen.count, 0)
    }

    // The verify step: when, and what is printed

    var repos = 0

    func repoWithOrigin(_ url: String) -> URL {
        repos += 1
        let dir = tmp.appendingPathComponent("repo\(repos)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertEqual(Proc.run(["git", "init", "-q"], cwd: dir).code, 0)
        XCTAssertEqual(Proc.run(["git", "remote", "add", "origin", url], cwd: dir).code, 0)
        return dir
    }

    let gitlabCi = Ci(provider: "gitlab", commit: "abc", branch: "feature/x", pullRequest: "7", fork: false, buildUrl: "https://ci.example/job/1", repository: nil, isCi: true)

    func post(_ ci: Ci?, _ env: [String: String], _ log: Console, _ http: Http, dir: URL? = nil) {
        PullRequestComment.post("<!-- swiftshot -->\nbody", ci: ci, env: env, projectDir: dir ?? repoWithOrigin("https://gitlab.com/group/name.git"), log: log, http: http)
    }

    func testNoCommentWithoutTokenOrPr() {
        let http = Recording()
        let log = Console(capture: true)
        post(gitlabCi, [:], log, http)
        post(gitlabCi, ["SWIFTSHOT_HOST_TOKEN": ""], log, http)
        var noPr = gitlabCi; noPr.pullRequest = nil
        post(noPr, ["SWIFTSHOT_HOST_TOKEN": token], log, http)
        post(nil, ["SWIFTSHOT_HOST_TOKEN": token], log, http)
        XCTAssertEqual(http.requests, [])
        XCTAssertEqual(log.text, "")
    }

    func testUnknownHostIsOneInfoLineWithoutTheToken() {
        let http = Recording()
        let log = Console(capture: true)
        post(gitlabCi, ["SWIFTSHOT_HOST_TOKEN": token], log, http, dir: repoWithOrigin("https://git.corp.example/g/n.git"))
        XCTAssertEqual(http.requests, [])
        XCTAssertEqual(log.text.split(separator: "\n").count, 1, log.text)
        XCTAssertFalse(log.text.contains(token))
    }

    func testCommentFailureIsWarning() throws {
        for status in [401, 500] {
            let log = Console(capture: true)
            post(gitlabCi, ["SWIFTSHOT_HOST_TOKEN": token], log, Recording { _ in HttpReply(status: status, body: "x") })
            XCTAssertEqual(log.text, "couldn't comment on the pull request (gitlab \(status))\n")
        }
        let refused = try server { _ in self.ok("[]") }
        refused.stop()
        let log = Console(capture: true)
        post(gitlabCi, ["SWIFTSHOT_HOST_TOKEN": token, "SWIFTSHOT_HOST_API": refused.url], log, URLSessionHttp())
        XCTAssertEqual(log.text, "couldn't comment on the pull request (gitlab no response)\n")
    }

    func testPostsToTheHostOfTheRemote() throws {
        let s = try server { r in r.method == "GET" ? self.ok("[]") : .init(status: 201, body: "{}") }
        let log = Console(capture: true)
        post(gitlabCi, ["SWIFTSHOT_HOST_TOKEN": token, "SWIFTSHOT_HOST_API": s.url], log, URLSessionHttp())
        XCTAssertEqual(log.text, "")
        XCTAssertEqual(s.seen.map(\.method), ["GET", "POST"])
        XCTAssertEqual(s.seen[1].target, "/projects/group%2Fname/merge_requests/7/notes")
        XCTAssertEqual(s.seen[1].headers["private-token"], token)
    }

    func testTokenNeverInOutput() throws {
        let s = try server { _ in .init(status: 403, body: "{\"message\":\"bad token \(self.token)\"}") }
        let log = Console(capture: true)
        post(gitlabCi, ["SWIFTSHOT_HOST_TOKEN": token, "SWIFTSHOT_HOST_API": s.url], log, URLSessionHttp())
        post(gitlabCi, ["SWIFTSHOT_HOST_TOKEN": token, "SWIFTSHOT_HOST_API": "http://git.example.com/api"], log, URLSessionHttp())
        XCTAssertFalse(log.text.isEmpty)
        XCTAssertFalse(log.text.contains(token), log.text)
    }

    func verifyEnv() -> [String: String] {
        ["SWIFTSHOT_COMMIT": "0123456789abcdef0123456789abcdef01234567", "SWIFTSHOT_BRANCH": "feature/x", "GITLAB_CI": "true", "CI_MERGE_REQUEST_IID": "7", "CI_JOB_URL": "https://ci.example/job/1"]
    }

    func runVerify(_ s: RecordingServer, _ log: Console) throws -> Int32 {
        let c = fixtures.appendingPathComponent("changed-pixels")
        let vars = verifyEnv()
        let env = BaselineEnv.detect(tmp, env: vars, readFile: { _ in nil }, version: "1.0.0-test")
        XCTAssertEqual(env.ci?.pullRequest, "7")
        let config = CompareConfig.from(try Options.parse(["verify", "--config", c.appendingPathComponent("config.json").path]))
        return try Baseline.verify(output: c.appendingPathComponent("output"), baseline: c.appendingPathComponent("baseline"), report: tmp.appendingPathComponent("verify-report"),
                                   config: config, env: env, log: log, processEnv: vars.merging(["SWIFTSHOT_HOST_TOKEN": token, "SWIFTSHOT_HOST_API": s.url]) { $1 }, out: { _ in },
                                   projectDir: repoWithOrigin("https://gitlab.com/group/name.git"))
    }

    func testVerifyExitCodeIsUnchangedByAFailingComment() throws {
        let s = try server { _ in .init(status: 401, body: "no") }
        let log = Console(capture: true)
        XCTAssertEqual(try runVerify(s, log), 1)
        XCTAssertTrue(log.text.contains("couldn't comment on the pull request (gitlab 401)\n"), log.text)
        XCTAssertEqual(try String(contentsOf: tmp.appendingPathComponent("verify-report/summary.md"), encoding: .utf8).split(separator: "\n").first, "<!-- swiftshot -->")
    }

    func testCommentBodyIsTheSummary() throws {
        let s = try server { r in r.method == "GET" ? self.ok("[]") : .init(status: 201, body: "{}") }
        _ = try runVerify(s, Console(capture: true))
        XCTAssertEqual(try String(contentsOf: tmp.appendingPathComponent("verify-report/summary.md"), encoding: .utf8), try bodyOf("gitlab", s.seen.last!.body))
    }
}
