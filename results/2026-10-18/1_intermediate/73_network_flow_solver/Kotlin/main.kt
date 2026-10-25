private class Problem(val text: String) : RuntimeException(text)

private fun fail(reason: String): Nothing = throw Problem("ERROR $reason")

private data class Edge(val from: Int, val to: Int, var capacity: Long, var cost: Long = 0, var lower: Long = 0, var flow: Long = 0)

private data class Arc(val edge: Int, val forward: Boolean)

private sealed interface Owner

private data object NoOwner : Owner

private data class FlowOwner(val source: Int, val sink: Int) : Owner

private data object CirculationOwner : Owner

private data class Pushed(val arcs: List<Arc>, val amount: Long, val phase: Int = 0, val delta: Long = 1, val cost: Long = 0)

private data class Component(val start: Int, val edges: List<Int>, val amount: Long, val cycle: Boolean)

private class Network {
    val names = mutableListOf<String>()
    val demands = mutableListOf<Long>()
    val edges = mutableListOf<Edge>()
    var owner: Owner = NoOwner
    fun copy(): Network {
        val n = Network()
        n.names.addAll(names)
        n.demands.addAll(demands)
        n.edges.addAll(edges.map {
            it.copy()
        })
        n.owner = owner
        return n
    }
    fun node(name: String) = names.indexOf(name).takeIf {
        it >= 0
    }?: fail("UNKNOWN NODE $name")
    fun endpoints(a: String, b: String): Pair<Int,Int> {
        val s = node(a)
        val t = node(b)
        if (s == t) fail("SAME NODE")
        return s to t
    }
    fun edgeNumber(text: String) = text.toInt().takeIf {
        it in 1..edges.size
    }?.minus(1) ?: fail("UNKNOWN EDGE $text")
    fun globalArcs() = listOf(true,false).flatMap {
        forward -> edges.indices.map {
            Arc(it,forward)
        }
    }
    fun arcs(node: Int) = globalArcs().filter {
        start(it) == node
    }
    fun start(a: Arc) = if (a.forward) edges[a.edge].from else edges[a.edge].to
    fun end(a: Arc) = if (a.forward) edges[a.edge].to else edges[a.edge].from
    fun residual(a: Arc) = edges[a.edge].let {
        if (a.forward) it.capacity-it.flow else it.flow
    }
    fun arcCost(a: Arc) = if (a.forward) edges[a.edge].cost else -edges[a.edge].cost
    fun push(path: List<Arc>, amount: Long) {
        for (a in path) edges[a.edge].flow += if (a.forward) amount else -amount
    }
    fun bottleneck(path: List<Arc>) = path.minOf {
        residual(it)
    }
    fun balances(): LongArray {
        val b = LongArray(names.size)
        for (e in edges) {
            b[e.from] += e.flow
            b[e.to] -= e.flow
        }
        return b
    }
    fun cost() = edges.sumOf {
        it.flow*it.cost
    }
    fun zero() {
        for (e in edges) e.flow = 0
    }
    fun begin(s: Int, t: Int): Long {
        if (owner != FlowOwner(s,t)) zero()
        owner = FlowOwner(s,t)
        return balances()[s]
    }
    fun bfs(s: Int, delta: Long = 1): Pair<IntArray,List<Arc?>> {
        val level = IntArray(names.size) {
            -1
        }
        val parent = MutableList<Arc?>(names.size) {
            null
        }
        val queue = ArrayDeque<Int>()
        queue.addLast(s)
        level[s] = 0
        while (queue.isNotEmpty()) {
            val u = queue.removeFirst()
            for (a in arcs(u)) {
                val v = end(a)
                if (residual(a) >= delta && level[v] < 0) {
                    level[v] = level[u]+1
                    parent[v] = a
                    queue.addLast(v)
                }
            }
        }
        return level to parent
    }
    fun path(s: Int, t: Int, parent: List<Arc?>): List<Arc> {
        val path = mutableListOf<Arc>()
        var at = t
        while (at != s) {
            val a = parent[at]!!
            path.add(a)
            at = start(a)
        }
        return path.asReversed()
    }
    fun augment(s: Int, t: Int, delta: Long = 1): Pushed? {
        val (level,parent) = bfs(s,delta)
        if (level[t] < 0) return null
        val arcs = path(s,t,parent)
        val amount = bottleneck(arcs)
        push(arcs,amount)
        return Pushed(arcs,amount,delta=delta)
    }
    fun maxflow(s: Int, t: Int): List<Pushed> {
        val result = mutableListOf<Pushed>()
        while (true) result.add(augment(s,t) ?: break)
        return result
    }
    fun dinic(s: Int, t: Int): Pair<Int,List<Pushed>> {
        var phases = 0
        val pushed = mutableListOf<Pushed>()
        while (true) {
            val (level,_) = bfs(s)
            if (level[t] < 0) return phases to pushed
            phases++
            val lists = names.indices.map {
                arcs(it)
            }
            val pointers = IntArray(names.size)
            var path = mutableListOf<Arc>()
            var u = s
            while (true) {
                if (u == t) {
                    val amount = bottleneck(path)
                    push(path,amount)
                    pushed.add(Pushed(path.toList(),amount,phase=phases))
                    path = mutableListOf()
                    u = s
                } else if (pointers[u] == lists[u].size) {
                    if (u == s) break
                    val a = path.removeAt(path.lastIndex)
                    u = start(a)
                    pointers[u]++
                } else {
                    val a = lists[u][pointers[u]]
                    val v = end(a)
                    if (residual(a) > 0 && level[v] >= 0 && level[v] == level[u]+1) {
                        path.add(a)
                        u = v
                    } else pointers[u]++
                }
            }
        }
    }
    fun scaling(s: Int, t: Int): List<Pushed> {
        val capacity = edges.maxOfOrNull {
            it.capacity
        }?: 0
        var delta = 1L
        while (delta*2 <= capacity) delta *= 2
        val paths = mutableListOf<Pushed>()
        while (delta >= 1) {
            while (true) paths.add(augment(s,t,delta) ?: break)
            delta /= 2
        }
        return paths
    }
    fun negativeCycle(residualLower: Boolean): Boolean {
        val distance = LongArray(names.size)
        repeat(names.size) {
            pass -> var changed = false
            for (e in edges) if (e.capacity-(if (residualLower) e.lower else 0) > 0 && distance[e.to] > distance[e.from]+e.cost) {
                distance[e.to] = distance[e.from]+e.cost
                changed = true
            }
            if (!changed) return false
            if (pass == names.lastIndex) return true
        }
        return false
    }
    fun shortest(s: Int): Pair<List<Long?>,List<Arc?>> {
        val arcs = globalArcs().filter {
            residual(it) > 0
        }
        val distance = MutableList<Long?>(names.size) {
            null
        }
        val parent = MutableList<Arc?>(names.size) {
            null
        }
        distance[s] = 0
        while (true) {
            var changed = false
            for (a in arcs) {
                val u = start(a)
                val v = end(a)
                val d = distance[u] ?: continue
                val next = d+arcCost(a)
                if (distance[v] == null || next < distance[v]!!) {
                    distance[v] = next
                    parent[v] = a
                    changed = true
                }
            }
            if (!changed) return distance to parent
        }
    }
    fun mincost(s: Int, t: Int, target: Long? = null): Triple<Long,Long,List<Pushed>> {
        var amount = 0L
        var cost = 0L
        val paths = mutableListOf<Pushed>()
        while (target == null || amount < target) {
            val (distance,parent) = shortest(s)
            val unit = distance[t] ?: break
            val arcs = path(s,t,parent)
            var delta = bottleneck(arcs)
            if (target != null) delta = minOf(delta,target-amount)
            push(arcs,delta)
            amount += delta
            cost += delta*unit
            paths.add(Pushed(arcs,delta,cost=unit))
        }
        return Triple(amount,cost,paths)
    }
    fun notation(start: Int, path: List<Arc>) = names[start]+path.joinToString("") {
        " ${if (it.forward) "+" else "-"}${it.edge+1} ${names[end(it)]}"
    }
    fun flows() = edges.mapIndexed {
        i,e -> "FLOW ${i+1} ${names[e.from]} ${names[e.to]} ${e.flow}/${e.capacity}"
    }
    fun decompose(): List<Component> {
        val g = edges.map {
            it.flow
        }.toLongArray()
        val balance = balances()
        val result = mutableListOf<Component>()
        while (g.any {
            it > 0
        }) {
            val first = g.indexOfFirst {
                it > 0
            }
            val start = balance.indexOfFirst {
                it > 0
            }.takeIf {
                it >= 0
            }?: edges[first].from
            val vertices = mutableListOf(start)
            val path = mutableListOf<Int>()
            while (true) {
                val u = vertices.last()
                val i = edges.indices.first {
                    edges[it].from == u && g[it] > 0
                }
                val v = edges[i].to
                path.add(i)
                val q = vertices.indexOf(v)
                if (q >= 0) {
                    val cycle = path.drop(q)
                    val delta = cycle.minOf {
                        g[it]
                    }
                    for (e in cycle) g[e] -= delta
                    result.add(Component(v,cycle,delta,true))
                    break
                }
                vertices.add(v)
                if (balance[v] < 0) {
                    val delta = minOf(path.minOf {
                        g[it]
                    },balance[start],-balance[v])
                    for (e in path) g[e] -= delta
                    balance[start] -= delta
                    balance[v] += delta
                    result.add(Component(start,path.toList(),delta,false))
                    break
                }
            }
        }
        return result
    }
    fun command(w: List<String>): List<String> {
        val c = w[0]
        val a = w.drop(1)
        fun num(i: Int) = a[i].toLong()
        val out = mutableListOf<String>()
        when(c) {
            "NODE" -> {
                val seen = names.toMutableSet()
                for (name in a) if (!seen.add(name)) fail("DUPLICATE NODE $name")
                if (names.size+a.size > 20) fail("TOO MANY NODES")
                names.addAll(a)
                repeat(a.size) {
                    demands.add(0)
                }
                out.add("NODE added=${a.size} total=${names.size}")
            }
            "EDGE" -> {
                val u = node(a[0])
                val v = node(a[1])
                if (u == v) fail("SELF LOOP")
                if (edges.size == 60) fail("TOO MANY EDGES")
                val cost = if (a.size == 4) num(3) else 0L
                edges.add(Edge(u,v,num(2),cost))
                out.add("EDGE ${edges.size} ${a[0]} ${a[1]} cap=${num(2)} cost=$cost")
            }
            "LOWER","CAP","COST" -> {
                val e = edges[edgeNumber(a[0])]
                val n = num(1)
                when(c) {
                    "LOWER" -> {
                        if (n > e.capacity) fail("BAD BOUND")
                        e.lower = n
                        out.add("LOWER ${a[0]} low=$n cap=${e.capacity}")
                    }
                    "CAP" -> {
                        if (n < e.lower) fail("BAD BOUND")
                        if (n < e.flow) fail("BELOW FLOW")
                        e.capacity = n
                        out.add("CAP ${a[0]} low=${e.lower} cap=$n")
                    } else -> {
                        e.cost = n
                        out.add("COST ${a[0]} cost=$n")
                    }
                }
            }
            "DEMAND" -> {
                demands[node(a[0])] = num(1)
                out.add("DEMAND ${a[0]} ${num(1)} total=${demands.sum()}")
            }
            "RESET" -> {
                out.add("RESET edges=${edges.count { it.flow != 0L }}")
                zero()
                owner = NoOwner
            }
            "CLEAR" -> {
                out.add("CLEAR nodes=${names.size} edges=${edges.size}")
                names.clear()
                demands.clear()
                edges.clear()
                owner = NoOwner
            }
            "SHOW" -> {
                val balance = balances()
                out.add("NETWORK nodes=${names.size} edges=${edges.size}")
                out.add(when(val owner = owner) {
                    NoOwner -> "STATE none"
                    CirculationOwner -> "STATE circulation cost=${cost()}"
                    is FlowOwner -> "STATE flow ${names[owner.source]} ${names[owner.sink]} value=${balance[owner.source]} cost=${cost()}"
                })
                for ((i,name) in names.withIndex()) out.add("NODE $name demand=${demands[i]} out=${edges.filter { it.from == i }.sumOf { it.flow }} in=${edges.filter { it.to == i }.sumOf { it.flow }}")
                for ((i,e) in edges.withIndex()) out.add("EDGE ${i+1} ${names[e.from]} ${names[e.to]} cap=${e.capacity} cost=${e.cost} low=${e.lower} flow=${e.flow}")
            }
            "AUGMENT","MAXFLOW","DINIC","SCALING","MINCUT" -> {
                val (s,t) = endpoints(a[0],a[1])
                val start = begin(s,t)
                if (c == "AUGMENT") {
                    val p = augment(s,t)
                    out.add(if (p == null) "AUGMENT ${a[0]} ${a[1]} value=${balances()[s]} none" else "AUGMENT ${a[0]} ${a[1]} value=${balances()[s]} amount=${p.amount} ${notation(s,p.arcs)}")
                } else if (c == "MINCUT") {
                    maxflow(s,t)
                    val (level,_) = bfs(s)
                    val cut = edges.indices.filter {
                        level[edges[it].from] >= 0 && level[edges[it].to] < 0
                    }
                    out.add("MINCUT ${a[0]} ${a[1]} value=${balances()[s]} edges=${cut.size}")
                    out.add("SOURCE "+names.indices.filter {
                        level[it] >= 0
                    }.joinToString(" ") {
                        names[it]
                    })
                    out.add("SINK "+names.indices.filter {
                        level[it] < 0
                    }.joinToString(" ") {
                        names[it]
                    })
                    for (i in cut) {
                        val e = edges[i]
                        out.add("CUT ${i+1} ${names[e.from]} ${names[e.to]} ${e.capacity}")
                    }
                } else {
                    val (phases,paths) = when(c) {
                        "DINIC" -> dinic(s,t)
                        "SCALING" -> 0 to scaling(s,t)
                        else -> 0 to maxflow(s,t)
                    }
                    out.add("$c ${a[0]} ${a[1]} value=${balances()[s]} start=$start${if (c == "DINIC") " phases=$phases" else ""} paths=${paths.size}")
                    for ((i,p) in paths.withIndex()) out.add("AUG ${i+1}${if (c == "DINIC") " phase=${p.phase}" else if (c == "SCALING") " delta=${p.delta}" else ""} amount=${p.amount} ${notation(s,p.arcs)}")
                    out.addAll(flows())
                }
            }
            "SENSITIVITY" -> {
                val (s,t) = endpoints(a[0],a[1])
                val base = copy()
                base.zero()
                base.maxflow(s,t)
                val value = base.balances()[s]
                var up = 0
                var down = 0
                val details = mutableListOf<String>()
                for (i in edges.indices) {
                    val work = copy()
                    work.zero()
                    work.edges[i].capacity++
                    work.maxflow(s,t)
                    val effectiveUp = work.balances()[s] > value
                    var effectiveDown = false
                    if (edges[i].capacity > 0) {
                        val reduced = copy()
                        reduced.zero()
                        reduced.edges[i].capacity--
                        reduced.maxflow(s,t)
                        effectiveDown = reduced.balances()[s] < value
                    }
                    if (effectiveUp) up++
                    if (effectiveDown) down++
                    if (effectiveUp || effectiveDown) {
                        val e = edges[i]
                        details.add("CRITICAL ${i+1} ${names[e.from]} ${names[e.to]} up=${if (effectiveUp) "yes" else "no"} down=${if (effectiveDown) "yes" else "no"}")
                    }
                }
                out.add("SENSITIVITY ${a[0]} ${a[1]} value=$value up=$up down=$down")
                out.addAll(details)
            }
            "MINCOST" -> {
                val (s,t) = endpoints(a[0],a[1])
                if (negativeCycle(false)) fail("NEGATIVE CYCLE")
                val target = if (a[2] == "MAX") null else num(2)
                val work = copy()
                work.zero()
                val (amount,cost,paths) = work.mincost(s,t,target)
                if (target != null && amount < target) out.add("MINCOST ${a[0]} ${a[1]} k=${a[2]} infeasible max=$amount") else {
                    for (i in edges.indices) edges[i].flow = work.edges[i].flow
                    owner = FlowOwner(s,t)
                    out.add("MINCOST ${a[0]} ${a[1]} k=${a[2]} flow=$amount cost=$cost")
                    for ((i,p) in paths.withIndex()) out.add("AUG ${i+1} amount=${p.amount} cost=${p.cost} ${notation(s,p.arcs)}")
                    out.addAll(flows())
                }
            }
            "DISJOINT" -> {
                val (s,t) = endpoints(a[0],a[1])
                val original = edges.size
                val work = copy()
                work.zero()
                val exits = IntArray(names.size) {
                    it
                }
                if (a[2] == "VERTEX") for (v in names.indices) if (v != s && v != t) {
                    exits[v] = work.names.size
                    work.names.add(names[v])
                    work.demands.add(0)
                }
                for (i in work.edges.indices) {
                    val e = work.edges[i]
                    work.edges[i] = e.copy(from=exits[e.from],capacity=if (e.capacity > 0) 1 else 0,cost=0)
                }
                if (a[2] == "VERTEX") for (v in names.indices) if (v != s && v != t) work.edges.add(Edge(v,exits[v],1))
                work.maxflow(s,t)
                val paths = work.decompose().filter {
                    !it.cycle
                }
                out.add("DISJOINT ${a[0]} ${a[1]} ${a[2]} count=${paths.size}")
                for ((i,p) in paths.withIndex()) out.add("PATH ${i+1} ${notation(s,p.edges.filter { it < original }.map { Arc(it,true) })}")
            }
            "DECOMPOSE" -> {
                val parts = decompose()
                out.add("DECOMPOSE paths=${parts.count { !it.cycle }} cycles=${parts.count { it.cycle }}")
                val counts = IntArray(2)
                for (p in parts) {
                    val kind = if (p.cycle) 1 else 0
                    counts[kind]++
                    out.add("${if (p.cycle) "CYCLE" else "PATH"} ${counts[kind]} amount=${p.amount} ${notation(p.start,p.edges.map { Arc(it,true) })}")
                }
            }
            "VERIFY" -> {
                val violations = mutableListOf<String>()
                for ((i,e) in edges.withIndex()) if (e.flow < e.lower) violations.add("LOW ${i+1} flow=${e.flow} low=${e.lower}")
                val balance = balances()
                for (i in names.indices) {
                    val owner = owner
                    val need = if (owner is FlowOwner) {
                        if (i == owner.source || i == owner.sink) null else 0L
                    } else demands[i]
                    if (need != null && -balance[i] != need) violations.add("BALANCE ${names[i]} net=${-balance[i]} need=$need")
                }
                if (violations.isEmpty()) out.add("VERIFY ok") else {
                    out.add("VERIFY violations=${violations.size}")
                    out.addAll(violations)
                }
            }
            "CIRCULATION" -> {
                if (a[0] == "MINCOST" && negativeCycle(true)) fail("NEGATIVE CYCLE")
                val sum = demands.sum()
                if (sum != 0L) return listOf("CIRCULATION infeasible unbalanced=$sum")
                val n = names.size
                val work = copy()
                work.names.addAll(listOf("super source","super sink"))
                work.demands.addAll(listOf(0L,0L))
                val required = demands.toLongArray()
                for (e in work.edges) {
                    required[e.to] -= e.lower
                    required[e.from] += e.lower
                    e.capacity -= e.lower
                    e.flow = 0
                }
                for (v in required.indices) if (required[v] < 0) work.edges.add(Edge(n,v,-required[v]))
                val sinkStart = work.edges.size
                for (v in required.indices) if (required[v] > 0) work.edges.add(Edge(v,n+1,required[v]))
                if (a[0] == "ANY") work.maxflow(n,n+1) else work.mincost(n,n+1)
                val total = required.filter {
                    it > 0
                }.sum()
                val achieved = work.edges.drop(sinkStart).sumOf {
                    it.flow
                }
                if (achieved < total) {
                    val (level,_) = work.bfs(n)
                    out.add("CIRCULATION infeasible required=$total achieved=$achieved")
                    out.add("CUT "+names.indices.filter {
                        level[it] >= 0
                    }.joinToString(" ") {
                        names[it]
                    })
                } else {
                    for (i in edges.indices) edges[i].flow = edges[i].lower+work.edges[i].flow
                    owner = CirculationOwner
                    out.add("CIRCULATION feasible required=$total cost=${cost()}")
                    out.addAll(flows())
                }
            }
            "MATCH" -> out.addAll(matching(a))
            "ASSIGN" -> out.addAll(assignment(a))
        }
        return out
    }
}

