private class Problem(val reason: String) : RuntimeException(reason)

private fun ip(word: String): Long {
    val fields = word.split('.')
    if (fields.size != 4) throw Problem("bad address $word")
    var address = 0L
    for (field in fields) {
        if (
            field.length !in 1..3 ||
                (field.length > 1 && field[0] == '0') ||
                field.any { it !in '0'..'9' } ||
                field.toInt() > 255
        )
            throw Problem("bad address $word")
        address = address * 256 + field.toInt()
    }
    return address
}

private fun address(a: Long) = "${a shr 24}.${(a shr 16) and 255}.${(a shr 8) and 255}.${a and 255}"

private fun mask(length: Int) =
    if (length == 0) 0L else (0xffffffffL shl (32 - length)) and 0xffffffffL

private data class Prefix(val network: Long, val length: Int) {
    fun contains(a: Long) = (a and mask(length)) == (network and mask(length))

    fun notation() = "${address(network)}/$length"

    fun aclNotation() = if (length == 0) "any" else notation()
}

private fun prefix(word: String, hostBits: Boolean = true): Prefix {
    val fields = word.split('/')
    if (fields.size != 2) throw Problem("bad prefix $word")
    val a =
        try {
            ip(fields[0])
        } catch (_: Problem) {
            throw Problem("bad prefix $word")
        }
    val s = fields[1]
    if (
        s.length !in 1..2 ||
            (s.length == 2 && s[0] == '0') ||
            s.any { it !in '0'..'9' } ||
            s.toInt() > 32
    )
        throw Problem("bad prefix $word")
    val length = s.toInt()
    if (hostBits && (a and (0xffffffffL xor mask(length))) != 0L)
        throw Problem("host bits set in $word")
    return Prefix(a, length)
}

private data class Ports(val low: Int, val high: Int, val any: Boolean) {
    fun contains(n: Int) = n in low..high

    fun notation() = if (any) "any" else if (low == high) "$low" else "$low-$high"
}

private fun ports(word: String): Ports {
    if (word == "ANY") return Ports(0, 65535, true)
    val values = word.split('-').map(String::toInt)
    val a = values.first()
    val b = values.last()
    if (a > 65535 || b > 65535 || a > b) throw Problem("bad port range $word")
    return Ports(a, b, false)
}

private data class Interface(
    val name: String,
    val address: Long,
    val length: Int,
    var up: Boolean = true,
    var outside: Boolean = false,
    var pool: Int? = null,
    var rpf: String = "off",
    var rx: Int = 0,
    var tx: Int = 0,
    var drop: Int = 0,
    val defaults: IntArray = IntArray(2),
)

private data class Route(
    val kind: String,
    val dest: Prefix,
    val iface: Int,
    val hop: Long?,
    val metric: Int,
    var hits: Int = 0,
)

private data class Rule(
    val iface: Int,
    val dir: Int,
    val seq: Int,
    val action: String,
    val proto: String,
    val src: Prefix,
    val sports: Ports,
    val dst: Prefix,
    val dports: Ports,
    val established: Boolean,
    var hits: Int = 0,
)

private data class Forward(
    val iface: Int,
    val proto: String,
    val port: Int,
    val inside: Long,
    val inport: Int,
)

private data class Pat(
    val iface: Int,
    val proto: String,
    val inside: Long,
    val inport: Int,
    val port: Int,
    var used: Int,
)

private data class PacketTuple(
    val proto: String,
    val src: Long,
    val sport: Int,
    val dst: Long,
    val dport: Int,
) {
    fun notation() = "${address(src)}:$sport > ${address(dst)}:$dport"
}

private data class Connection(
    val number: Int,
    val orig: PacketTuple,
    val reply: PacketTuple,
    val input: Int,
    val output: Int,
    var used: Int,
    var state: String = if (orig.proto == "TCP") "SYN_SENT" else "UNREPLIED",
    val packets: IntArray = IntArray(2),
    val fin: BooleanArray = BooleanArray(2),
)

private val reasons =
    listOf("down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted")

private fun protocolIndex(p: String) =
    when (p) {
        "TCP" -> 0
        "UDP" -> 1
        else -> 2
    }

