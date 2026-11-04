import Foundation

/// A reply to `Http.send`; the body is read as text.
struct HttpReply { let status: Int; let body: String }

/// There was no reply (refused, timed out, not a URL).
struct HttpError: Error {}

/// The one HTTP call the git host needs; tests give it their own. Throws `HttpError` when there is no reply.
protocol Http {
    func send(method: String, url: String, headers: [String: String], body: String?) throws -> HttpReply
}

/// The real `Http`: a redirect is a reply like any other, never followed (a token would follow it).
final class URLSessionHttp: Http {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private final class Box: @unchecked Sendable { var data: Data?; var response: HTTPURLResponse? }

    func send(method: String, url: String, headers: [String: String], body: String?) throws -> HttpReply {
        guard let u = URL(string: url) else { throw HttpError() }
        var request = URLRequest(url: u, timeoutInterval: 60)
        request.httpMethod = method
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = body.map { Data($0.utf8) }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, _ in
            box.data = data
            box.response = response as? HTTPURLResponse
            done.signal()
        }.resume()
        done.wait()
        session.finishTasksAndInvalidate()
        guard let response = box.response else { throw HttpError() }
        return HttpReply(status: response.statusCode, body: String(decoding: box.data?.prefix(16 << 20) ?? Data(), as: UTF8.self))
    }
}

/// What `Host.upsertComment` did: `action` is `created` or `updated`; `failure` is a status code or a short reason, never a body.
struct CommentResult {
    var action: String?
    var failure: String?
    var ok: Bool { failure == nil }
}

/// The git host of the repository (docs/wiki/Baseline-format.md, "Git host"): where verify comments on the pull
/// request. `api` is the API base, `project` the path in the remote, `web` the project's web address.
struct Host: Equatable {
    var kind: String
    var api: String
    var project: String
    var web: String

    private static let kinds: Set<String> = ["github", "gitlab", "bitbucket"]
    private struct Remote { let scheme: String?; let host: String; let port: String?; let path: [String] }

