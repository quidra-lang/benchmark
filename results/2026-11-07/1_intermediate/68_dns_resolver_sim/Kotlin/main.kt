private val types = listOf("A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA")
private val kinds = listOf("ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT")
private class Problem(val reason: String) : RuntimeException(reason)
private fun integer(s: String): Int? = if (s.matches(Regex("0|[1-9][0-9]{0,8}"))) s.toInt() else null
private fun ip(s: String): Long? {
    val parts = s.split('.')
    if (parts.size != 4) return null
    var a = 0L
    for (p in parts) {
        if (p.length > 3) return null
        val n = integer(p) ?: return null
        if (n > 255) return null
        a = a*256+n
    }
    return a
}
private fun address(a: Long) = "${a shr 24}.${(a shr 16) and 255}.${(a shr 8) and 255}.${a and 255}"
private fun ipv6(s: String): List<Int>? {
    fun groups(s: String): List<Int>? {
        if (s.isEmpty()) return emptyList()
        val out = mutableListOf<Int>()
        for (p in s.split(':')) {
            if (!p.matches(Regex("[0-9A-Fa-f]{1,4}"))) return null
            out.add(p.toInt(16))
        }
        return out
    }
    val pieces = s.split("::")
    if (pieces.size == 1) return groups(s)?.takeIf {
        it.size == 8
    }
    if (pieces.size != 2) return null
    val left = groups(pieces[0]) ?: return null
    val right = groups(pieces[1]) ?: return null
    if (left.size+right.size > 7) return null
    return left+List(8-left.size-right.size) {
        0
    }+right
}
private fun address6(a: List<Int>): String {
    var best = 0
    var size = 0
    var at = 0
    while (at < 8) {
        if (a[at] != 0) {
            at++
            continue
        }
        val start = at
        while (at < 8 && a[at] == 0) at++
        if (at-start >= 2 && at-start > size) {
            best = start
            size = at-start
        }
    }
    fun text(a: List<Int>) = a.joinToString(":") {
        it.toString(16)
    }
    return if (size == 0) text(a) else text(a.take(best))+"::"+text(a.drop(best+size))
}
private fun name(word: String, wild: Boolean, origin: String? = null): String {
    if (word == "@" && origin != null) return origin
    if (word == ".") return "."
    val parts = word.removeSuffix(".").split('.')
    for ((i, p) in parts.withIndex()) {
        if (wild && i == 0 && p == "*") continue
        if (p.length !in 1..63 || p.startsWith('-') || p.endsWith('-') || p.any {
            it !in 'A'..'Z' && it !in 'a'..'z' && it !in '0'..'9' && it != '-'
        }) throw Problem("bad name $word")
    }
    return parts.joinToString(".").lowercase()+"."+(if (!word.endsWith('.') && origin != null && origin != ".") origin else "")
}
private fun labels(s: String) = if (s == ".") emptyList() else s.dropLast(1).split('.')
private fun nameOrder(a: String, b: String): Int {
    val x = labels(a).asReversed()
    val y = labels(b).asReversed()
    for (i in 0 until minOf(x.size, y.size)) {
        val c = x[i].compareTo(y[i])
        if (c != 0) return c
    }
    return x.size.compareTo(y.size)
}
private fun below(a: String, b: String) = b == "." || a == b || a.endsWith(".$b")
private fun ancestors(s: String): List<String> {
    val p = labels(s)
    return p.indices.map {
        p.drop(it).joinToString(".")+"."
    }+"."
}
private fun checkedIp(s: String) = ip(s) ?: throw Problem("bad address $s")
private fun checkedType(s: String) {
    if (s !in types) throw Problem("bad type $s")
}
private fun ttl(s: String): Int {
    var seconds = integer(s)
    if (seconds == null) {
        var at = 0
        var previous = -1
        var total = 0
        var valid = true
        while (at < s.length) {
            val start = at
            while (at < s.length && s[at] in '0'..'9') at++
            val n = integer(s.substring(start, at))
            if (at == s.length || at-start > 3 || n == null) {
                valid = false
                break
            }
            val unit = "wdhms".indexOf(s[at].lowercaseChar())
            if (unit <= previous) {
                valid = false
                break
            }
            total += n*intArrayOf(604800, 86400, 3600, 60, 1)[unit]
            previous = unit
            at++
        }
        if (valid && previous >= 0) seconds = total
    }
    return seconds?.takeIf {
        it in 1..604800
    } ?: throw Problem("bad ttl $s")
}
private sealed interface Data
private data class A(val address: Long) : Data
private data class Aaaa(val address: List<Int>) : Data
private data class Target(val name: String) : Data
private data class Mx(val preference: Int, val host: String) : Data
private data class Txt(val text: String) : Data
private data class Soa(val mname: String, val rname: String, val numbers: List<Int>) : Data
private fun dataText(d: Data): String = when (d) {
    is A -> address(d.address)
    is Aaaa -> address6(d.address)
    is Target -> d.name
    is Mx -> "${d.preference} ${d.host}"
    is Txt -> d.text
    is Soa -> "${d.mname} ${d.rname} ${d.numbers.joinToString(" ")}"
}
private fun dataOrder(a: Data, b: Data): Int = when {
    a is A && b is A -> a.address.compareTo(b.address)
    a is Aaaa && b is Aaaa -> {
        var c = 0
        for (i in 0..7) {
            c = a.address[i].compareTo(b.address[i])
            if (c != 0) break
        }
        c
    }
    a is Target && b is Target -> nameOrder(a.name, b.name)
    a is Mx && b is Mx -> a.preference.compareTo(b.preference).takeIf {
        it != 0
    } ?: nameOrder(a.host, b.host)
    a is Txt && b is Txt -> a.text.compareTo(b.text)
    else -> 0
}
private data class Record(val owner: String, val ttl: Int, val type: String, val data: Data) {
    fun text() = "$owner $ttl $type ${dataText(data)}"
}
private val recordOrder = Comparator<Record> {
    a, b -> nameOrder(a.owner, b.owner).takeIf {
        it != 0
    } ?: types.indexOf(a.type).compareTo(types.indexOf(b.type)).takeIf {
        it != 0
    } ?: dataOrder(a.data, b.data)
}
private data class Zone(val origin: String, val server: Long, val line: Int, val records: MutableList<Record> = mutableListOf())
private data class Response(val kind: Int, val answer: List<Record> = emptyList(), val authority: List<Record> = emptyList(), val additional: List<Record> = emptyList(), val cut: String = "") {
    fun text() = when (kind) {
        1 -> "CNAME ${dataText(answer[0].data)}"
        2 -> "REFERRAL $cut"
        else -> kinds[kind]
    }
}
private data class Cache(val kind: Int, val records: List<Record>, val expiry: Int)
private data class Result(val status: String, val answer: List<Record>)
private class Resolver {
    val roots = mutableListOf<Long>()
    val zones = mutableListOf<Zone>()
    var current: Int? = null
    val down = mutableSetOf<Long>()
    val cache = mutableMapOf<Pair<String, String>, Cache>()
    val settings = intArrayOf(1, 86400, 3600)
    var clock = 0
    val queries = sortedMapOf<Long, IntArray>()
    var hits = 0
    val resolutions = IntArray(4)
    val out = mutableListOf<String>()
    fun zoneLine(w: List<String>, line: Int) {
        if (w[0] == "ROOT") {
            val added = mutableListOf<Long>()
            for (word in w.drop(1)) {
                val a = checkedIp(word)
                if (a in roots || a in added) throw Problem("duplicate root $word")
                added.add(a)
            }
            roots.addAll(added)
            return
        }
        if (w[0] == "ZONE") {
            current = null
            val origin = name(w[1], false)
            val server = checkedIp(w[2])
            if (zones.any {
                it.origin == origin && it.server == server
            }) throw Problem("duplicate zone $origin at ${w[2]}")
            current = zones.size
            zones.add(Zone(origin, server, line))
            return
        }
        val z = zones[current ?: throw Problem("no current zone")]
        val owner = name(w[0], true, z.origin)
        if (!below(owner, z.origin)) throw Problem("out of zone $owner")
        val seconds = ttl(w[1])
        val type = w[2]
        checkedType(type)
        val fields = w.drop(3)
        val count = when (type) {
            "MX" -> 2
            "SOA" -> 7
            "TXT" -> fields.size
            else -> 1
        }
        if (fields.size != count) throw Problem("wrong field count")
        val data: Data = when (type) {
            "A" -> A(checkedIp(fields[0]))
            "AAAA" -> Aaaa(ipv6(fields[0]) ?: throw Problem("bad address ${fields[0]}"))
            "NS", "CNAME", "PTR" -> Target(name(fields[0], false, z.origin))
            "MX" -> {
                val p = integer(fields[0])?.takeIf {
                    it <= 65535
                } ?: throw Problem("bad preference ${fields[0]}")
                Mx(p, name(fields[1], false, z.origin))
            }
            "TXT" -> {
                val s = fields.joinToString(" ")
                if (s.length < 2 || !s.startsWith('"') || !s.endsWith('"') || '"' in s.substring(1, s.lastIndex)) throw Problem("bad text $s")
                Txt(s)
            }
            else -> {
                val a = name(fields[0], false, z.origin)
                val b = name(fields[1], false, z.origin)
                val n = (2..5).map {
                    integer(fields[it]) ?: throw Problem("bad number ${fields[it]}")
                }+
                (integer(fields[6])?.takeIf {
                    it in 1..86400
                } ?: throw Problem("bad minimum ${fields[6]}"))
                Soa(a, b, n)
            }
        }
        if (type == "NS" && owner.startsWith("*.")) throw Problem("ns at wildcard")
        if (type == "SOA" && owner != z.origin) throw Problem("soa not at origin")
        if (type == "SOA" && z.records.any {
            it.type == "SOA"
        }) throw Problem("duplicate soa")
        if (z.records.any {
            it.owner == owner && it.type == type && it.data == data
        }) throw Problem("duplicate record")
        if (z.records.any {
            it.owner == owner && (type == "CNAME" || it.type == "CNAME")
        }) throw Problem("cname conflict $owner")
        z.records.add(Record(owner, seconds, type, data))
    }
    fun finishZones() {
        val kept = mutableListOf<Zone>()
        for (z in zones) {
            if (z.records.any {
                it.type == "SOA"
            }) {
                out.add("zone ${z.origin} at ${address(z.server)} records=${z.records.size}")
                kept.add(z)
            }
            else out.add("error line ${z.line}: zone ${z.origin} at ${address(z.server)} has no soa")
        }
        zones.clear()
        zones.addAll(kept)
        out.add("loaded roots=${roots.size} zones=${zones.size} records=${zones.sumOf { it.records.size }}")
    }
    fun records(z: Zone, n: String, t: String) = z.records.filter {
        it.owner == n && it.type == t
    }.sortedWith {
        a, b -> dataOrder(a.data, b.data)
    }
    fun authoritative(server: Long, n: String, t: String, cut: String): Response {
        if (server in down || zones.none {
            it.server == server
        }) return Response(6)
        val z = zones.filter {
            it.server == server && below(n, it.origin)
        }.maxByOrNull {
            labels(it.origin).size
        } ?: return Response(5)
        if (labels(z.origin).size < labels(cut).size) return Response(5)
        for (d in ancestors(n).asReversed().filter {
            it != z.origin && below(it, z.origin)
        }) {
            val ns = records(z, d, "NS")
            if (ns.isNotEmpty()) return Response(2, authority = ns, additional = ns.flatMap {
                records(z, (it.data as Target).name, "A")
            }, cut = d)
        }
        fun exists(x: String) = z.records.any {
            below(it.owner, x)
        }
        val soa = records(z, z.origin, "SOA")
        var owner = n
        if (z.records.none {
            it.owner == n
        }) {
            if (exists(n)) return Response(3, authority = soa)
            val e = ancestors(n).first {
                it != n && exists(it)
            }
            owner = if (e == ".") "*." else "*.$e"
            if (z.records.none {
                it.owner == owner
            }) return Response(4, authority = soa)
        }
        var answer = records(z, owner, t)
        var kind = 0
        if (answer.isEmpty() && t != "CNAME") {
            answer = records(z, owner, "CNAME")
            kind = 1
        }
        if (answer.isEmpty()) return Response(3, authority = soa)
        return Response(kind, answer.map {
            it.copy(owner = n)
        })
    }
    fun ask(a: Long, n: String, t: String, cut: String): Response {
        val r = authoritative(a, n, t, cut)
        queries.getOrPut(a) {
            IntArray(7)
        }[r.kind]++
        return r
    }
    fun trace(depth: Int, text: String) {
        out.add(" ".repeat(2*(depth+1))+text)
    }
    fun positive(records: List<Record>): Int {
        val seconds = records.minOf {
            it.ttl
        }.coerceAtLeast(settings[0]).coerceAtMost(settings[1])
        cache[records[0].owner to records[0].type] = Cache(0, records, clock+seconds)
        return seconds
    }
    fun cachedRecords(key: Pair<String, String>): List<Record>? = cache[key]?.takeIf {
        it.kind == 0
    }?.let {
        e -> e.records.map {
            it.copy(ttl = e.expiry-clock)
        }
    }
    fun queryServers(n: String, t: String, cut: String, servers: List<String>?, depth: Int, stack: MutableList<Pair<String, String>>): Response? {
        if (servers == null) {
            for (a in roots) {
                val r = ask(a, n, t, cut)
                trace(depth, "ASK ${address(a)} $n $t -> ${r.text()}")
                if (r.kind < 5) return r
            }
        } else for (host in servers.sortedWith {
            a, b -> nameOrder(a, b)
        }) {
            val records = cachedRecords(host to "A") ?: if ((host to "A") in stack) {
                trace(depth, "GLUELESS $host -> LOOP")
                emptyList()
            } else {
                trace(depth, "GLUELESS $host")
                val r = resolve(host, "A", depth+1, stack)
                if (r.status == "NOERROR") r.answer else emptyList()
            }
            val addresses = records.mapNotNull {
                (it.data as? A)?.address
            }.toSortedSet()
            for (a in addresses) {
                val r = ask(a, n, t, cut)
                trace(depth, "ASK ${address(a)} $n $t -> ${r.text()}")
                if (r.kind < 5) return r
            }
        }
        return null
    }
    fun lookup(n: String, t: String, depth: Int, stack: MutableList<Pair<String, String>>): Response {
        cache[n to t]?.let {
            e -> hits++
            trace(depth, "CACHE HIT $n $t -> ${if (e.kind == 0) "ANSWER" else kinds[e.kind]}")
            return Response(e.kind, if (e.kind == 0) cachedRecords(n to t)!! else emptyList())
        }
        if (cache.any {
            (key, e) -> e.kind == 4 && below(n, key.first)
        }) {
            hits++
            trace(depth, "CACHE HIT $n $t -> NXDOMAIN")
            return Response(4)
        }
        if (t != "CNAME") cachedRecords(n to "CNAME")?.let {
            hits++
            val r = Response(1, it)
            trace(depth, "CACHE HIT $n $t -> ${r.text()}")
            return r
        }
        val referral = cache.entries.filter {
            it.key.second == "NS" && it.value.kind == 0 && below(n, it.key.first)
        }.maxByOrNull {
            labels(it.key.first).size
        }
        var cut = referral?.key?.first ?: "."
        var servers = referral?.value?.records?.map {
            dataText(it.data)
        }
        if (referral != null) {
            hits++
            trace(depth, "CACHE HIT $n $t -> REFERRAL $cut")
        }
        while (true) {
            val r = queryServers(n, t, cut, servers, depth, stack) ?: throw Problem("SERVFAIL no server for $cut")
            when (r.kind) {
                2 -> {
                    positive(r.authority)
                    r.additional.groupBy {
                        it.owner
                    }.values.forEach {
                        positive(it)
                    }
                    cut = r.cut
                    servers = r.authority.map {
                        dataText(it.data)
                    }
                }
                0, 1 -> {
                    val seconds = positive(r.answer)
                    return r.copy(answer = r.answer.map {
                        it.copy(ttl = seconds)
                    })
                }
                3, 4 -> {
                    val soa = r.authority[0]
                    val seconds = minOf(soa.ttl, (soa.data as Soa).numbers[4], settings[2])
                    cache[n to t] = Cache(r.kind, emptyList(), clock+seconds)
                    return r
                }
                else -> error("unexpected response")
            }
        }
    }
    fun resolve(n: String, t: String, depth: Int, stack: MutableList<Pair<String, String>>): Result {
        stack.add(n to t)
        val chain = mutableListOf<Record>()
        val seen = mutableSetOf(n)
        var current = n
        var result: Result
        while (true) {
            val r = try {
                lookup(current, t, depth, stack)
            } catch (p: Problem) {
                result = Result(p.reason, emptyList())
                break
            }
            if (r.kind == 1) {
                val target = dataText(r.answer[0].data)
                chain.addAll(r.answer)
                if (target in seen) {
                    result = Result("SERVFAIL cname loop", emptyList())
                    break
                }
                if (chain.size == 9) {
                    result = Result("SERVFAIL cname chain too long", emptyList())
                    break
                }
                seen.add(target)
                current = target
            } else {
                if (r.kind == 0) chain.addAll(r.answer)
                result = Result(if (r.kind == 0) "NOERROR" else kinds[r.kind], chain.toList())
                break
            }
        }
        stack.removeAt(stack.lastIndex)
        resolutions[when (result.status) {
            "NOERROR" -> 0
            "NODATA" -> 1
            "NXDOMAIN" -> 2
            else -> 3
        }]++
        return result
    }
    fun outputResolution(n: String, t: String): Result {
        val r = resolve(n, t, 0, mutableListOf())
        r.answer.forEach {
            out.add("answer ${it.text()}")
        }
        out.add("status ${r.status}")
        return r
    }
    fun hostAddresses(n: String): List<String> = buildList {
        for (t in listOf("A", "AAAA")) {
            val r = resolve(n, t, 0, mutableListOf())
            if (r.status == "NOERROR") addAll(r.answer.filter {
                it.type == t
            }.map {
                dataText(it.data)
            })
        }
    }
    fun command(w: List<String>) {
        when (w[0]) {
            "RESOLVE" -> {
                val n = name(w[1], true)
                checkedType(w[2])
                out.add("resolve $n ${w[2]}")
                outputResolution(n, w[2])
            }
            "REVERSE" -> {
                val a: String
                val n: String
                if (':' in w[1]) {
                    val groups = ipv6(w[1]) ?: throw Problem("bad address ${w[1]}")
                    a = address6(groups)
                    n = groups.joinToString("") {
                        "%04x".format(it)
                    }.reversed().map(Char::toString).joinToString(".")+".ip6.arpa."
                }
                else {
                    val value = checkedIp(w[1])
                    a = address(value)
                    n = a.split('.').reversed().joinToString(".")+".in-addr.arpa."
                }
                out.add("reverse $a $n")
                outputResolution(n, "PTR")
            }
            "MX" -> {
                val n = name(w[1], true)
                out.add("mx $n")
                val r = outputResolution(n, "MX")
                if (r.status == "NOERROR") for (record in r.answer) {
                    val data = record.data as? Mx ?: continue
                    if (data.host == ".") out.add("exchange ${data.preference} . -> null")
                    else {
                        val addresses = hostAddresses(data.host)
                        out.add("exchange ${data.preference} ${data.host} -> ${addresses.takeIf { it.isNotEmpty() }?.joinToString(" ") ?: "no address"}")
                    }
                } else if (r.status == "NODATA") {
                    val host = r.answer.lastOrNull {
                        it.type == "CNAME"
                    }?.let {
                        dataText(it.data)
                    } ?: n
                    val addresses = hostAddresses(host)
                    out.add("implicit $host -> ${addresses.takeIf { it.isNotEmpty() }?.joinToString(" ") ?: "no address"}")
                }
            }
            "QUERY" -> {
                val a = checkedIp(w[1])
                val n = name(w[2], true)
                checkedType(w[3])
                val r = ask(a, n, w[3], ".")
                out.add("query ${address(a)} $n ${w[3]} -> ${r.text()}")
                val sections = when (r.kind) {
                    0, 1 -> listOf("answer" to r.answer)
                    2 -> listOf("authority" to r.authority, "additional" to r.additional)
                    3, 4 -> listOf("authority" to r.authority)
                    else -> emptyList()
                }
                for ((section, records) in sections) records.forEach {
                    out.add("$section ${it.text()}")
                }
            }
            "DUMP" -> {
                val a = checkedIp(w[1])
                val n = name(w[2], false)
                val z = zones.firstOrNull {
                    it.server == a && it.origin == n
                }
                if (a in down || zones.none {
                    it.server == a
                }) out.add("dump ${address(a)} $n -> TIMEOUT")
                else if (z == null) out.add("dump ${address(a)} $n -> REFUSED")
                else {
                    out.add("dump ${address(a)} $n records=${z.records.size}")
                    z.records.sortedWith(recordOrder).forEach {
                        out.add("  ${it.text()}")
                    }
                }
            }
            "UP", "DOWN" -> {
                val a = checkedIp(w[1])
                if (w[0] == "DOWN") {
                    if (a in down) throw Problem("server ${w[1]} already down")
                    down.add(a)
                }
                else if (!down.remove(a)) throw Problem("server ${w[1]} not down")
                out.add("${w[0].lowercase()} ${address(a)}")
            }
            "SET" -> {
                val i = listOf("MINTTL", "MAXTTL", "NEGTTL").indexOf(w[1])
                if (i < 0) throw Problem("bad setting ${w[1]}")
                val n = integer(w[2])?.takeIf {
                    it in 1..604800
                } ?: throw Problem("bad value ${w[2]}")
                val changed = settings.copyOf()
                changed[i] = n
                if (changed[0] > changed[1]) throw Problem("minttl above maxttl")
                settings[i] = n
                out.add("set ${w[1]}=$n")
            }
            "TIME" -> {
                val n = integer(w[1])?.takeIf {
                    it in 1..1000000
                } ?: throw Problem("bad time ${w[1]}")
                clock += n
                val old = cache.size
                cache.entries.removeIf {
                    it.value.expiry <= clock
                }
                out.add("time now=$clock expired=${old-cache.size}")
            }
            "CACHE", "FLUSH" -> {
                val parent = if (w.size == 2) name(w[1], false) else null
                val keys = cache.keys.filter {
                    parent == null || below(it.first, parent)
                }.sortedWith {
                    a, b -> nameOrder(a.first, b.first).takeIf {
                        it != 0
                    } ?: types.indexOf(a.second).compareTo(types.indexOf(b.second))
                }
                if (w[0] == "FLUSH") {
                    out.add("flush removed=${keys.size}")
                    keys.forEach {
                        cache.remove(it)
                    }
                }
                else {
                    out.add("cache entries=${keys.size}")
                    for (key in keys) {
                        val e = cache.getValue(key)
                        if (e.kind == 0) cachedRecords(key)!!.forEach {
                            out.add("  ${it.text()}")
                        } else out.add("  ${key.first} ${e.expiry-clock} ${key.second} ${kinds[e.kind]}")
                    }
                }
            }
            else -> {
                out.add("stats queries=${queries.values.sumOf { it.sum() }} hits=$hits")
                for ((a, c) in queries) out.add("  ${address(a)} sent=${c.sum()} answer=${c[0]} cname=${c[1]} referral=${c[2]} nodata=${c[3]} nxdomain=${c[4]} lame=${c[5]} timeout=${c[6]}")
                val c = resolutions
                out.add("resolutions noerror=${c[0]} nodata=${c[1]} nxdomain=${c[2]} servfail=${c[3]}")
            }
        }
    }
}
fun main() {
    val resolver = Resolver()
    var zones = true
    generateSequence(::readLine).forEachIndexed {
        i, line ->
        if (line == "END") return@forEachIndexed
        if (line == "END ZONES") {
            resolver.finishZones()
            zones = false
        }
        else try {
            if (zones) resolver.zoneLine(line.split(' '), i+1) else resolver.command(line.split(' '))
        }
        catch (p: Problem) {
            resolver.out.add("error line ${i+1}: ${p.reason}")
        }
    }
    resolver.out.forEach(::println)
}