private class Router {
    val ifaces = mutableListOf<Interface>()
    val routes = mutableListOf<Route>()
    val rules = mutableListOf<Rule>()
    val statics = mutableListOf<Pair<Long, Long>>()
    val forwards = mutableListOf<Forward>()
    val pats = mutableListOf<Pat>()
    val conns = mutableListOf<Connection>()
    val timeouts = intArrayOf(300, 60, 30)
    var clock = 0
    var packetNumber = 0
    var connectionNumber = 0
    var forwarded = 0
    var local = 0
    val drops = IntArray(9)
    var errors = 0

    fun iface(name: String): Int =
        ifaces.indexOfFirst { it.name == name }.takeIf { it >= 0 }
            ?: throw Problem("no interface $name")

    fun localAddress(a: Long): Int? = ifaces.indexOfFirst { it.address == a }.takeIf { it >= 0 }

    fun select(a: Long): Int? {
        var selected: Int? = null
        for ((i, r) in routes.withIndex()) {
            if (!ifaces[r.iface].up || !r.dest.contains(a)) continue
            val old = selected?.let { routes[it] }
            if (
                old == null ||
                    r.dest.length > old.dest.length ||
                    (r.dest.length == old.dest.length && r.metric < old.metric)
            )
                selected = i
        }
        return selected
    }

    fun routeText(r: Route) =
        "${r.kind} ${r.dest.notation()}${r.hop?.let { " via ${address(it)}" } ?: ""} dev ${ifaces[r.iface].name} metric ${r.metric}"

    fun acl(i: Int, d: Int, tuple: PacketTuple, existing: Boolean): String? {
        val list = rules.filter { it.iface == i && it.dir == d }.sortedBy { it.seq }
        if (list.isEmpty()) return null
        val name = ifaces[i].name
        val dir = if (d == 0) "in" else "out"
        for (r in list) {
            if (
                (r.proto != "ANY" && r.proto != tuple.proto) ||
                    !r.src.contains(tuple.src) ||
                    !r.dst.contains(tuple.dst) ||
                    (r.established && !existing)
            )
                continue
            if (
                r.proto in listOf("TCP", "UDP") &&
                    (!r.sports.contains(tuple.sport) || !r.dports.contains(tuple.dport))
            )
                continue
            r.hits++
            return when (r.action) {
                "PERMIT" -> null
                "DENY" -> "DROP acl $name $dir ${r.seq}"
                else ->
                    "REJECT acl $name $dir ${r.seq} ${if (tuple.proto == "TCP") "tcp-reset" else "icmp-prohibited"}"
            }
        }
        ifaces[i].defaults[d]++
        return "DROP acl $name $dir default"
    }