    /// `https://[user@]host[:port]/a/b[.git]`, `ssh://git@host[:port]/a/b[.git]`, `git@host:a/b[.git]`.
    private static func parse(_ remote: String) -> Remote? {
        let s = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        var scheme: String?
        var host: String, port: String?, rawPath: String
        if let sep = s.range(of: "://") {
            let name = String(s[..<sep.lowerBound])
            guard let first = name.first, first.isASCII, first.isLetter, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) }) else { return nil }
            let rest = s[sep.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            var authority = String(rest[..<slash])
            rawPath = String(rest[rest.index(after: slash)...])
            if let at = authority.lastIndex(of: "@") {
                guard !authority[..<at].contains("/") else { return nil }
                authority = String(authority[authority.index(after: at)...])
            }
            if authority.hasPrefix("[") {
                guard let close = authority.firstIndex(of: "]") else { return nil }
                host = String(authority[...close])
                let tail = authority[authority.index(after: close)...]
                if tail.isEmpty { port = nil } else if tail.hasPrefix(":"), tail.count > 1, tail.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }) { port = String(tail.dropFirst()) } else { return nil }
            } else if let colon = authority.firstIndex(of: ":") {
                host = String(authority[..<colon])
                let p = authority[authority.index(after: colon)...]
                guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
                port = String(p)
            } else {
                host = authority
                port = nil
            }
            scheme = name.lowercased()
        } else {
            guard let at = s.firstIndex(of: "@"), let colon = s[at...].firstIndex(of: ":") else { return nil }
            let user = s[..<at], h = s[s.index(after: at)..<colon], p = s[s.index(after: colon)...]
            guard !user.isEmpty, !user.contains(where: { "/:".contains($0) || $0.isWhitespace }),
                  !h.isEmpty, !h.contains(where: { "/:".contains($0) || $0.isWhitespace }), !p.isEmpty, !p.hasPrefix("//") else { return nil }
            host = String(h)
            port = nil
            rawPath = String(p)
        }
        guard !host.isEmpty, !host.contains("@") else { return nil }
        var path = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts.contains(".") , !parts.contains("..") else { return nil }
        return Remote(scheme: scheme, host: host.lowercased(), port: port, path: parts)
    }

    /// The host of `remoteUrl` (`git remote get-url origin`); nil when it isn't a known one. `env` is the process environment.
    static func detect(_ remoteUrl: String?, env: [String: String]) -> Host? {
        func v(_ k: String) -> String? { env[k].flatMap { $0.isEmpty ? nil : $0 } }
        guard let r = remoteUrl.flatMap(parse) else { return nil }
        func sameHost(_ url: String?) -> Bool { url.flatMap { URL(string: $0)?.host?.lowercased() } == r.host }
        let enterprise = v("GITHUB_ACTIONS")?.lowercased() == "true" && sameHost(v("GITHUB_SERVER_URL"))
        let kind: String
        if let forced = v("SWIFTSHOT_GIT_HOST")?.lowercased(), kinds.contains(forced) { kind = forced }
        else if r.host == "github.com" { kind = "github" }
        else if r.host == "bitbucket.org" { kind = "bitbucket" }
        else if r.host == "gitlab.com" { kind = "gitlab" }
        else if enterprise { kind = "github" }
        else if sameHost(v("CI_API_V4_URL")) { kind = "gitlab" }
        else { return nil }
        let web = r.scheme == "http" || r.scheme == "https" ? r.scheme! : "https"
        let base = "\(web)://\(r.host)" + (web == r.scheme ? r.port.map { ":\($0)" } ?? "" : "")
        let project = r.path.joined(separator: "/")
        if kind != "gitlab" && r.path.count != 2 { return nil }
        var api: String
        if let o = v("SWIFTSHOT_HOST_API") { api = o }
        else {
            switch kind {
            case "github": api = (enterprise ? v("GITHUB_API_URL") : nil) ?? (r.host == "github.com" ? "https://api.github.com" : "\(base)/api/v3")
            case "bitbucket": api = "https://api.bitbucket.org/2.0"
            default: api = v("CI_API_V4_URL").flatMap { sameHost($0) ? $0 : nil } ?? "\(base)/api/v4"
            }
        }
        while api.hasSuffix("/") { api.removeLast() }
        return Host(kind: kind, api: api, project: project, web: "\(base)/\(project)")
    }

    private static func basic(_ s: String) -> String { "Basic " + Data(s.utf8).base64EncodedString() }

    /// A URL path segment, percent-encoded.
    static func encode(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            let c = Character(UnicodeScalar(b))
            if b < 128, c.isLetter || c.isNumber || "-._~".contains(c) { out.append(c) } else { out += String(format: "%%%02X", b) }
        }
        return out
    }

    /// The header an API call carries. GitLab's job token can't write notes, so only a user's or project's token fits here.
    func authHeader(_ token: String) -> (String, String) {
        if kind == "gitlab" { return ("PRIVATE-TOKEN", token) }
        if kind == "bitbucket", token.contains(":") { return ("Authorization", Host.basic(token)) }
        return ("Authorization", "Bearer \(token)")
    }

    /// The value of `http.extraHeader` for `git push`; `jobToken` is `CI_JOB_TOKEN`, which GitLab wants under another user name.
    func pushHeader(_ token: String, jobToken: String? = nil) -> String {
        "Authorization: " + {
            switch kind {
            case "github": return Host.basic("x-access-token:\(token)")
            case "gitlab": return Host.basic((token == jobToken ? "gitlab-ci-token" : "oauth2") + ":\(token)")
            default: return Host.basic(token.contains(":") ? token : "x-token-auth:\(token)")
            }
        }()
    }

    private var path: String { project.split(separator: "/").map { Host.encode(String($0)) }.joined(separator: "/") }

    private func listUrl(_ pr: String, _ page: Int) -> String {
        switch kind {
        case "github": return "\(api)/repos/\(path)/issues/\(pr)/comments?per_page=100&page=\(page)"
        case "gitlab": return "\(api)/projects/\(project.split(separator: "/").map { Host.encode(String($0)) }.joined(separator: "%2F"))/merge_requests/\(pr)/notes?per_page=100&page=\(page)&sort=asc"
        default: return "\(api)/repositories/\(path)/pullrequests/\(pr)/comments?pagelen=100&page=\(page)"
        }
    }

    private func itemUrl(_ pr: String, _ id: String) -> String {
        kind == "github" ? "\(api)/repos/\(path)/issues/comments/\(id)" : "\(listUrl(pr, 1).split(separator: "?")[0])/\(id)"
    }

    /// The comments of a page as (id, text), and whether there may be a next page; nil when it isn't a page of comments.
    /// A comment whose id isn't a whole number that fits 64 bits is skipped.
    private func comments(_ json: String) -> (items: [(id: String, text: String)], more: Bool)? {
        guard let root = try? JSON.parse(json) else { return nil }
        guard let list = kind == "bitbucket" ? root["values"]?.array : root.array else { return nil }
        var items: [(id: String, text: String)] = []
        for c in list {
            guard let o = c.object else { return nil }
            let id: String
            switch o["id"] {
            case .int(let i)?: id = String(i)
            case .double(let d)?:
                guard let i = Int64(exactly: d) else { continue }
                id = String(i)
            default: return nil
            }
            let text = kind == "bitbucket" ? o["content"]?["raw"]?.string : o["body"]?.string
            items.append((id, text ?? ""))
        }
        return (items, kind == "bitbucket" ? root["next"] != nil : list.count >= 100)
    }

    /// Writes `body` (which starts with `Summary.marker`) as a comment on pull request `pr`: the first comment that
    /// starts with the marker is updated, else a new one is made. Looks at most 10 pages of 100. Nothing is sent over
    /// plain http unless the host is this machine; no reply body is ever kept.
    func upsertComment(pr: String, body: String, token: String, http: Http) -> CommentResult {
        func fail(_ why: String) -> CommentResult { CommentResult(action: nil, failure: why) }
        guard !pr.isEmpty, pr.count <= 18, pr.allSatisfy({ $0.isASCII && $0.isNumber }) else { return fail("invalid pull request") }
        guard let origin = URL(string: api), let host = origin.host?.lowercased(), let scheme = origin.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && Download.loopback.contains(host)) else { return fail("https only") }
        let (authName, authValue) = authHeader(token)
        let headers = [authName: authValue, "Accept": "application/json", "Content-Type": "application/json", "User-Agent": "swiftshot"]
        func call(_ method: String, _ url: String, _ payload: String? = nil) -> HttpReply? { try? http.send(method: method, url: url, headers: headers, body: payload) }
        var existing: String?
        for page in 1...10 {
            guard let reply = call("GET", listUrl(pr, page)) else { return fail("no response") }
            guard (200...299).contains(reply.status) else { return fail("\(reply.status)") }
            guard let (items, more) = comments(reply.body) else { return fail("\(reply.status)") }
            existing = items.first { $0.text.hasPrefix(Summary.marker) }?.id
            if existing != nil || !more { break }
        }
        let payload = (kind == "bitbucket" ? JSON.object(["content": .object(["raw": .string(body)])]) : JSON.object(["body": .string(body)])).compact()
        let reply: HttpReply?
        if let existing { reply = call(kind == "github" ? "PATCH" : "PUT", itemUrl(pr, existing), payload) }
        else { reply = call("POST", String(listUrl(pr, 1).split(separator: "?")[0]), payload) }
        guard let reply else { return fail("no response") }
        return (200...299).contains(reply.status) ? CommentResult(action: existing == nil ? "created" : "updated", failure: nil) : fail("\(reply.status)")
    }
}

