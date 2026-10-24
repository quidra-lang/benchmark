import java.util.ArrayDeque

fun yes(value: Boolean) = if (value) "yes" else "no"
fun mark(m: LongArray) = m.joinToString(",", "(", ")") { if (it < 0) "w" else it.toString() }
fun listed(a: List<String>) = if (a.isEmpty()) "none" else a.joinToString(" ")
fun number(s: String, lo: Long, hi: Long): Long? = if (s.matches(Regex("0|[1-9][0-9]{0,9}"))) s.toLong().takeIf { it in lo..hi } else null
fun bad(reason: String): Nothing = throw IllegalArgumentException(reason)
fun visit(adj: List<List<Int>>, start: Int): BooleanArray {
    val seen = BooleanArray(adj.size); val queue = ArrayDeque<Int>(); queue.add(start); seen[start] = true
    while (queue.isNotEmpty()) for (v in adj[queue.removeFirst()]) if (!seen[v]) { seen[v] = true; queue.add(v) }
    return seen
}
fun gcd(a: Long, b: Long): Long = if (b == 0L) kotlin.math.abs(a) else gcd(b, a % b)
fun lex(a: LongArray, b: LongArray): Int { for (i in a.indices) if (a[i] != b[i]) return a[i].compareTo(b[i]); return 0 }
fun flows(a: List<LongArray>): List<LongArray> {
    val n = a.size; val m = a[0].size
    var rows = a.mapIndexed { i, r -> r + LongArray(n) { j -> if (i == j) 1 else 0 } }
    for (j in 0 until m) {
        val unique = linkedMapOf<List<Long>, LongArray>()
        for (r in rows) if (r[j] == 0L) unique[r.toList()] = r
        for (r in rows) if (r[j] > 0) for (s in rows) if (s[j] < 0) {
            val v = LongArray(m+n) { k -> -s[j]*r[k]+r[j]*s[k] }; val d = v.fold(0L, ::gcd)
            for (k in v.indices) v[k] /= d
            unique[v.toList()] = v
        }
        val candidates = unique.values.toList()
        val supports = candidates.map { r -> (0 until n).fold(0) { mask, i -> if (r[m+i] > 0) mask or (1 shl i) else mask } }
        rows = candidates.filterIndexed { i, _ -> supports.none { it != supports[i] && it and supports[i] == it } }
    }
    return rows.map { it.copyOfRange(m,m+n) }.sortedWith { a,b -> lex(b,a) }
}
data class Edge(val transition: Int, val target: Int)
class Graph {
    val states = mutableListOf<LongArray>(); val parent = mutableListOf<Int>(); val via = mutableListOf<Int>(); val edges = mutableListOf<MutableList<Edge>>()
    var found = -1; var aborted = false
    fun add(m: LongArray, p: Int, t: Int) { states.add(m); parent.add(p); via.add(t); edges.add(mutableListOf()) }
}
class Net(val name: String) {
    val places = mutableListOf<String>(); val transitions = mutableListOf<String>(); val initial = mutableListOf<Long>(); val capacity = mutableListOf<Long>(); val priority = mutableListOf<Long>()
    val pre = Array(16) { LongArray(16) }; val post = Array(16) { LongArray(16) }; val inhibitor = Array(16) { LongArray(16) }
    var arcs = 0; var inhibitors = 0; var current = LongArray(0); val history = mutableListOf<LongArray>()
    fun define(w: List<String>) {
        val cmd = w[0]; val n = w.size-1
        if (cmd !in listOf("place","transition","arc","inhibit")) bad("unknown definition $cmd")
        if (!(when (cmd) { "place" -> n in 2..3; "transition" -> n in 1..2; else -> n == 3 })) bad("wrong number of arguments")
        val a = w[1]
        when (cmd) {
            "place", "transition" -> {
                if (a in places || a in transitions) bad("duplicate name $a")
                if (cmd == "place") { if (n == 3 && w[2].toLong() > w[3].toLong()) bad("tokens exceed capacity of $a"); places.add(a); initial.add(w[2].toLong()); capacity.add(if (n == 3) w[3].toLong() else 0) }
                else { transitions.add(a); priority.add(if (n == 2) w[2].toLong() else 0) }
            }
            "arc" -> {
                val b = w[2]; for (x in listOf(a,b)) if (x !in places && x !in transitions) bad("unknown node $x")
                val pa = places.indexOf(a); val pb = places.indexOf(b)
                if ((pa >= 0) == (pb >= 0)) bad("arc must connect a place and a transition")
                val p = if (pa >= 0) pa else pb; val t = transitions.indexOf(if (pa >= 0) b else a); val matrix = if (pa >= 0) pre else post
                if (matrix[p][t] > 0) bad("duplicate arc $a $b"); matrix[p][t] = w[3].toLong(); ++arcs
            }
            else -> { val p = places.indexOf(a); val t = transitions.indexOf(w[2]); if (p < 0) bad("unknown place $a"); if (t < 0) bad("unknown transition ${w[2]}"); if (inhibitor[p][t] > 0) bad("duplicate inhibitor $a ${w[2]}"); inhibitor[p][t] = w[3].toLong(); ++inhibitors }
        }
    }
    fun reason(m: LongArray, t: Int): String? {
        for (p in places.indices) if (m[p] >= 0 && m[p] < pre[p][t]) return "insufficient tokens in ${places[p]}"
        for (p in places.indices) if (inhibitor[p][t] > 0 && (m[p] < 0 || m[p] >= inhibitor[p][t])) return "inhibited by ${places[p]}"
        for (p in places.indices) if (capacity[p] > 0 && (m[p] < 0 || m[p]-pre[p][t]+post[p][t] > capacity[p])) return "capacity of ${places[p]} exceeded"
        return null
    }
    fun enabled(m: LongArray) = transitions.indices.filter { reason(m,it) == null }
    fun fire(m: LongArray, t: Int) = LongArray(m.size) { p -> if (m[p] < 0) -1 else m[p]-pre[p][t]+post[p][t] }
    fun commit(t: Int) { history.add(current); current = fire(current,t) }
    fun names(ts: List<Int>) = ts.map { transitions[it] }
    fun graph(start: LongArray, limit: Int, target: List<Pair<Long,Long>>? = null): Graph {
        val g = Graph(); g.add(start.copyOf(),-1,-1); val index = mutableMapOf(start.toList() to 0)
        fun matches(m: LongArray) = target != null && m.indices.all { p -> m[p] >= target[p].first && (target[p].second < 0 || m[p] == target[p].second) }
        if (matches(start)) { g.found = 0; return g }
        var q = 0
        while (q < g.states.size) {
            for (t in enabled(g.states[q])) {
                val m = fire(g.states[q],t); var k = index[m.toList()]
                if (k == null) { if (g.states.size == limit) { g.aborted = true; return g }; k = g.states.size; index[m.toList()] = k; g.add(m,q,t); if (matches(m)) { g.found = k; return g } }
                g.edges[q].add(Edge(t,k))
            }
            ++q
        }
        return g
    }
    fun path(g: Graph, target: Int): List<Int> { var k = target; val a = mutableListOf<Int>(); while (g.parent[k] >= 0) { a.add(g.via[k]); k = g.parent[k] }; return a.asReversed() }
    fun reach(limit: Int, display: Boolean) {
        val g = graph(current,limit); if (g.aborted) { println("reachability graph limit $limit exceeded"); return }; val n = g.states.size
        if (display) { for (i in 0 until n) { val a = g.edges[i].map { "${transitions[it.transition]}->M${it.target}" }; println("M$i ${mark(g.states[i])}: " + if (a.isEmpty()) "dead" else a.joinToString(" ")) }; return }
        val adj = g.edges.map { e -> e.map { it.target } }; val closure = List(n) { visit(adj,it) }; val comp = IntArray(n) { -1 }; var components = 0
        for (i in 0 until n) if (comp[i] < 0) { for (j in i until n) if (closure[i][j] && closure[j][i]) comp[j] = components; ++components }
        val terminal = BooleanArray(components) { true }; val home = BooleanArray(n) { true }; val maximum = LongArray(places.size); val dead = mutableListOf<Int>(); var edgeCount = 0; var persistent = true
        for (i in 0 until n) { if (g.edges[i].isEmpty()) dead.add(i); edgeCount += g.edges[i].size; for (p in places.indices) maximum[p] = maxOf(maximum[p],g.states[i][p]); for (j in 0 until n) home[j] = home[j] && closure[i][j]; for (e in g.edges[i]) { if (comp[i] != comp[e.target]) terminal[comp[i]] = false; for (u in g.edges[i]) if (u.transition != e.transition && reason(g.states[e.target],u.transition) != null) persistent = false } }
        println("reachable markings: $n\nedges: $edgeCount\ncomponents: $components (terminal ${terminal.count { it }})\ndead markings: ${dead.size}")
        for (i in dead) { val a = names(path(g,i)); println("  M$i ${mark(g.states[i])} path " + if (a.isEmpty()) "empty" else a.joinToString(" ")) }
        val bound = maximum.maxOrNull()!!; println("max tokens: ${mark(maximum)}\nbound: $bound\nsafe: ${yes(bound<=1)}\nhome markings: ${home.count { it }}\nreversible: ${yes(home[0])}\npersistent: ${yes(persistent)}")
        val levels = transitions.indices.map { t ->
            val present = BooleanArray(components); var used = false; var cycle = false
            for (i in 0 until n) for (e in g.edges[i]) if (e.transition == t) { used = true; present[comp[i]] = true; if (comp[i] == comp[e.target]) cycle = true }
            val live = terminal.indices.all { !terminal[it] || present[it] }; transitions[t]+"="+if (live) "L4" else if (cycle) "L3" else if (used) "L1" else "L0"
        }
        println("liveness: " + levels.joinToString(" "))
    }
    fun rank(v: Long) = if (v < 0) Long.MAX_VALUE else v
    fun cover(limit: Int) {
        val g = Graph(); g.add(current.copyOf(),-1,-1); val old = mutableListOf(false); val dead = mutableListOf(false); val seen = mutableSetOf(current.toList()); var q = 0
        while (q < g.states.size) {
            if (!old[q]) {
                val es = enabled(g.states[q]); dead[q] = es.isEmpty(); val ancestors = mutableListOf<Int>(); var a = q
                while (a >= 0) { ancestors.add(a); a = g.parent[a] }; ancestors.reverse()
                for (t in es) {
                    val m = fire(g.states[q],t)
                    for (ancestor in ancestors) if (m.indices.all { rank(m[it]) >= rank(g.states[ancestor][it]) } && m.indices.any { rank(m[it]) > rank(g.states[ancestor][it]) }) for (p in m.indices) if (capacity[p] == 0L && rank(m[p]) > rank(g.states[ancestor][p])) m[p] = -1
                    if (g.states.size == limit) { println("coverability tree limit $limit exceeded"); return }
                    old.add(!seen.add(m.toList())); dead.add(false); g.add(m,q,t)
                }
            }
            ++q
        }
        println("coverability tree nodes: ${g.states.size}"); val maximum = LongArray(places.size)
        for (i in g.states.indices) { println("  $i ${mark(g.states[i])} " + (if (i == 0) "root" else "<- ${g.parent[i]} ${transitions[g.via[i]]}") + (if (old[i]) " old" else "") + (if (dead[i]) " dead" else "")); for (p in places.indices) if (rank(g.states[i][p]) > rank(maximum[p])) maximum[p] = g.states[i][p] }
        println("bounds: ${mark(maximum)}\nunbounded: " + listed(places.indices.filter { maximum[it] < 0 }.map { places[it] }))
    }
    fun bits(mask: Int) = places.indices.filter { mask and (1 shl it) != 0 }
    fun sets(trap: Boolean): List<Int> {
        val found = (1 until (1 shl places.size)).filter { mask -> transitions.indices.all { t -> val input = bits(mask).any { post[it][t] > 0 }; val output = bits(mask).any { pre[it][t] > 0 }; if (trap) !output || input else !input || output } }
        return found.filter { m -> found.none { it != m && it and m == it } }.sortedWith { a,b -> val x = bits(a); val y = bits(b); if (x.size != y.size) x.size.compareTo(y.size) else lex(x.map { it.toLong() }.toLongArray(),y.map { it.toLong() }.toLongArray()) }
    }
    fun setText(mask: Int) = bits(mask).joinToString(",","{","}") { places[it] }
    fun realize(counts: LongArray): List<Int>? {
        val used = LongArray(counts.size); val stack = mutableListOf(current); val choices = mutableListOf(0); val result = mutableListOf<Int>(); val seen = mutableSetOf<List<Long>>(); val total = counts.sum()
        while (stack.isNotEmpty()) {
            val d = result.size; if (d.toLong() == total) return result; var chosen = -1
            for (t in choices[d] until counts.size) { choices[d] = t+1; if (used[t] >= counts[t] || reason(stack[d],t) != null) continue; ++used[t]; val fresh = seen.add(used.toList()); --used[t]; if (fresh) { chosen = t; break } }
            if (chosen >= 0) { ++used[chosen]; result.add(chosen); stack.add(fire(stack[d],chosen)); choices.add(0) }
            else { stack.removeAt(stack.lastIndex); choices.removeAt(choices.lastIndex); if (result.isNotEmpty()) --used[result.removeAt(result.lastIndex)] }
        }
        return null
    }
    fun invariants(transpose: Boolean) {
        val matrix = if (transpose) transitions.indices.map { t -> LongArray(places.size) { p -> post[p][t]-pre[p][t] } } else places.indices.map { p -> LongArray(transitions.size) { t -> post[p][t]-pre[p][t] } }
        val f = flows(matrix); val ns = if (transpose) transitions else places; val covered = BooleanArray(ns.size); val bounds = LongArray(ns.size) { -1 }
        println((if (transpose) "T" else "P")+"-semiflows: ${f.size}")
        for (c in f) { val terms = c.indices.filter { c[it] > 0 }.joinToString(" + ") { i -> (if (c[i] == 1L) "" else "${c[i]}*")+ns[i] }; for (i in c.indices) if (c[i] > 0) covered[i] = true
            if (transpose) { val sequence = realize(c); println("  $terms: " + if (sequence == null) "not realizable" else "realizable "+names(sequence).joinToString(" ")) }
            else { val value = c.indices.sumOf { c[it]*current[it] }; println("  $terms = $value"); for (p in c.indices) if (c[p] > 0) bounds[p] = if (bounds[p] < 0) value/c[p] else minOf(bounds[p],value/c[p]) }
        }
        if (!transpose) println("bounds: " + bounds.joinToString(",","(",")") { if (it < 0) "-" else it.toString() })
        println((if (transpose) "consistent: " else "conservative: ")+yes(covered.all { it }))
    }
    fun classify() {
        val inputs = transitions.indices.map { t -> places.indices.filter { pre[it][t] > 0 } }; val outputs = places.indices.map { p -> transitions.indices.filter { pre[p][it] > 0 } }
        val ordinary = places.indices.all { p -> transitions.indices.all { pre[p][it] <= 1 && post[p][it] <= 1 } }; val pure = places.indices.all { p -> transitions.indices.all { pre[p][it] == 0L || post[p][it] == 0L } }
        val sm = ordinary && transitions.indices.all { t -> inputs[t].size == 1 && places.indices.count { post[it][t] > 0 } == 1 }; val mg = ordinary && places.indices.all { p -> outputs[p].size == 1 && transitions.indices.count { post[p][it] > 0 } == 1 }
        val fc = ordinary && outputs.all { a -> a.all { a.size == 1 || inputs[it].size == 1 } }; val efc = ordinary && outputs.all { a -> outputs.all { b -> a.intersect(b.toSet()).isEmpty() || a == b } }
        for ((label,value) in listOf("ordinary" to ordinary,"pure" to pure,"state machine" to sm,"marked graph" to mg,"free choice" to fc,"extended free choice" to efc)) println("$label: ${yes(value)}")
        var verdict = if (!fc) "not applicable" else if (places.size > 12) "too many places" else "holds"
        if (fc && places.size <= 12) { val traps = sets(true); for (s in sets(false)) if (traps.none { q -> s and q == q && bits(q).any { current[it] > 0 } }) { verdict = "fails at "+setText(s); break } }
        println("commoner: $verdict")
    }
    fun workflow(limit: Int) {
        val P = places.size; val T = transitions.size; val sources = places.indices.filter { p -> transitions.indices.all { post[p][it] == 0L } }; val sinks = places.indices.filter { p -> transitions.indices.all { pre[p][it] == 0L } }
        if (sources.size != 1) { println("workflow: no (${sources.size} source places)"); return }; if (sinks.size != 1) { println("workflow: no (${sinks.size} sink places)"); return }
        val i = sources[0]; val o = sinks[0]; val ns = places+transitions; val adj = List(P+T) { mutableListOf<Int>() }; val rev = List(P+T) { mutableListOf<Int>() }
        for (p in places.indices) for (t in transitions.indices) { if (pre[p][t] > 0) { adj[p].add(P+t); rev[P+t].add(p) }; if (post[p][t] > 0) { adj[P+t].add(p); rev[p].add(P+t) } }
        val f = visit(adj,i); val b = visit(rev,o); for (v in ns.indices) if (!f[v] || !b[v]) { println("workflow: no (${ns[v]} is not on a path from ${places[i]} to ${places[o]})"); return }
        println("workflow: source ${places[i]} sink ${places[o]}"); val start = LongArray(P); val goal = LongArray(P); start[i] = 1; goal[o] = 1; val g = graph(start,limit); if (g.aborted) { println("reachability graph limit $limit exceeded"); return }
        val finish = g.states.indexOfFirst { it.contentEquals(goal) }; val back = List(g.states.size) { mutableListOf<Int>() }; val used = BooleanArray(T); for (u in g.states.indices) for (e in g.edges[u]) { back[e.target].add(u); used[e.transition] = true }
        val option = finish >= 0 && visit(back,finish).all { it }; val proper = g.states.all { it[o] < 1 || it.contentEquals(goal) }; val live = used.all { it }
        println("option to complete: ${yes(option)}\nproper completion: ${yes(proper)}\nno dead transitions: ${yes(live)}\nsound: ${yes(option&&proper&&live)}")
    }
    fun execute(w: List<String>) {
        val arity = mapOf("MARKING" to 0,"RESET" to 0,"SET" to 2,"ENABLED" to 0,"FIRE" to -1,"UNDO" to 1,"SIMULATE" to 3,"CONFLICTS" to 0,"REACH" to 1,"GRAPH" to 1,"COVER" to 1,"PATH" to 2,"INCIDENCE" to 0,"PINV" to 0,"TINV" to 0,"SIPHONS" to 0,"TRAPS" to 0,"CLASSIFY" to 0,"WORKFLOW" to 1,"SHOW" to 0)
        val cmd = w[0]; val expected = arity[cmd] ?: bad("unknown command $cmd"); if (if (expected < 0) w.size < 2 else w.size != expected+1) bad("wrong number of arguments")
        val limit = if (cmd in listOf("REACH","GRAPH","COVER","PATH","WORKFLOW")) (number(w[1],1,2000) ?: bad("invalid limit ${w[1]}")).toInt() else 0
        when (cmd) {
            "MARKING", "RESET" -> { if (cmd == "RESET") { current = initial.toLongArray(); history.clear() }; println("marking "+mark(current)) }
            "SET" -> { val p = places.indexOf(w[1]); if (p < 0) bad("unknown place ${w[1]}"); val v = number(w[2],0,999) ?: bad("invalid tokens ${w[2]}"); if (capacity[p] > 0 && v > capacity[p]) bad("tokens exceed capacity of ${w[1]}"); current = current.copyOf(); current[p] = v; history.clear(); println("marking "+mark(current)) }
            "ENABLED" -> println("enabled: "+listed(names(enabled(current))))
            "FIRE" -> { val ts = w.drop(1).map { name -> transitions.indexOf(name).takeIf { it >= 0 } ?: bad("unknown transition $name") }; for ((i,t) in ts.withIndex()) { val reason = reason(current,t); if (reason != null) { println("step ${i+1}: ${transitions[t]} not enabled ($reason) at ${mark(current)}"); return }; commit(t) }; println("fired ${ts.size} -> ${mark(current)}") }
            "UNDO" -> { val k = (number(w[1],1,1000) ?: bad("invalid count ${w[1]}")).toInt(); if (k > history.size) bad("cannot undo $k: history size ${history.size}"); current = history[history.size-k]; history.subList(history.size-k,history.size).clear(); println("marking "+mark(current)) }
            "SIMULATE" -> { val steps = (number(w[1],1,1000) ?: bad("invalid steps ${w[1]}")).toInt(); var x = number(w[2],1,2147483646) ?: bad("invalid seed ${w[2]}"); if (w[3] !in listOf("PRIORITY","RANDOM")) bad("invalid mode ${w[3]}"); val counts = IntArray(transitions.size); var done = 0
                while (done < steps) { val es = enabled(current); if (es.isEmpty()) { println("dead (steps=$done)"); break }; var t = es[0]; if (w[3] == "RANDOM") { x = x*48271%2147483647; t = es[(x%es.size).toInt()] } else for (u in es) if (priority[u] > priority[t]) t = u; commit(t); ++counts[t]; ++done; println("step $done: ${transitions[t]} -> ${mark(current)}") }; if (done == steps) println("completed (steps=$steps)"); println("counts: "+transitions.indices.joinToString(" ") { "${transitions[it]}=${counts[it]}" }) }
            "CONFLICTS" -> { val s = mutableListOf<String>(); val e = mutableListOf<String>(); for (u in transitions.indices) for (v in u+1 until transitions.size) { val pair = "${transitions[u]}/${transitions[v]}"; if (places.indices.any { pre[it][u] > 0 && pre[it][v] > 0 }) s.add(pair); if (reason(current,u) == null && reason(current,v) == null && (reason(fire(current,u),v) != null || reason(fire(current,v),u) != null)) e.add(pair) }; println("structural: ${listed(s)}\neffective: ${listed(e)}") }
            "REACH", "GRAPH" -> reach(limit,cmd=="GRAPH"); "COVER" -> cover(limit)
            "PATH" -> { val entries = w[2].split(','); if (entries.size != places.size) bad("target needs ${places.size} entries"); val target = entries.map { s -> if (s == "*") 0L to -1L else { val plus = s.endsWith('+'); val v = number(if (plus) s.dropLast(1) else s,0,9999999999) ?: bad("invalid target entry $s"); v to if (plus) -1L else v } }; val g = graph(current,limit,target); if (g.found >= 0) { val a = names(path(g,g.found)); println("reached ${mark(g.states[g.found])} length=${a.size}"+(if (a.isEmpty()) "" else ": "+a.joinToString(" "))) } else if (g.aborted) println("search limit $limit exceeded") else println("unreachable (markings explored: ${g.states.size})") }
            "INCIDENCE" -> { val rows = listOf(listOf("")+transitions)+places.indices.map { p -> listOf(places[p])+transitions.indices.map { (post[p][it]-pre[p][it]).toString() } }; val width = rows[0].indices.map { i -> rows.maxOf { it[i].length } }; for (r in rows) println(r.indices.joinToString("  ") { i -> if (i == 0) r[i].padEnd(width[i]) else r[i].padStart(width[i]) }.trimEnd()) }
            "PINV", "TINV" -> invariants(cmd=="TINV")
            "SIPHONS", "TRAPS" -> { if (places.size > 12) bad("more than 12 places"); val ss = sets(cmd=="TRAPS"); println("minimal "+(if (cmd=="TRAPS") "traps" else "siphons")+": ${ss.size}"); for (s in ss) println("  ${setText(s)} tokens=${bits(s).sumOf { current[it] }}") }
            "CLASSIFY" -> classify(); "WORKFLOW" -> workflow(limit)
            "SHOW" -> { for (p in places.indices) println("place ${places[p]} tokens=${initial[p]} capacity="+(if (capacity[p] == 0L) "none" else capacity[p].toString())); for (t in transitions.indices) { fun list(mat: Array<LongArray>): String { val a = places.indices.filter { mat[it][t] > 0 }.joinToString(",") { "${places[it]}:${mat[it][t]}" }; return a.ifEmpty { "-" } }; println("transition ${transitions[t]} priority=${priority[t]} pre=${list(pre)} post=${list(post)} inhibit=${list(inhibitor)}") } }
        }
    }
}
fun main() {
    val input = System.`in`.bufferedReader(); val blocks = input.readLine().toInt()
    repeat(blocks) { val net = Net(input.readLine().split(' ')[1]); while (true) { val line = input.readLine(); if (line == "END NET") break; try { net.define(line.split(' ')) } catch (e: IllegalArgumentException) { println("error: ${e.message}") } }; net.current = net.initial.toLongArray(); println("net ${net.name}: places=${net.places.size} transitions=${net.transitions.size} arcs=${net.arcs} inhibitors=${net.inhibitors}"); repeat(input.readLine().toInt()) { try { net.execute(input.readLine().split(' ')) } catch (e: IllegalArgumentException) { println("error: ${e.message}") } } }
}