    fun packet(input: Int, flags: String, orig: PacketTuple, ttl: Int): Pair<String, Int> {
        if (!ifaces[input].up) return "DROP down" to 0
        fun martian(a: Long) = a shr 24 == 0L || a shr 24 == 127L || a >= 0xe0000000L
        if (martian(orig.src) || martian(orig.dst) || localAddress(orig.src) != null)
            return "DROP martian" to 1
        if (ifaces[input].rpf != "off") {
            val r = select(orig.src) ?: return "DROP rpf" to 2
            if (ifaces[input].rpf == "strict" && routes[r].iface != input) return "DROP rpf" to 2
        }
        val pureSyn = orig.proto == "TCP" && flags == "S"
        var found: Connection? = null
        var side = 0
        for (c in conns) {
            if (c.orig == orig) {
                found = c
                side = 0
                break
            }
            if (c.reply == orig) {
                found = c
                side = 1
                break
            }
        }
        if (found?.state == "CLOSED" && pureSyn) {
            conns.remove(found)
            found = null
        }
        if (orig.proto == "TCP" && found == null && !pureSyn) return "DROP invalid" to 3
        acl(input, 0, orig, found != null)?.let {
            return it to 4
        }
        var dst = orig.dst
        var dport = orig.dport
        var used: Pat? = null
        if (ifaces[input].outside) {
            val static = statics.firstOrNull { it.second == dst }
            if (static != null) dst = static.first
            else if (dst == ifaces[input].address) {
                val f = forwards.firstOrNull {
                    it.iface == input && it.proto == orig.proto && it.port == dport
                }
                if (f != null) {
                    dst = f.inside
                    dport = f.inport
                } else {
                    val p = pats.firstOrNull {
                        it.iface == input && it.proto == orig.proto && it.port == dport
                    }
                    if (p != null) {
                        dst = p.inside
                        dport = p.inport
                        used = p
                    }
                }
            }
        }
        localAddress(dst)?.let {
            return "LOCAL ${ifaces[it].name}" to -2
        }
        if (ttl == 1) return "DROP ttl" to 5
        val r = select(dst) ?: return "DROP noroute" to 6
        val output = routes[r].iface
        acl(output, 1, orig.copy(dst = dst, dport = dport), found != null)?.let {
            return it to 7
        }
        var src = orig.src
        var sport = orig.sport
        if (!ifaces[input].outside && ifaces[output].outside) {
            val static = statics.firstOrNull { it.first == src }
            val forward = forwards.firstOrNull {
                it.iface == output &&
                    it.proto == orig.proto &&
                    it.inside == src &&
                    it.inport == sport
            }
            if (static != null) src = static.second
            else if (forward != null) {
                src = ifaces[output].address
                sport = forward.port
            } else {
                val count = ifaces[output].pool
                if (count != null) {
                    var mapping = pats.firstOrNull {
                        it.iface == output &&
                            it.proto == orig.proto &&
                            it.inside == src &&
                            it.inport == sport
                    }
                    if (mapping == null) {
                        val port =
                            (20000 until 20000 + count).firstOrNull { p ->
                                pats.none { it.iface == output && it.port == p } &&
                                    forwards.none { it.iface == output && it.port == p }
                            } ?: return "DROP exhausted" to 8
                        mapping = Pat(output, orig.proto, src, sport, port, clock)
                        pats.add(mapping)
                    }
                    used = mapping
                    src = ifaces[output].address
                    sport = mapping.port
                }
            }
        }
        used?.used = clock
        val direction: String
        val c: Connection
        if (found != null) {
            c = found
            direction = if (side == 0) "orig" else "reply"
        } else {
            connectionNumber++
            c =
                Connection(
                    connectionNumber,
                    orig,
                    PacketTuple(orig.proto, dst, dport, src, sport),
                    input,
                    output,
                    clock,
                )
            conns.add(c)
            side = 0
            direction = "new"
        }
        c.packets[side]++
        c.used = clock
        if (orig.proto != "TCP") {
            if (side == 1) c.state = "REPLIED"
        } else if ('R' in flags) c.state = "CLOSED"
        else {
            if (c.state == "SYN_SENT" && side == 1 && 'S' in flags && 'A' in flags)
                c.state = "ESTABLISHED"
            if ('F' in flags && c.state in listOf("ESTABLISHED", "FIN_WAIT")) {
                c.fin[side] = true
                c.state = if (c.fin.all { it }) "CLOSED" else "FIN_WAIT"
            }
        }
        ifaces[output].tx++
        routes[r].hits++
        val hop = routes[r].hop?.let { "via ${address(it)}" } ?: "direct"
        var verdict = "FORWARD ${ifaces[output].name} $hop ttl=${ttl-1}"
        if (dst != orig.dst || dport != orig.dport) verdict += " dnat=${address(dst)}:$dport"
        if (src != orig.src || sport != orig.sport) verdict += " snat=${address(src)}:$sport"
        return "$verdict conn=${c.number} $direction" to -1
    }

