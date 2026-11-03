import Foundation

struct Problem: Error { let reason: String }
func matches(_ s: String, _ pattern: String) -> Bool {
    s.range(
        of: "^(?:" + pattern + ")$",
        options: .regularExpression
    ) != nil
}
func validName(_ s: String) -> Bool {
    matches(s, "[a-z][a-z0-9_]{0,19}")
}
func role(_ s: String) -> Bool {
    matches(s, "[a-z]{1,16}")
}
func unreserved(_ c: UInt8) -> Bool {
    (65...90).contains(c) || (97...122).contains(c) || (48...57).contains(c) || [
        45,
        46,
        95,
        126
    ].contains(c)
}
func segment(_ s: String) -> Bool {
    !s.isEmpty && s != "." && s != ".." && s.utf8.allSatisfy(unreserved)
}
func canonical(_ s: String) -> Bool {
    s == "/" ||
        (s.hasPrefix("/") && String(s.dropFirst()).components(separatedBy: "/").allSatisfy(segment))
}
func mediaPart(_ s: String) -> Bool {
    matches(s, "[a-z0-9.+-]+")
}
func media(_ s: String) -> Bool {
    let p = s.components(separatedBy: "/")
    return p.count == 2 && p.allSatisfy(mediaPart)
}
func intParameter(_ s: String) -> Bool {
    matches(s, "[0-9]{1,9}")
}
func slug(_ s: String) -> Bool {
    matches(s, "[a-z0-9-]+")
}
func trim(_ s: String) -> String {
    s.trimmingCharacters(in: CharacterSet(charactersIn: " "))
}
func cut(_ s: String, _ a: Int, _ b: Int? = nil) -> String {
    String(
        decoding: Array(s.utf8)[a..<(b ?? s.utf8.count)],
        as: UTF8.self
    )
}
func splitFirst(_ s: String, _ separator: Character) -> (String, String)? {
    guard let at = s.firstIndex(of: separator) else {
        return nil
    }
    return (String(s[..<at]), String(s[s.index(after: at)...]))
}
func hex(_ c: UInt8) -> Int? {
    switch c { case 48...57:
        return Int(c - 48)
    case 65...70:
        return Int(c - 65 + 10)
    case 97...102:
        return Int(c - 97 + 10)
    default:
        return nil }
}
func validEscapes(_ s: String) -> Bool {
    let b = Array(s.utf8)
    var at = 0
    while at < b.count {
        if b[at] ==
            37
        {
            guard at + 2 < b.count, let a = hex(b[at + 1]), let c = hex(b[at + 2]),
                  (32...126).contains(a * 16 + c)
            else {
                return false
            }
            at += 3
        } else {
            at += 1
        }
    }
    return true
}
func decode(_ s: String) -> String {
    let b = Array(s.utf8)
    var at = 0, out: [UInt8] = []
    while at < b.count {
        if b[at] == 37 {
            out.append(UInt8(hex(b[at + 1])! * 16 + hex(b[at + 2])!))
            at += 3
        } else {
            out.append(b[at])
            at += 1
        }
    }
    return String(decoding: out, as: UTF8.self)
}
func encode(_ s: String) -> String {
    s.utf8.map { unreserved($0) ? String(UnicodeScalar($0)) : String(
        format: "%%%02X",
        Int($0)
    ) }.joined()
}
func normalize(_ path: String) -> String {
    let b = Array(path.utf8)
    var at = 0, text = ""
    while at < b.count {
        if b[at] == 37 {
            let c = UInt8(hex(b[at + 1])! * 16 + hex(b[at + 2])!)
            text += unreserved(c) ? String(UnicodeScalar(c)) : String(format: "%%%02X", Int(c))
            at += 3
        } else {
            text += String(UnicodeScalar(b[at]))
            at += 1
        }
    }
    var parts: [String] = []
    for p in String(text.dropFirst()).components(separatedBy: "/") {
        if p.isEmpty || p == "." {
            continue
        }
        if p == ".." {
            if !parts.isEmpty {
                parts.removeLast()
            }
        } else {
            parts.append(p)
        }
    }
    return "/" + parts.joined(separator: "/")
}
struct Piece { let kind: Character, value: String }
func parsePattern(_ s: String) -> [Piece]? {
    if s == "/" {
        return []
    }
    guard s.hasPrefix("/") else {
        return nil
    }
    let parts = String(s.dropFirst()).components(separatedBy: "/")
    var pieces: [Piece] = [], names = Set<String>()
    for (i, p) in parts.enumerated() {
        if segment(p) {
            pieces.append(Piece(kind: "l", value: p))
            continue
        }
        guard p.hasPrefix("{") && p.hasSuffix("}") else {
            return nil
        }
        let inner = String(p.dropFirst().dropLast()), kind: Character, value: String
        if inner.hasPrefix("*") {
            guard i == parts.count - 1
            else {
                return nil
            }
            kind = "w"
            value = String(inner.dropFirst())
        } else if let (v, t) = splitFirst(inner, ":") {
            guard t == "int" || t == "slug"
            else {
                return nil
            }
            kind = t == "int" ? "i" : "s"
            value = v
        } else {
            kind = "p"
            value = inner
        }
        guard validName(value), names.insert(value).inserted else {
            return nil
        }
        pieces.append(Piece(kind: kind, value: value))
    }
    return pieces
}
final class Route {
    let name: String, methods: Set<String>, pattern: String, pieces: [Piece], role: String
    var types: [String]? = nil, count = 0
    init(_ name: String, _ methods: Set<String>, _ pattern: String, _ pieces: [Piece], _ role: String) {
        self.name = name
        self.methods = methods
        self.pattern = pattern
        self.pieces = pieces
        self.role = role
    }
    func fits(_ parts: [String]) -> Bool {
        let wildcard = pieces.last?.kind == "w", m = pieces.count - (wildcard ? 1 : 0)
        guard wildcard ? parts.count >= m : parts.count == m else {
            return false
        }
        for i in 0..<m {
            let p = pieces[i], x = parts[i]
            if (p.kind == "l" && p.value != x) || (p.kind == "i" && !intParameter(x)) ||
                (p.kind == "s" && !slug(x))
            {
                return false
            }
        }
        return true
    }
    func parameters(_ parts: [String]) -> [(String, String)] {
        var result: [(String, String)] = []
        for (i, p) in pieces.enumerated() {
            if p.kind == "l" {
                continue
            }
            let value: String
            switch p.kind { case "w":
                value = parts[i...].map(decode).joined(separator: "/")
            case "i":
                value = String(Int(parts[i])!)
            case "s":
                value = parts[i]
            default:
                value = decode(parts[i]) }
            result.append((p.value, value))
        }
        return result.sorted { $0.0 < $1.0 }
    }
}
struct Redirect { let from: String, to: String, prefix: Bool, code: Int }
struct Client { var level: Int, last: Int, allowed = 0, limited = 0 }
struct Response {
    var status: Int, headers: [String: String] = [:], body: String, head = false, contentType = "text/plain"
    init(_ status: Int, _ body: String = "", _ headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }
}
final class Router {
    var routes: [Route] = [], priority: [Int] = [], tokens: [String: String] = [:], redirects: [Redirect] = [],
        origins = Set<String>(), limit: (
            Int,
            Int
        )? = nil, clients: [String: Client] = [:], statuses: [Int: Int] = [:], configErrors = 0
    func config(_ w: [String]) throws {
        let command = w[0], args = w.count - 1
        func require(_ condition: Bool, _ reason: String) throws {
            if !condition {
                throw Problem(reason: reason)
            }
        }
        try require(
            ["ROUTE", "TOKEN", "REDIRECT", "ORIGIN", "LIMIT", "TYPES"].contains(command),
            "unknown command \(command)"
        )
        let correct: Bool
        switch command { case "ROUTE":
            correct = args == 3 || args == 5
        case "TOKEN", "LIMIT":
            correct = args == 2
        case "REDIRECT":
            correct = args == 3
        case "ORIGIN":
            correct = args == 1
        default:
            correct = args >= 2 }
        try require(correct, "wrong number of arguments")
        switch command {
        case "ROUTE":
            try require(validName(w[1]), "bad route name \(w[1])")
            try require(!routes.contains { $0.name == w[1] }, "duplicate route \(w[1])")
            let methods = w[2].components(separatedBy: ","), set = Set(methods)
            try require(
                methods.allSatisfy { ["GET", "POST", "PUT", "PATCH", "DELETE"].contains($0) } && set.count == methods
                    .count,
                "bad methods \(w[2])"
            )
            guard let pieces = parsePattern(w[3]) else {
                throw Problem(reason: "bad pattern \(w[3])")
            }
            if args == 5 {
                try require(w[4] == "ROLE", "unknown option \(w[4])")
                try require(role(w[5]), "bad role \(w[5])")
            }
            routes.append(Route(w[1], set, w[3], pieces, args == 5 ? w[5] : "none"))
        case "TOKEN":
            try require(matches(w[1], "[A-Za-z0-9._-]{1,32}"), "bad token \(w[1])")
            try require(tokens[w[1]] == nil, "duplicate token \(w[1])")
            try require(role(w[2]), "bad role \(w[2])")
            tokens[w[1]] = w[2]
        case "REDIRECT":
            func rule(_ s: String) -> Bool {
                canonical(s) ||
                    (s.hasSuffix("/*") && String(s.dropLast(2)) != "/" && canonical(String(s.dropLast(2))))
            }
            try require(rule(w[1]), "bad path \(w[1])")
            try require(rule(w[2]), "bad path \(w[2])")
            let p = w[1].hasSuffix("/*")
            try require(p == w[2].hasSuffix("/*"), "wildcard mismatch")
            try require(["301", "302", "307", "308"].contains(w[3]), "bad redirect code \(w[3])")
            let from = p ? String(w[1].dropLast(2)) : w[1], to = p ? String(w[2].dropLast(2)) : w[2]
            try require(!redirects.contains { $0.prefix == p && $0.from == from }, "duplicate redirect \(w[1])")
            redirects.append(Redirect(from: from, to: to, prefix: p, code: Int(w[3])!))
        case "ORIGIN":
            try require(matches(w[1], "https?://[a-z0-9.:-]+"), "bad origin \(w[1])")
            try require(!origins.contains(w[1]), "duplicate origin \(w[1])")
            origins.insert(w[1])
        case "LIMIT":
            guard matches(w[1], "[1-9][0-9]*"), matches(w[2], "[1-9][0-9]*"), let n = Int(w[1]), let s = Int(w[2]),
                  (1...100).contains(n), (1...3600).contains(s)
            else {
                throw Problem(reason: "bad limit")
            }
            try require(limit == nil, "duplicate limit")
            limit = (n, s)
        default:
            guard let r = routes.first(where: { $0.name == w[1] })
            else {
                throw Problem(reason: "unknown route \(w[1])")
            }
            try require(r.types == nil, "duplicate types \(w[1])")
            var seen = Set<String>()
            for t in w.dropFirst(2) {
                try require(media(t), "bad media type \(t)")
                try require(seen.insert(t).inserted, "duplicate media type \(t)")
            }
            r.types = Array(w.dropFirst(2))
        }
    }
    func table() {
        let rate = limit.map { "\($0.0)/\($0.1)" } ?? "none"
        print(
            "CONFIG routes=\(routes.count) tokens=\(tokens.count) redirects=\(redirects.count) origins=\(origins.count) limit=\(rate) errors=\(configErrors)"
        )
        for r in routes where r.types == nil {
            r.types = ["application/json"]
        }
        priority = routes.indices.sorted { a, b in
            let x = routes[a], y = routes[b], xl = x.pieces.filter { $0.kind == "l" }.count,
                yl = y.pieces.filter { $0.kind == "l" }.count
            if xl != yl {
                return xl > yl
            }
            let xt = x.pieces.filter { $0.kind == "i" || $0.kind == "s" }.count,
                yt = y.pieces.filter { $0.kind == "i" || $0.kind == "s" }.count
            if xt != yt {
                return xt > yt
            }
            let xw = x.pieces.contains { $0.kind == "w" }, yw = y.pieces.contains { $0.kind == "w" }
            return xw != yw ? !xw : a < b
        }
        for (rank, i) in priority.enumerated() {
            let r = routes[i]
            var methods = r.methods
            if methods.contains("GET") {
                methods.insert("HEAD")
            }
            print(
                "TABLE \(rank + 1) \(r.name) \(methods.sorted().joined(separator: ",")) \(r.pattern) role=\(r.role == "none" ? "-" : r.role) types=\(r.types!.joined(separator: ","))"
            )
        }
    }
    func request(_ line: String, _ raw: [String]) -> Response {
        let w = line.components(separatedBy: " ")
        guard w.count == 3, matches(w[0], "[A-Z]{1,16}"), w[1].hasPrefix("/"), !w[1].contains("#"),
              w[2] == "HTTP/1.1"
        else {
            return Response(
                400,
                "bad request: request line"
            )
        }
        let head = w[0] == "HEAD"
        func bad(_ body: String) -> Response {
            var r = Response(400, body)
            r.head = head
            return r
        }
        guard validEscapes(w[1]) else {
            return bad("bad request: percent escape")
        }
        var headers: [String: String] = [:]
        for (i, row) in raw.enumerated() {
            guard let (name, value) = splitFirst(row, ":"),
                  matches(name, "[A-Za-z0-9-]+")
            else {
                return bad("bad request: header line \(i + 1)")
            }
            let key = name.lowercased()
            if headers[key] != nil {
                return bad("bad request: duplicate header \(key)")
            }
            headers[key] = trim(value)
        }
        var response = validRequest(w[0], w[1], headers)
        response.head = head
        if let origin = headers["origin"], origins.contains(origin) {
            response.headers["Access-Control-Allow-Origin"] = origin
            if response
                .status == 204 && headers["access-control-request-method"] !=
                nil
            {
                response.headers["Access-Control-Allow-Methods"] = response.headers["Allow"]!
            }
        }
        return response
    }
    func validRequest(_ method: String, _ target: String, _ h: [String: String]) -> Response {
        if !["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"].contains(method) {
            return Response(
                501,
                "not implemented: \(method)"
            )
        }
        if (h["host"] ?? "").isEmpty {
            return Response(400, "bad request: missing host")
        }
        var effective = method
        if let value = h["x-http-method-override"] {
            guard method == "POST" && ["PUT", "PATCH", "DELETE"].contains(value) else {
                return Response(
                    400,
                    "bad request: method override"
                )
            }
            effective = value
        }
        if let client = h["x-client"], !client.isEmpty {
            let time = Int(h["x-time"]!)!, (n, s) = limit ?? (0, 0)
            var c = clients[client] ?? Client(level: n * s, last: time)
            if limit != nil {
                c.level = min(n * s, c.level + (time - c.last) * n)
                c.last = time
                if c.level < s {
                    c.limited += 1
                    clients[client] = c
                    return Response(
                        429,
                        "too many requests: client \(client)",
                        ["Retry-After": String((s - c.level + n - 1) / n)]
                    )
                }
                c.level -= s
            }
            c.allowed += 1
            clients[client] = c
        }
        let split = splitFirst(target, "?"), path = split?.0 ?? target, query = split?.1,
            suffix = query.map { "?" + $0 } ?? "", normalized = normalize(path)
        if normalized != path {
            let dest = normalized + suffix
            return Response(308, "redirect to " + dest, ["Location": dest])
        }
        for rule in redirects
            where path == rule
            .from ||
            (rule.prefix && path.hasPrefix(rule.from + "/"))
        {
            let dest = rule.to + String(path.dropFirst(rule.from.count)) + suffix
            return Response(rule.code, "redirect to " + dest, ["Location": dest])
        }
        let parts = path == "/" ? [] : String(path.dropFirst()).components(separatedBy: "/")
        let matching = priority.filter { routes[$0].fits(parts) }
        if matching.isEmpty {
            return Response(404, "not found: " + path)
        }
        var allowed: Set<String> = ["OPTIONS"]
        for i in matching {
            allowed.formUnion(routes[i].methods)
        }
        if allowed.contains("GET") {
            allowed.insert("HEAD")
        }
        let allow = allowed.sorted().joined(separator: ", ")
        if effective == "OPTIONS" {
            return Response(204, "", ["Allow": allow])
        }
        let lookup = effective == "HEAD" ? "GET" : effective
        guard let i = matching.first(where: { routes[$0].methods.contains(lookup) }) else {
            return Response(
                405,
                "method not allowed: " + effective,
                ["Allow": allow]
            )
        }
        let route = routes[i]
        route.count += 1
        if route.role != "none" {
            guard let auth = h["authorization"] else {
                return Response(
                    401,
                    "unauthorized: missing token",
                    ["WWW-Authenticate": "Bearer realm=\"api\""]
                )
            }
            let (scheme, token) = splitFirst(auth, " ") ?? (auth, "")
            guard scheme.lowercased() == "bearer", let tokenRole = tokens[token] else {
                return Response(
                    401,
                    "unauthorized: invalid token",
                    ["WWW-Authenticate": "Bearer realm=\"api\", error=\"invalid_token\""]
                )
            }
            if tokenRole != route.role && tokenRole != "admin" {
                return Response(
                    403,
                    "forbidden: requires role " + route.role
                )
            }
        }
        let types = route.types!
        func vary(_ r: Response) -> Response {
            var r = r
            if types.count >= 2 {
                r.headers["Vary"] = "Accept"
            }
            return r
        }
        let selected: String?
        if let accept = h["accept"] {
            selected = negotiate(types, accept)
        } else {
            selected = types[0]
        }
        guard let selected else {
            return vary(Response(406, "not acceptable: " + types.joined(separator: ", ")))
        }
        let params = route.parameters(parts)
        var queries: [(String, String)] = []
        if let query {
            for p in query.components(separatedBy: "&") where !p.isEmpty {
                let (a, b) = splitFirst(p, "=") ?? (
                    p,
                    ""
                )
                queries.append((
                    decode(a.replacingOccurrences(of: "+", with: " ")),
                    decode(b.replacingOccurrences(of: "+", with: " "))
                ))
            }
        }
        var cookieMap: [String: String] = [:]
        if let cookie = h["cookie"] {
            for p in cookie.components(separatedBy: ";").map(trim) {
                if let (a, b) = splitFirst(
                    p,
                    "="
                ), !a.isEmpty, cookieMap[a] == nil {
                    cookieMap[a] = b
                }
            }
        }
        let cookies = cookieMap.keys.sorted().map { ($0, cookieMap[$0]!) }, body = makeBody(
            route.name,
            selected,
            params,
            queries,
            cookies
        ), tag = etag(body)
        if let value = h["if-none-match"],
           value.components(separatedBy: ",")
               .contains(where: { p in let p = trim(p), value = p.hasPrefix("W/") ? String(p.dropFirst(2)) : p
                   return value == "*" || value == tag
               })
        {
            return lookup == "GET" ? vary(Response(304, "", ["ETag": tag])) : vary(Response(
                412,
                "precondition failed: " + tag
            ))
        }
        var response = vary(Response(200, body, ["ETag": tag]))
        response.contentType = selected
        return response
    }
    func urlfor(_ w: [String]) throws -> String {
        guard let route = routes.first(where: { $0.name == w[1] })
        else {
            throw Problem(reason: "unknown route \(w[1])")
        }
        let names = Set(route.pieces.filter { $0.kind != "l" }.map(\.value))
        var args: [(String, String)] = [], params: [String: String] = [:]
        for arg in w.dropFirst(2) {
            guard let (name, value) = splitFirst(arg, "="),
                  !name.isEmpty
            else {
                throw Problem(reason: "bad argument \(arg)")
            }
            if names.contains(name) {
                if params[name] != nil {
                    throw Problem(reason: "duplicate parameter \(name)")
                }
                params[name] = value
            }
            args.append((name, value))
        }
        for p in route.pieces where p.kind != "l" {
            let value = params[p.value]
            if p.kind != "w" && value == nil {
                throw Problem(reason: "missing parameter \(p.value)")
            }
            let good: Bool
            switch p.kind { case "p":
                good = value != "" && value != "." && value != ".."
            case "i":
                good = intParameter(value!)
            case "s":
                good = slug(value!)
            default:
                good = value == nil || value == "" || value!.components(separatedBy: "/")
                    .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." } }
            if !good {
                throw Problem(reason: "bad value for \(p.value)")
            }
        }
        var pieces: [String] = []
        for p in route.pieces {
            if p.kind == "l" {
                pieces.append(p.value)
            } else {
                let value = params[p.value] ?? ""
                if p.kind == "w" {
                    if !value.isEmpty {
                        pieces += value.components(separatedBy: "/").map(encode)
                    }
                } else {
                    pieces.append(encode(value))
                }
            }
        }
        var url = "/" + pieces.joined(separator: "/")
        let queries = args.filter { !names.contains($0.0) }.map { encode($0.0) + "=" + encode($0.1) }
        if !queries.isEmpty {
            url += "?" + queries.joined(separator: "&")
        }
        return "URLFOR \(route.name) \(url)"
    }
}
func negotiate(_ types: [String], _ accept: String) -> String? {
    var elements: [(String, Int, Int)] = []
    for element in accept.components(separatedBy: ",") {
        let parts = element.components(separatedBy: ";").map(trim), range = parts[0].lowercased(), specificity: Int
        if range == "*/*" {
            specificity = 1
        } else if range.hasSuffix("/*") && mediaPart(String(range.dropLast(2))) {
            specificity = 2
        } else if media(range) {
            specificity = 3
        } else {
            continue
        }
        var q: String? = nil
        for p in parts
            .dropFirst()
        {
            if let (name, value) = splitFirst(p, "="), trim(name).lowercased() == "q" {
                q = trim(value)
                break
            }
        }
        let weight: Int
        if let q {
            guard matches(q, "(?:0(?:\\.[0-9]{0,3})?|1(?:\\.0{0,3})?)") else {
                continue
            }
            if q.hasPrefix("1") {
                weight = 1000
            } else {
                let f = splitFirst(q, ".")?.1 ?? ""
                weight = Int(f + String(repeating: "0", count: 3 - f.count))!
            }
        } else {
            weight = 1000
        }
        elements.append((range, specificity, weight))
    }
    var selected: String? = nil, best = 0
    for t in types {
        var specificity = 0, weight = 0
        for (range, s, w) in elements where s > specificity {
            if range == "*/*" || range == t ||
                (range.hasSuffix("/*") && String(range.dropLast(2)) == t.components(separatedBy: "/")[0])
            {
                specificity = s
                weight = w
            }
        }
        if weight > best {
            best = weight
            selected = t
        }
    }
    return selected
}
func json(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
        of: "\"",
        with: "\\\""
    ) + "\""
}
func html(_ s: String) -> String {
    s.map { c in switch c { case "&":
        return "&amp;"
    case "<":
        return "&lt;"
    case ">":
        return "&gt;"
    case "\"":
        return "&quot;"
    default:
        return String(c) } }.joined()
}
func makeBody(
    _ route: String,
    _ type: String,
    _ params: [(String, String)],
    _ query: [(String, String)],
    _ cookies: [(String, String)]
) -> String {
    if type == "application/json" {
        func object(_ pairs: [(String, String)]) -> String {
            pairs.map { json($0.0) + ":" + json($0.1) }
                .joined(separator: ",")
        }
        return "{\"route\":" + json(route) + ",\"params\":{" + object(params) + "},\"query\":[" + query
            .map { "[" + json($0.0) + "," + json($0.1) + "]" }
            .joined(separator: ",") + "],\"cookies\":{" + object(cookies) + "}}"
    }
    if type == "text/html" {
        var result = "<dl><dt>route</dt><dd>" + html(route) + "</dd>"
        for (kind, list) in [("param", params), ("query", query), ("cookie", cookies)] {
            for (a, b) in list {
                result += "<dt>\(kind) \(html(a))</dt><dd>\(html(b))</dd>"
            }
        }
        return result + "</dl>"
    }
    func list(_ pairs: [(String, String)]) -> String {
        pairs.isEmpty ? "-" : pairs
            .map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&")
    }
    return "route=\(route) params=\(list(params)) query=\(list(query)) cookies=\(list(cookies))"
}
func etag(_ body: String) -> String {
    var a = 1, b = 0
    for c in body.utf8 {
        a = (a + Int(c)) % 65521
        b = (b + a) % 65521
    }
    return String(format: "\"%04x%04x\"", b, a)
}
let phrases = [
    200: "OK",
    204: "No Content",
    301: "Moved Permanently",
    302: "Found",
    304: "Not Modified",
    307: "Temporary Redirect",
    308: "Permanent Redirect",
    400: "Bad Request",
    401: "Unauthorized",
    403: "Forbidden",
    404: "Not Found",
    405: "Method Not Allowed",
    406: "Not Acceptable",
    412: "Precondition Failed",
    429: "Too Many Requests",
    501: "Not Implemented"
]
func output(_ number: Int, _ response: Response) {
    var r = response
    print("REQUEST \(number)")
    print("HTTP/1.1 \(r.status) \(phrases[r.status]!)")
    if r.status != 204 && r.status != 304 {
        r.headers["Content-Type"] = r.contentType
        r.headers["Content-Length"] = String(r.body.utf8.count)
    }
    for name in [
        "Location",
        "Allow",
        "Retry-After",
        "WWW-Authenticate",
        "Access-Control-Allow-Origin",
        "Access-Control-Allow-Methods",
        "Vary",
        "ETag",
        "Content-Type",
        "Content-Length"
    ] {
        if let value = r.headers[name] {
            print(name + ": " + value)
        }
    }
    if r.status != 204 && r.status != 304 && !r.head {
        print(r.body)
    }
}
var lines: [String] = []
while let line = readLine() {
    lines.append(line)
}
var at = 0, requests = 0, urlOK = 0, urlError = 0
let router = Router()
while lines[at] != "REQUESTS" {
    do { try router.config(lines[at].components(separatedBy: " ")) }
    catch let p as Problem { router.configErrors += 1
        print("CONFIG ERROR \(at + 1): \(p.reason)")
    } catch { fatalError("unexpected error") }
    at += 1
}
at += 1
router.table()
while lines[at] != "END" {
    let line = lines[at]
    at += 1
    if line.hasPrefix("URLFOR ") {
        do { print(try router.urlfor(line.components(separatedBy: " ")))
            urlOK += 1
        } catch let p as Problem { urlError += 1
            print("URLFOR ERROR " + p.reason)
        } catch { fatalError("unexpected error") }
    } else {
        requests += 1
        var headers: [String] = []
        while !lines[at].isEmpty {
            headers.append(lines[at])
            at += 1
        }
        at += 1
        let r = router.request(line, headers)
        router.statuses[r.status, default: 0] += 1
        output(requests, r)
    }
}
print("SUMMARY requests=\(requests) urlfor_ok=\(urlOK) urlfor_error=\(urlError)")
for code in router.statuses.keys.sorted() {
    print("STATUS \(code) \(router.statuses[code]!)")
}
for r in router.routes {
    print("ROUTE \(r.name) \(r.count)")
}
for name in router.clients.keys.sorted() {
    let c = router.clients[name]!
    print("CLIENT \(name) allowed=\(c.allowed) limited=\(c.limited)")
}
