private class Problem(val reason: String) : RuntimeException(reason)
private fun validName(s: String) = s.matches(Regex("[a-z][a-z0-9_]{0,19}"))
private fun role(s: String) = s.matches(Regex("[a-z]{1,16}"))
private fun unreserved(c: Char) = c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c in "-._~"
private fun segment(s: String) = s.isNotEmpty() && s != "." && s != ".." && s.all(::unreserved)
private fun canonical(s: String) = s == "/" || (s.startsWith('/') && s.substring(1).split('/').all(::segment))
private fun mediaPart(s: String) = s.matches(Regex("[a-z0-9.+-]+"))
private fun media(s: String): Boolean { val p = s.split('/'); return p.size == 2 && p.all(::mediaPart) }
private fun intParameter(s: String) = s.matches(Regex("[0-9]{1,9}"))
private fun slug(s: String) = s.matches(Regex("[a-z0-9-]+"))
private fun splitFirst(s: String, c: Char): Pair<String, String>? {
    val at = s.indexOf(c)
    return if (at < 0) null else s.substring(0, at) to s.substring(at + 1)
}
private fun hex(c: Char): Int? = when (c) { in '0'..'9' -> c-'0'; in 'A'..'F' -> c-'A'+10; in 'a'..'f' -> c-'a'+10; else -> null }
private fun validEscapes(s: String): Boolean {
    var at = 0
    while (at < s.length) {
        if (s[at] == '%') {
            if (at + 2 >= s.length) return false
            val a = hex(s[at+1]) ?: return false
            val b = hex(s[at+2]) ?: return false
            if (a*16+b !in 32..126) return false
            at += 3
        } else at++
    }
    return true
}
private fun decode(s: String): String = buildString {
    var at = 0
    while (at < s.length) {
        if (s[at] == '%') { append((hex(s[at+1])!!*16+hex(s[at+2])!!).toChar()); at += 3 }
        else append(s[at++])
    }
}
private fun encode(s: String) = s.map { if (unreserved(it)) it.toString() else "%%%02X".format(it.code) }.joinToString("")
private fun normalize(path: String): String {
    val text = buildString {
        var at = 0
        while (at < path.length) {
            if (path[at] == '%') { val c = (hex(path[at+1])!!*16+hex(path[at+2])!!).toChar(); append(if (unreserved(c)) c.toString() else "%%%02X".format(c.code)); at += 3 }
            else append(path[at++])
        }
    }
    val parts = mutableListOf<String>()
    for (p in text.substring(1).split('/')) when (p) { "", "." -> Unit; ".." -> if (parts.isNotEmpty()) parts.removeAt(parts.lastIndex); else -> parts.add(p) }
    return "/" + parts.joinToString("/")
}
private data class Piece(val kind: Char, val value: String)
private fun parsePattern(s: String): List<Piece>? {
    if (s == "/") return emptyList()
    if (!s.startsWith('/')) return null
    val parts = s.substring(1).split('/')
    val result = mutableListOf<Piece>()
    val names = mutableSetOf<String>()
    for ((i, p) in parts.withIndex()) {
        if (segment(p)) { result.add(Piece('l', p)); continue }
        if (!p.startsWith('{') || !p.endsWith('}')) return null
        val inner = p.substring(1, p.lastIndex)
        val kind: Char
        val value: String
        if (inner.startsWith('*')) { if (i != parts.lastIndex) return null; kind = 'w'; value = inner.substring(1) }
        else {
            val typed = splitFirst(inner, ':')
            if (typed != null) { value = typed.first; kind = when (typed.second) { "int" -> 'i'; "slug" -> 's'; else -> return null } }
            else { kind = 'p'; value = inner }
        }
        if (!validName(value) || !names.add(value)) return null
        result.add(Piece(kind, value))
    }
    return result
}
private data class Route(val name: String, val methods: Set<String>, val pattern: String, val pieces: List<Piece>, val role: String,
    var types: List<String>? = null, var count: Int = 0) {
    fun fits(parts: List<String>): Boolean {
        val wildcard = pieces.lastOrNull()?.kind == 'w'
        val m = pieces.size - if (wildcard) 1 else 0
        if (if (wildcard) parts.size < m else parts.size != m) return false
        return (0 until m).all { i -> val p = pieces[i]; val x = parts[i]; when (p.kind) { 'l' -> p.value == x; 'i' -> intParameter(x); 's' -> slug(x); else -> true } }
    }
    fun parameters(parts: List<String>): List<Pair<String, String>> = pieces.mapIndexedNotNull { i, p ->
        val value = when (p.kind) { 'l' -> return@mapIndexedNotNull null; 'w' -> parts.drop(i).joinToString("/", transform = ::decode); 'i' -> parts[i].toInt().toString(); 's' -> parts[i]; else -> decode(parts[i]) }
        p.value to value
    }.sortedBy { it.first }
}
private data class Redirect(val from: String, val to: String, val prefix: Boolean, val code: Int)
private data class Client(var level: Int, var last: Int, var allowed: Int = 0, var limited: Int = 0)
private data class Response(val status: Int, val body: String = "", val headers: MutableMap<String, String> = mutableMapOf(), var head: Boolean = false, var contentType: String = "text/plain")
private class Router {
    val routes = mutableListOf<Route>()
    var priority = emptyList<Int>()
    val tokens = mutableMapOf<String, String>()
    val redirects = mutableListOf<Redirect>()
    val origins = mutableSetOf<String>()
    var limit: Pair<Int, Int>? = null
    val clients = sortedMapOf<String, Client>()
    val statuses = sortedMapOf<Int, Int>()
    var configErrors = 0
    fun config(w: List<String>) {
        val command = w[0]
        val args = w.size-1
        fun require(condition: Boolean, reason: String) { if (!condition) throw Problem(reason) }
        require(command in setOf("ROUTE", "TOKEN", "REDIRECT", "ORIGIN", "LIMIT", "TYPES"), "unknown command $command")
        val correct = when (command) { "ROUTE" -> args == 3 || args == 5; "TOKEN", "LIMIT" -> args == 2; "REDIRECT" -> args == 3; "ORIGIN" -> args == 1; else -> args >= 2 }
        require(correct, "wrong number of arguments")
        when (command) {
            "ROUTE" -> {
                require(validName(w[1]), "bad route name ${w[1]}")
                require(routes.none { it.name == w[1] }, "duplicate route ${w[1]}")
                val methods = w[2].split(',')
                require(methods.all { it in setOf("GET", "POST", "PUT", "PATCH", "DELETE") } && methods.toSet().size == methods.size, "bad methods ${w[2]}")
                val pieces = parsePattern(w[3]) ?: throw Problem("bad pattern ${w[3]}")
                if (args == 5) { require(w[4] == "ROLE", "unknown option ${w[4]}"); require(role(w[5]), "bad role ${w[5]}") }
                routes.add(Route(w[1], methods.toSet(), w[3], pieces, if (args == 5) w[5] else "none"))
            }
            "TOKEN" -> {
                require(w[1].matches(Regex("[A-Za-z0-9._-]{1,32}")), "bad token ${w[1]}")
                require(w[1] !in tokens, "duplicate token ${w[1]}"); require(role(w[2]), "bad role ${w[2]}"); tokens[w[1]] = w[2]
            }
            "REDIRECT" -> {
                fun rule(s: String) = canonical(s) || (s.endsWith("/*") && s.dropLast(2) != "/" && canonical(s.dropLast(2)))
                require(rule(w[1]), "bad path ${w[1]}"); require(rule(w[2]), "bad path ${w[2]}")
                val p = w[1].endsWith("/*")
                require(p == w[2].endsWith("/*"), "wildcard mismatch")
                require(w[3] in setOf("301", "302", "307", "308"), "bad redirect code ${w[3]}")
                val from = if (p) w[1].dropLast(2) else w[1]
                val to = if (p) w[2].dropLast(2) else w[2]
                require(redirects.none { it.prefix == p && it.from == from }, "duplicate redirect ${w[1]}")
                redirects.add(Redirect(from, to, p, w[3].toInt()))
            }
            "ORIGIN" -> {
                require(w[1].matches(Regex("https?://[a-z0-9.:-]+")), "bad origin ${w[1]}")
                require(w[1] !in origins, "duplicate origin ${w[1]}"); origins.add(w[1])
            }
            "LIMIT" -> {
                val n = w[1].toIntOrNull()
                val s = w[2].toIntOrNull()
                require(w[1].matches(Regex("[1-9][0-9]*")) && w[2].matches(Regex("[1-9][0-9]*")) && n != null && n in 1..100 && s != null && s in 1..3600, "bad limit")
                require(limit == null, "duplicate limit"); limit = n!! to s!!
            }
            else -> {
                val r = routes.firstOrNull { it.name == w[1] } ?: throw Problem("unknown route ${w[1]}")
                require(r.types == null, "duplicate types ${w[1]}")
                val seen = mutableSetOf<String>()
                for (t in w.drop(2)) { require(media(t), "bad media type $t"); require(seen.add(t), "duplicate media type $t") }
                r.types = w.drop(2)
            }
        }
    }
    fun table() {
        val rate = limit?.let { "${it.first}/${it.second}" } ?: "none"
        println("CONFIG routes=${routes.size} tokens=${tokens.size} redirects=${redirects.size} origins=${origins.size} limit=$rate errors=$configErrors")
        routes.forEach { if (it.types == null) it.types = listOf("application/json") }
        priority = routes.indices.sortedWith(compareByDescending<Int> { routes[it].pieces.count { p -> p.kind == 'l' } }
            .thenByDescending { routes[it].pieces.count { p -> p.kind == 'i' || p.kind == 's' } }
            .thenBy { routes[it].pieces.any { p -> p.kind == 'w' } }.thenBy { it })
        for ((rank, i) in priority.withIndex()) {
            val r = routes[i]
            val methods = r.methods.toMutableSet().also { if ("GET" in it) it.add("HEAD") }
            println("TABLE ${rank+1} ${r.name} ${methods.sorted().joinToString(",")} ${r.pattern} role=${if (r.role == "none") "-" else r.role} types=${r.types!!.joinToString(",")}")
        }
    }
    fun request(line: String, raw: List<String>): Response {
        val w = line.split(' ')
        if (w.size != 3 || !w[0].matches(Regex("[A-Z]{1,16}")) || !w[1].startsWith('/') || '#' in w[1] || w[2] != "HTTP/1.1") return Response(400, "bad request: request line")
        val head = w[0] == "HEAD"
        fun bad(body: String) = Response(400, body, head = head)
        if (!validEscapes(w[1])) return bad("bad request: percent escape")
        val headers = mutableMapOf<String, String>()
        for ((i, row) in raw.withIndex()) {
            val pair = splitFirst(row, ':') ?: return bad("bad request: header line ${i+1}")
            if (!pair.first.matches(Regex("[A-Za-z0-9-]+"))) return bad("bad request: header line ${i+1}")
            val name = pair.first.lowercase()
            if (name in headers) return bad("bad request: duplicate header $name")
            headers[name] = pair.second.trim(' ')
        }
        val response = validRequest(w[0], w[1], headers)
        response.head = head
        val origin = headers["origin"]
        if (origin != null && origin in origins) {
            response.headers["Access-Control-Allow-Origin"] = origin
            if (response.status == 204 && "access-control-request-method" in headers) response.headers["Access-Control-Allow-Methods"] = response.headers.getValue("Allow")
        }
        return response
    }
    fun validRequest(method: String, target: String, h: Map<String, String>): Response {
        if (method !in setOf("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")) return Response(501, "not implemented: $method")
        if (h["host"].isNullOrEmpty()) return Response(400, "bad request: missing host")
        var effective = method
        h["x-http-method-override"]?.let {
            if (method != "POST" || it !in setOf("PUT", "PATCH", "DELETE")) return Response(400, "bad request: method override")
            effective = it
        }
        val client = h["x-client"]
        if (!client.isNullOrEmpty()) {
            val time = h.getValue("x-time").toInt()
            val (n, s) = limit ?: (0 to 0)
            val c = clients.getOrPut(client) { Client(n*s, time) }
            if (limit != null) {
                c.level = minOf(n*s, c.level+(time-c.last)*n); c.last = time
                if (c.level < s) { c.limited++; return Response(429, "too many requests: client $client", mutableMapOf("Retry-After" to ((s-c.level+n-1)/n).toString())) }
                c.level -= s
            }
            c.allowed++
        }
        val split = splitFirst(target, '?')
        val path = split?.first ?: target
        val query = split?.second
        val suffix = query?.let { "?$it" } ?: ""
        val normalized = normalize(path)
        if (normalized != path) { val dest = normalized+suffix; return Response(308, "redirect to $dest", mutableMapOf("Location" to dest)) }
        for (r in redirects) if (path == r.from || (r.prefix && path.startsWith(r.from+"/"))) {
            val dest = r.to+path.substring(r.from.length)+suffix
            return Response(r.code, "redirect to $dest", mutableMapOf("Location" to dest))
        }
        val parts = if (path == "/") emptyList() else path.substring(1).split('/')
        val matching = priority.filter { routes[it].fits(parts) }
        if (matching.isEmpty()) return Response(404, "not found: $path")
        val allowed = mutableSetOf("OPTIONS")
        matching.forEach { allowed.addAll(routes[it].methods) }; if ("GET" in allowed) allowed.add("HEAD")
        val allow = allowed.sorted().joinToString(", ")
        if (effective == "OPTIONS") return Response(204, headers = mutableMapOf("Allow" to allow))
        val lookup = if (effective == "HEAD") "GET" else effective
        val i = matching.firstOrNull { lookup in routes[it].methods } ?: return Response(405, "method not allowed: $effective", mutableMapOf("Allow" to allow))
        val route = routes[i]; route.count++
        if (route.role != "none") {
            val auth = h["authorization"] ?: return Response(401, "unauthorized: missing token", mutableMapOf("WWW-Authenticate" to "Bearer realm=\"api\""))
            val (scheme, token) = splitFirst(auth, ' ') ?: (auth to "")
            val tokenRole = tokens[token]
            if (scheme.lowercase() != "bearer" || tokenRole == null) return Response(401, "unauthorized: invalid token", mutableMapOf("WWW-Authenticate" to "Bearer realm=\"api\", error=\"invalid_token\""))
            if (tokenRole != route.role && tokenRole != "admin") return Response(403, "forbidden: requires role ${route.role}")
        }
        val types = route.types!!
        fun vary(r: Response): Response { if (types.size >= 2) r.headers["Vary"] = "Accept"; return r }
        val selected = if ("accept" in h) negotiate(types, h.getValue("accept")) else types[0]
        if (selected == null) return vary(Response(406, "not acceptable: ${types.joinToString(", ")}"))
        val params = route.parameters(parts)
        val queries = query?.split('&')?.filter { it.isNotEmpty() }?.map { val (a, b) = splitFirst(it, '=') ?: (it to ""); decode(a.replace('+', ' ')) to decode(b.replace('+', ' ')) } ?: emptyList()
        val cookieMap = sortedMapOf<String, String>()
        h["cookie"]?.split(';')?.map { it.trim(' ') }?.forEach { p -> val pair = splitFirst(p, '='); if (pair != null && pair.first.isNotEmpty()) cookieMap.putIfAbsent(pair.first, pair.second) }
        val cookies = cookieMap.entries.map { it.key to it.value }
        val body = makeBody(route.name, selected, params, queries, cookies)
        val tag = etag(body)
        if (h["if-none-match"]?.split(',')?.any { val value = it.trim(' ').removePrefix("W/"); value == "*" || value == tag } == true) {
            return if (lookup == "GET") vary(Response(304, headers = mutableMapOf("ETag" to tag))) else vary(Response(412, "precondition failed: $tag"))
        }
        return vary(Response(200, body, mutableMapOf("ETag" to tag), contentType = selected))
    }
    fun urlfor(w: List<String>): String {
        val route = routes.firstOrNull { it.name == w[1] } ?: throw Problem("unknown route ${w[1]}")
        val names = route.pieces.filter { it.kind != 'l' }.map { it.value }.toSet()
        val args = mutableListOf<Pair<String, String>>()
        val params = mutableMapOf<String, String>()
        for (arg in w.drop(2)) {
            val (name, value) = splitFirst(arg, '=') ?: throw Problem("bad argument $arg")
            if (name.isEmpty()) throw Problem("bad argument $arg")
            if (name in names) { if (name in params) throw Problem("duplicate parameter $name"); params[name] = value }
            args.add(name to value)
        }
        for (p in route.pieces.filter { it.kind != 'l' }) {
            val value = params[p.value]
            if (p.kind != 'w' && value == null) throw Problem("missing parameter ${p.value}")
            val good = when (p.kind) { 'p' -> !value.isNullOrEmpty() && value != "." && value != ".."; 'i' -> intParameter(value!!); 's' -> slug(value!!); else -> value.isNullOrEmpty() || value.split('/').all { it.isNotEmpty() && it != "." && it != ".." } }
            if (!good) throw Problem("bad value for ${p.value}")
        }
        val pieces = mutableListOf<String>()
        for (p in route.pieces) if (p.kind == 'l') pieces.add(p.value) else {
            val value = params[p.value] ?: ""
            if (p.kind == 'w') { if (value.isNotEmpty()) pieces.addAll(value.split('/').map(::encode)) } else pieces.add(encode(value))
        }
        var url = "/"+pieces.joinToString("/")
        val queries = args.filter { it.first !in names }.map { encode(it.first)+"="+encode(it.second) }
        if (queries.isNotEmpty()) url += "?"+queries.joinToString("&")
        return "URLFOR ${route.name} $url"
    }
}
private fun negotiate(types: List<String>, accept: String): String? {
    val elements = mutableListOf<Triple<String, Int, Int>>()
    for (element in accept.split(',')) {
        val parts = element.split(';').map { it.trim(' ') }
        val range = parts[0].lowercase()
        val specificity = when { range == "*/*" -> 1; range.endsWith("/*") && mediaPart(range.dropLast(2)) -> 2; media(range) -> 3; else -> continue }
        val q = parts.drop(1).mapNotNull { splitFirst(it, '=') }.firstOrNull { it.first.trim(' ').lowercase() == "q" }?.second?.trim(' ')
        val weight = if (q == null) 1000 else {
            if (!q.matches(Regex("(?:0(?:\\.[0-9]{0,3})?|1(?:\\.0{0,3})?)"))) continue
            if (q.startsWith('1')) 1000 else (splitFirst(q, '.')?.second ?: "").padEnd(3, '0').toInt()
        }
        elements.add(Triple(range, specificity, weight))
    }
    var selected: String? = null
    var best = 0
    for (t in types) {
        var specificity = 0
        var weight = 0
        for ((range, s, w) in elements) if (s > specificity && (range == "*/*" || range == t || (range.endsWith("/*") && range.dropLast(2) == t.substringBefore('/')))) { specificity = s; weight = w }
        if (weight > best) { best = weight; selected = t }
    }
    return selected
}
private fun json(s: String) = "\""+s.replace("\\", "\\\\").replace("\"", "\\\"")+"\""
private fun html(s: String) = s.map { when (it) { '&' -> "&amp;"; '<' -> "&lt;"; '>' -> "&gt;"; '"' -> "&quot;"; else -> it.toString() } }.joinToString("")
private fun makeBody(route: String, type: String, params: List<Pair<String, String>>, query: List<Pair<String, String>>, cookies: List<Pair<String, String>>): String {
    if (type == "application/json") {
        fun obj(pairs: List<Pair<String, String>>) = pairs.joinToString(",") { json(it.first)+":"+json(it.second) }
        return "{\"route\":"+json(route)+",\"params\":{"+obj(params)+"},\"query\":["+query.joinToString(",") { "["+json(it.first)+","+json(it.second)+"]" }+"],\"cookies\":{"+obj(cookies)+"}}"
    }
    if (type == "text/html") return buildString {
        append("<dl><dt>route</dt><dd>").append(html(route)).append("</dd>")
        for ((kind, list) in listOf("param" to params, "query" to query, "cookie" to cookies)) for ((a, b) in list) append("<dt>$kind ${html(a)}</dt><dd>${html(b)}</dd>")
        append("</dl>")
    }
    fun list(pairs: List<Pair<String, String>>) = if (pairs.isEmpty()) "-" else pairs.joinToString("&") { encode(it.first)+"="+encode(it.second) }
    return "route=$route params=${list(params)} query=${list(query)} cookies=${list(cookies)}"
}
private fun etag(body: String): String { var a = 1; var b = 0; for (c in body) { a = (a+c.code)%65521; b = (b+a)%65521 }; return "\"%04x%04x\"".format(b, a) }
private val phrases = mapOf(200 to "OK", 204 to "No Content", 301 to "Moved Permanently", 302 to "Found", 304 to "Not Modified", 307 to "Temporary Redirect", 308 to "Permanent Redirect", 400 to "Bad Request", 401 to "Unauthorized", 403 to "Forbidden", 404 to "Not Found", 405 to "Method Not Allowed", 406 to "Not Acceptable", 412 to "Precondition Failed", 429 to "Too Many Requests", 501 to "Not Implemented")
private fun output(number: Int, r: Response) {
    println("REQUEST $number"); println("HTTP/1.1 ${r.status} ${phrases.getValue(r.status)}")
    if (r.status != 204 && r.status != 304) { r.headers["Content-Type"] = r.contentType; r.headers["Content-Length"] = r.body.length.toString() }
    for (name in listOf("Location", "Allow", "Retry-After", "WWW-Authenticate", "Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Vary", "ETag", "Content-Type", "Content-Length")) r.headers[name]?.let { println("$name: $it") }
    if (r.status != 204 && r.status != 304 && !r.head) println(r.body)
}
fun main() {
    val lines = generateSequence(::readLine).toList()
    val router = Router()
    var at = 0
    while (lines[at] != "REQUESTS") {
        try { router.config(lines[at].split(' ')) }
        catch (p: Problem) { router.configErrors++; println("CONFIG ERROR ${at+1}: ${p.reason}") }
        at++
    }
    at++; router.table()
    var requests = 0
    var urlOK = 0
    var urlError = 0
    while (lines[at] != "END") {
        val line = lines[at++]
        if (line.startsWith("URLFOR ")) {
            try { println(router.urlfor(line.split(' '))); urlOK++ }
            catch (p: Problem) { urlError++; println("URLFOR ERROR ${p.reason}") }
        } else {
            requests++
            val headers = mutableListOf<String>()
            while (lines[at].isNotEmpty()) headers.add(lines[at++])
            at++
            val r = router.request(line, headers)
            router.statuses[r.status] = (router.statuses[r.status] ?: 0)+1
            output(requests, r)
        }
    }
    println("SUMMARY requests=$requests urlfor_ok=$urlOK urlfor_error=$urlError")
    for ((status, count) in router.statuses) println("STATUS $status $count")
    for (r in router.routes) println("ROUTE ${r.name} ${r.count}")
    for ((name, c) in router.clients) println("CLIENT $name allowed=${c.allowed} limited=${c.limited}")
}