    fun command(w: List<String>): List<String> {
        fun n(i: Int) = w[i].toInt()
        fun d(s: String) = if (s == "IN") 0 else 1
        fun require(condition: Boolean, reason: String) {
            if (!condition) throw Problem(reason)
        }
        val text =
            when (w[0]) {
                "IFACE" -> {
                    require(ifaces.none { it.name == w[1] }, "duplicate interface ${w[1]}")
                    val p = prefix(w[2], false)
                    require(p.length in 8..30, "bad prefix ${w[2]}")
                    val host = p.network and (0xffffffffL xor mask(p.length))
                    require(
                        host != 0L && host != (0xffffffffL xor mask(p.length)),
                        "bad host address ${w[2]}",
                    )
                    ifaces
                        .firstOrNull {
                            (it.address and mask(minOf(it.length, p.length))) ==
                                (p.network and mask(minOf(it.length, p.length)))
                        }
                        ?.let { throw Problem("subnet overlaps ${it.name}") }
                    val i = ifaces.size
                    val dest = Prefix(p.network and mask(p.length), p.length)
                    ifaces.add(Interface(w[1], p.network, p.length))
                    routes.add(Route("C", dest, i, null, 0))
                    "ok iface ${w[1]} ${w[2]} network ${dest.notation()}"
                }
                "UP",
                "DOWN" -> {
                    val i = iface(w[1])
                    val up = w[0] == "UP"
                    require(ifaces[i].up != up, "interface ${w[1]} already ${w[0].lowercase()}")
                    ifaces[i].up = up
                    "ok ${w[0].lowercase()} ${w[1]}"
                }
                "ROUTE" -> {
                    val dest = prefix(w[1])
                    var hop: Long? = null
                    var output = 0
                    if (w[2] == "VIA") hop = ip(w[3]) else output = iface(w[3])
                    require(n(4) in 1..255, "bad metric ${w[4]}")
                    val nextHop = hop
                    if (nextHop != null) {
                        require(localAddress(nextHop) == null, "nexthop ${w[3]} is local")
                        output = ifaces.indexOfFirst {
                            Prefix(it.address, it.length).contains(nextHop)
                        }
                        require(output >= 0, "nexthop ${w[3]} unreachable")
                    }
                    require(
                        routes.none {
                            it.kind == "S" && it.dest == dest && it.iface == output && it.hop == hop
                        },
                        "duplicate route ${w[1]}",
                    )
                    val r = Route("S", dest, output, hop, n(4))
                    routes.add(r)
                    "ok route ${routeText(r)}"
                }
                "NOROUTE" -> {
                    val dest = prefix(w[1])
                    val old = routes.size
                    require(
                        routes.any { it.kind == "S" && it.dest == dest },
                        "no static route ${w[1]}",
                    )
                    routes.removeAll { it.kind == "S" && it.dest == dest }
                    "ok noroute ${w[1]} removed=${old-routes.size}"
                }
                "LOOKUP" -> {
                    val a = ip(w[1])
                    "lookup ${w[1]} ${select(a)?.let { routeText(routes[it]) } ?: "none"}"
                }
                "ACL" -> {
                    val i = iface(w[1])
                    val dir = d(w[2])
                    require(n(3) in 1..9999, "bad sequence ${w[3]}")
                    val src = if (w[6] == "ANY") Prefix(0, 0) else prefix(w[6])
                    val sports = ports(w[7])
                    val dst = if (w[8] == "ANY") Prefix(0, 0) else prefix(w[8])
                    val dports = ports(w[9])
                    require(
                        w[5] !in listOf("ICMP", "ANY") || (sports.any && dports.any),
                        "ports not allowed for ${w[5]}",
                    )
                    require(
                        rules.none { it.iface == i && it.dir == dir && it.seq == n(3) },
                        "duplicate sequence ${w[3]}",
                    )
                    rules.add(
                        Rule(i, dir, n(3), w[4], w[5], src, sports, dst, dports, w.size == 11),
                    )
                    "ok acl ${w[1]} ${w[2].lowercase()} ${w[3]}"
                }
                "NOACL" -> {
                    val i = iface(w[1])
                    val dir = d(w[2])
                    val at = rules.indexOfFirst { it.iface == i && it.dir == dir && it.seq == n(3) }
                    require(at >= 0, "no rule ${w[3]} on ${w[1]} ${w[2].lowercase()}")
                    val rule = rules.removeAt(at)
                    "ok noacl ${w[1]} ${w[2].lowercase()} ${w[3]} hits=${rule.hits}"
                }
                "NAT" ->
                    when (w[1]) {
                        "STATIC" -> {
                            val inside = ip(w[2])
                            val outside = ip(w[3])
                            require(localAddress(inside) == null, "address ${w[2]} is local")
                            require(localAddress(outside) == null, "address ${w[3]} is local")
                            require(statics.none { it.first == inside }, "duplicate static ${w[2]}")
                            require(
                                statics.none { it.second == outside },
                                "duplicate static ${w[3]}",
                            )
                            statics.add(inside to outside)
                            "ok nat static ${w[2]} ${w[3]}"
                        }
                        "OUTSIDE" -> {
                            val i = iface(w[2])
                            require(!ifaces[i].outside, "interface ${w[2]} already outside")
                            ifaces[i].outside = true
                            "ok nat outside ${w[2]}"
                        }
                        "PAT" -> {
                            val i = iface(w[2])
                            require(n(3) in 1..1000, "bad pool size ${w[3]}")
                            require(ifaces[i].pool == null, "pat already on ${w[2]}")
                            ifaces[i].pool = n(3)
                            ifaces[i].outside = true
                            "ok nat pat ${w[2]} ${address(ifaces[i].address)} 20000-${20000+n(3)-1}"
                        }
                        else -> {
                            val i = iface(w[2])
                            require(n(4) in 1..65535, "bad port ${w[4]}")
                            val inside = ip(w[5])
                            require(n(6) in 1..65535, "bad port ${w[6]}")
                            require(ifaces[i].outside, "interface ${w[2]} not outside")
                            require(localAddress(inside) == null, "address ${w[5]} is local")
                            require(
                                forwards.none {
                                    it.iface == i && it.proto == w[3] && it.port == n(4)
                                },
                                "duplicate forward ${w[2]} ${w[3]} ${w[4]}",
                            )
                            forwards.add(Forward(i, w[3], n(4), inside, n(6)))
                            "ok nat forward ${w[2]} ${w[3]} ${w[4]} ${w[5]}:${w[6]}"
                        }
                    }
                "RPF" -> {
                    val i = iface(w[1])
                    ifaces[i].rpf = w[2].lowercase()
                    "ok rpf ${w[1]} ${w[2].lowercase()}"
                }
                "TIMEOUT" -> {
                    require(n(2) in 1..86400, "bad timeout ${w[2]}")
                    timeouts[protocolIndex(w[1])] = n(2)
                    "ok timeout ${w[1]} ${w[2]}"
                }
                "TICK" -> {
                    require(n(1) in 1..86400, "bad tick ${w[1]}")
                    clock += n(1)
                    val old = conns.size
                    val oldNat = pats.size
                    conns.removeAll { c ->
                        val timeout =
                            if (c.orig.proto == "TCP")
                                when (c.state) {
                                    "SYN_SENT",
                                    "FIN_WAIT" -> 60
                                    "CLOSED" -> 10
                                    else -> timeouts[0]
                                }
                            else timeouts[protocolIndex(c.orig.proto)]
                        clock - c.used >= timeout
                    }
                    pats.removeAll { clock - it.used >= timeouts[protocolIndex(it.proto)] }
                    "ok tick time=$clock expired conns=${old-conns.size} nat=${oldNat-pats.size}"
                }
                "PACKET" -> {
                    val i = iface(w[1])
                    require(w[2] == "TCP" || w[3] == "-", "flags not allowed for ${w[2]}")
                    if (w[2] == "TCP" && w[3] != "-")
                        require(
                            w[3].all { it in "SAFR" } && w[3].toSet().size == w[3].length,
                            "bad flags ${w[3]}",
                        )
                    val src = ip(w[4])
                    require(n(5) in 0..65535, "bad port ${w[5]}")
                    val dst = ip(w[6])
                    require(n(7) in 0..65535, "bad port ${w[7]}")
                    require(n(8) in 1..255, "bad ttl ${w[8]}")
                    packetNumber++
                    ifaces[i].rx++
                    val (verdict, reason) =
                        packet(i, w[3], PacketTuple(w[2], src, n(5), dst, n(7)), n(8))
                    when (reason) {
                        -1 -> forwarded++
                        -2 -> local++
                        else -> {
                            drops[reason]++
                            ifaces[i].drop++
                        }
                    }
                    "#$packetNumber ${w[2]} ${w[3]} ${w[4]}:${w[5]} > ${w[6]}:${w[7]} $verdict"
                }
                "SHOW" -> return show(w[1])
                else ->
                    if (w[1] == "CONNS") {
                        val result = "ok clear conns=${conns.size} nat=${pats.size}"
                        conns.clear()
                        pats.clear()
                        result
                    } else {
                        forwarded = 0
                        local = 0
                        drops.fill(0)
                        errors = 0
                        ifaces.forEach {
                            it.rx = 0
                            it.tx = 0
                            it.drop = 0
                            it.defaults.fill(0)
                        }
                        routes.forEach { it.hits = 0 }
                        rules.forEach { it.hits = 0 }
                        "ok clear counters"
                    }
            }
        return listOf(text)
    }