/// verify's last step: the comment on the pull request (docs/wiki/Baseline-format.md, "Git host").
enum PullRequestComment {
    /// Comments `body` when `SWIFTSHOT_HOST_TOKEN` is set and the CI run is for a pull request. A failure is one
    /// warning and never changes verify's exit code; the token is never printed. `projectDir` is where `git` finds the origin.
    static func post(_ body: String, ci: Ci?, env: [String: String], projectDir: URL?, log: Console, http: Http = URLSessionHttp()) {
        guard let token = env["SWIFTSHOT_HOST_TOKEN"], !token.isEmpty, let pr = ci?.pullRequest else { return }
        guard let host = Host.detect(origin(projectDir), env: env) else {
            log.plain("SWIFTSHOT_HOST_TOKEN is set but the git host of origin is unknown; set SWIFTSHOT_GIT_HOST to github, gitlab or bitbucket")
            return
        }
        let result = host.upsertComment(pr: pr, body: body, token: token, http: http)
        if !result.ok { log.warn("couldn't comment on the pull request (\(host.kind) \(result.failure ?? ""))") }
    }

    /// `git remote get-url origin` in the repository containing `dir`; nil when there is none.
    private static func origin(_ dir: URL?) -> String? {
        let r = Proc.run(["git", "remote", "get-url", "origin"], cwd: dir)
        let out = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.code == 0 && !out.isEmpty ? out : nil
    }
}