private fun matching(a: List<String>): List<String> {
    val left = a[0].split(',')
    val right = a[1].split(',')
    val seen = mutableSetOf<String>()
    for (n in left+right) if (!seen.add(n)) fail("DUPLICATE VERTEX $n")
    val pairs = mutableListOf<Pair<Int,Int>>()
    if (a[2] != "-") for (p in a[2].split(',')) {
        val words = p.split('-')
        val u = left.indexOf(words[0]).takeIf {
            it >= 0
        }?: fail("UNKNOWN VERTEX ${words[0]}")
        val v = right.indexOf(words[1]).takeIf {
            it >= 0
        }?: fail("UNKNOWN VERTEX ${words[1]}")
        if ((u to v) in pairs) fail("DUPLICATE PAIR $p")
        pairs.add(u to v)
    }
    val lp = IntArray(left.size) {
        -1
    }
    val rp = IntArray(right.size) {
        -1
    }
    fun attempt(u: Int, examined: BooleanArray): Boolean {
        for ((x,b) in pairs) if (x == u && !examined[b]) {
            examined[b] = true
            if (rp[b] < 0 || attempt(rp[b],examined)) {
                lp[u] = b
                rp[b] = u
                return true
            }
        }
        return false
    }
    for (u in left.indices) attempt(u,BooleanArray(right.size))
    val zl = BooleanArray(left.size) {
        lp[it] < 0
    }
    val zr = BooleanArray(right.size)
    while (true) {
        var changed = false
        for ((u,v) in pairs) if (zl[u] && lp[u] != v && !zr[v]) {
            zr[v] = true
            changed = true
        }
        for (v in right.indices) if (zr[v] && rp[v] >= 0 && !zl[rp[v]]) {
            zl[rp[v]] = true
            changed = true
        }
        if (!changed) break
    }
    val size = lp.count {
        it >= 0
    }
    val out = mutableListOf("MATCH size=$size left=${left.size} right=${right.size}")
    for (u in left.indices) if (lp[u] >= 0) out.add("PAIR ${left[u]} ${right[lp[u]]}")
    fun list(values: List<String>) = values.joinToString(",").ifEmpty {
        "-"
    }
    out.add("FREE ${list(left.indices.filter { lp[it] < 0 }.map { left[it] })} ${list(right.indices.filter { rp[it] < 0 }.map { right[it] })}")
    val cover = left.indices.filter {
        !zl[it]
    }.map {
        left[it]
    }+right.indices.filter {
        zr[it]
    }.map {
        right[it]
    }
    out.add("COVER size=${cover.size}"+cover.joinToString("") {
        " $it"
    })
    if (lp.any {
        it < 0
    }) out.add("HALL ${list(left.indices.filter { zl[it] }.map { left[it] })} ${list(right.indices.filter { zr[it] }.map { right[it] })}")
    return out
}