    fun show(what: String): List<String> {
        val names = ifaces.indices.sortedBy { ifaces[it].name }
        val lines = mutableListOf<String>()
        when (what) {
            "IFACES" -> {
                lines.add("show ifaces count=${ifaces.size}")
                for (i in names) {
                    val f = ifaces[i]
                    lines.add(
                        "${f.name} ${address(f.address)}/${f.length} ${if (f.up) "up" else "down"} ${if (f.outside) "outside" else "inside"} rpf=${f.rpf}" +
                            (f.pool?.let { " pat=${pats.count { p -> p.iface == i }}/$it" } ?: ""),
                    )
                }
            }
            "ROUTES" -> {
                lines.add("show routes count=${routes.size}")
                for (i in
                    routes.indices.sortedWith(
                        compareBy(
                            { routes[it].dest.network },
                            { routes[it].dest.length },
                            { routes[it].metric },
                            { it },
                        ),
                    )) {
                    val r = routes[i]
                    lines.add(
                        "${routeText(r)} hits=${r.hits}${if (ifaces[r.iface].up) "" else " inactive"}",
                    )
                }
            }
            "ACL" -> {
                lines.add("show acl count=${rules.size}")
                for (i in names) for (d in 0..1) {
                    val list = rules.filter { it.iface == i && it.dir == d }.sortedBy { it.seq }
                    if (list.isEmpty()) continue
                    val name = ifaces[i].name
                    val dir = if (d == 0) "in" else "out"
                    for (r in list) lines.add(
                        "acl $name $dir ${r.seq} ${r.action} ${r.proto} ${r.src.aclNotation()} ${r.sports.notation()} ${r.dst.aclNotation()} ${r.dports.notation()}${if (r.established) " established" else ""} hits=${r.hits}",
                    )
                    lines.add("acl $name $dir default DENY hits=${ifaces[i].defaults[d]}")
                }
            }
            "NAT" -> {
                lines.add(
                    "show nat static=${statics.size} forward=${forwards.size} pat=${pats.size}",
                )
                for ((a, b) in statics.sortedBy { it.first }) lines.add(
                    "static ${address(a)} ${address(b)}",
                )
                for (f in
                    forwards.sortedWith(
                        compareBy({ ifaces[it.iface].name }, { it.port }, { it.proto }),
                    )) lines.add(
                    "forward ${ifaces[f.iface].name} ${f.proto} ${f.port} ${address(f.inside)}:${f.inport}",
                )
                for (p in pats.sortedWith(compareBy({ ifaces[it.iface].name }, { it.port }))) lines
                    .add(
                        "pat ${ifaces[p.iface].name} ${p.port} ${p.proto} ${address(p.inside)}:${p.inport} idle=${clock-p.used}",
                    )
            }
            "CONNS" -> {
                lines.add("show conns count=${conns.size}")
                for (c in conns) lines.add(
                    "conn ${c.number} ${c.orig.proto} ${c.orig.notation()} reply ${c.reply.notation()} in=${ifaces[c.input].name} out=${ifaces[c.output].name} state=${c.state} pkts=${c.packets[0]}/${c.packets[1]} idle=${clock-c.used}",
                )
            }
            else -> {
                val dropped = drops.sum()
                lines.add(
                    "show counters packets=${forwarded+local+dropped} forwarded=$forwarded local=$local dropped=$dropped errors=$errors",
                )
                lines.add(
                    "drops " + reasons.indices.joinToString(" ") { "${reasons[it]}=${drops[it]}" },
                )
                for (i in names) {
                    val f = ifaces[i]
                    lines.add("iface ${f.name} rx=${f.rx} tx=${f.tx} drop=${f.drop}")
                }
            }
        }
        return lines
    }
}

fun main() {
    val router = Router()
    repeat(readLine()!!.toInt()) {
        try {
            router.command(readLine()!!.split(' ')).forEach(::println)
        } catch (p: Problem) {
            router.errors++
            println("error: ${p.reason}")
        }
    }
}