private fun assignment(a: List<String>): List<String> {
    val n = a[1].toInt()
    if (n !in 1..8) fail("BAD SIZE")
    if (a.size-2 != n*n) fail("BAD LENGTH")
    val values = a.drop(2).map {
        if (it == "x") null else it.toLong()
    }
    var best: Long? = null
    var count = 0
    var first = emptyList<Int>()
    val chosen = mutableListOf<Int>()
    fun visit(used: Int, sum: Long) {
        val row = chosen.size
        if (row == n) {
            if (best == null || (if (a[0] == "MAX") sum > best!! else sum < best!!)) {
                best = sum
                count = 1
                first = chosen.toList()
            } else if (sum == best) count++
            return
        }
        for (col in 0 until n) if (used and (1 shl col) == 0) {
            val v = values[row*n+col] ?: continue
            chosen.add(col)
            visit(used or (1 shl col),sum+v)
            chosen.removeAt(chosen.lastIndex)
        }
    }
    visit(0,0)
    if (best == null) return listOf("ASSIGN ${a[0]} n=$n infeasible")
    return listOf("ASSIGN ${a[0]} n=$n total=$best optimal=$count")+first.mapIndexed {
        row,col -> "MATE ${row+1} ${col+1} ${values[row*n+col]}"
    }
}

fun main() {
    val network = Network()
    repeat(readLine()!!.toInt()) {
        try {
            network.command(readLine()!!.split(' ')).forEach(::println)
        } catch (p: Problem) {
            println(p.text)
        }
    }
}
