private class Problem(val text: String) : RuntimeException(text)

private fun fail(s: String): Nothing = throw Problem("error: $s")

private fun time(s: String) = s.take(2).toInt()*60+s.drop(3).toInt()

private fun timeText(t: Int) = "${(t/60).toString().padStart(2,'0')}:${(t%60).toString().padStart(2,'0')}"

private fun notation(p: List<Int>) = (listOf("D")+p.map {
    it.toString()
}+"D").joinToString("-")

private fun name(n: Int) = if (n == 0) "D" else n.toString()

private data class Stop(val x: Int,val y: Int,val demand: Int,val service: Int,val window: Pair<Int,Int>?)

private data class Plan(val capacity: Int,var routes: List<List<Int>>)

private data class Run(val lines: List<String>,val returned: Int,val violations: Int,val lateness: Int)

private data class TourMove(val path: List<Int>,val text: String)

private data class PlanMove(val routes: List<List<Int>>,val text: String)

private class Workbench {
    var depot: Pair<Int,Int>? = null
    var start = 480
    val stops = sortedMapOf<Int,Stop>()
    var tour: List<Int>? = null
    var plan: Plan? = null
    fun point(n: Int) = if (n == 0) depot!! else stops.getValue(n).let {
        it.x to it.y
    }
    fun d(a: Int,b: Int): Int {
        val x = point(a)
        val y = point(b)
        return kotlin.math.abs(x.first-y.first)+kotlin.math.abs(x.second-y.second)
    }
    fun length(p: List<Int>): Int {
        val all = listOf(0)+p+0
        return all.zipWithNext().sumOf {
            (a,b) -> d(a,b)
        }
    }
    fun load(p: List<Int>) = p.sumOf {
        stops.getValue(it).demand
    }
    fun normalize(routes: List<List<Int>>) = routes.filter {
        it.isNotEmpty()
    }.map {
        if (it.first() > it.last()) it.asReversed() else it
    }.sortedBy {
        it.minOrNull()!!
    }
    fun routeLines(p: Plan) = p.routes.mapIndexed {
        i,r -> "route ${i+1}: ${notation(r)} load ${load(r)} length ${length(r)}"
    }
    fun total(p: Plan) = p.routes.sumOf {
        length(it)
    }
    fun construction() {
        if (depot == null) fail("no depot")
        if (stops.isEmpty()) fail("no stops")
    }
    fun tour() = tour ?: fail("no tour")
    fun plan() = plan ?: fail("no plan")
    fun capacity(q: Int) {
        for ((n,s) in stops) if (s.demand > q) fail("stop $n demand ${s.demand} exceeds capacity $q")
    }
    fun run(p: List<Int>): Run {
        var at = 0
        var t = start
        var wait = 0
        var service = 0
        var violations = 0
        var late = 0
        val out = mutableListOf<String>()
        for (n in p) {
            val s = stops.getValue(n)
            val arrival = t+d(at,n)
            val w = maxOf(0,(s.window?.first ?: arrival)-arrival)
            val begin = arrival+w
            val e = maxOf(0,arrival-(s.window?.second ?: arrival))
            t = begin+s.service
            wait += w
            service += s.service
            if (e > 0) violations++
            late += e
            out.add("$n arrive ${timeText(arrival)} wait $w begin ${timeText(begin)} leave ${timeText(t)} "+if (e > 0) "late $e" else "ok")
            at = n
        }
        t += d(at,0)
        out.add("return ${timeText(t)}, travel ${length(p)}, wait $wait, service $service, violations $violations, lateness $late")
        return Run(out,t,violations,late)
    }
    fun firstTourMove(p: List<Int>,kind: String): TourMove? {
        val before = length(p)
        val n = p.size
        if (kind == "OROPT") {
            for (s in 1..3) for (i in 0..n-s) {
                val segment = p.subList(i,i+s)
                val rest = p.take(i)+p.drop(i+s)
                for (j in 0..rest.size) if (j != i) {
                    val next = rest.take(j)+segment+rest.drop(j)
                    val gain = before-length(next)
                    if (gain > 0) return TourMove(next,"move ${segment.joinToString("-")} after ${name(if (j == 0) 0 else rest[j-1])} gain $gain")
                }
            }
        } else for (i in 0 until n-1) for (j in i+1 until n) {
            val next = p.toMutableList()
            if (kind == "TWOOPT") for (k in i..j) next[k] = p[j-(k-i)] else {
                next[i] = p[j]
                next[j] = p[i]
            }
            val gain = before-length(next)
            if (gain > 0) return TourMove(next,if (kind == "TWOOPT") "reverse ${p[i]}..${p[j]} gain $gain" else "swap ${p[i]} and ${p[j]} gain $gain")
        }
        return null
    }
    fun firstPlanMove(p: Plan,kind: String): PlanMove? {
        val rs = p.routes
        val k = rs.size
        fun replaced(r: Int,a: List<Int>,t: Int,b: List<Int>) = rs.mapIndexed {
            i,old -> if (i == r) a else if (i == t) b else old
        }
        if (kind == "RELOCATE") {
            for (r in 0 until k) for (pos in rs[r].indices) for (t in 0 until k) if (t != r) {
                val c = rs[r][pos]
                if (load(rs[t])+stops.getValue(c).demand > p.capacity) continue
                for (j in 0..rs[t].size) {
                    val a = rs[r].filterIndexed {
                        i,_ -> i != pos
                    }
                    val b = rs[t].take(j)+c+rs[t].drop(j)
                    val gain = length(rs[r])+length(rs[t])-length(a)-length(b)
                    if (gain > 0) return PlanMove(replaced(r,a,t,b),"relocate $c from route ${r+1} to route ${t+1} after ${name(if (j == 0) 0 else rs[t][j-1])} gain $gain")
                }
            }
        } else for (r in 0 until k) for (t in r+1 until k) {
            if (kind == "EXCHANGE") {
                for (pos in rs[r].indices) for (j in rs[t].indices) {
                    val c = rs[r][pos]
                    val e = rs[t][j]
                    val a = rs[r].toMutableList()
                    val b = rs[t].toMutableList()
                    a[pos] = e
                    b[j] = c
                    if (load(a) > p.capacity || load(b) > p.capacity) continue
                    val gain = length(rs[r])+length(rs[t])-length(a)-length(b)
                    if (gain > 0) return PlanMove(replaced(r,a,t,b),"exchange $c (route ${r+1}) with $e (route ${t+1}) gain $gain")
                }
            } else for (i in 0..rs[r].size) for (j in 0..rs[t].size) {
                val a = rs[r].take(i)+rs[t].drop(j)
                val b = rs[t].take(j)+rs[r].drop(i)
                if (load(a) > p.capacity || load(b) > p.capacity) continue
                val gain = length(rs[r])+length(rs[t])-length(a)-length(b)
                if (gain > 0) return PlanMove(replaced(r,a,t,b),"cross route ${r+1} after ${name(if (i == 0) 0 else rs[r][i-1])} with route ${t+1} after ${name(if (j == 0) 0 else rs[t][j-1])} gain $gain")
            }
        }
        return null
    }
    fun mst(initial: Int,vertices: List<Int>): Pair<Int,List<String>> {
        val entered = mutableListOf(initial)
        val left = vertices.toMutableSet()
        left.remove(initial)
        var total = 0
        val edges = mutableListOf<String>()
        while (left.isNotEmpty()) {
            var best: Triple<Int,Int,Int>? = null
            for (c in left.sorted()) for ((i,p) in entered.withIndex()) {
                val candidate = Triple(d(p,c),c,i)
                val old = best
                if (old == null || candidate.first < old.first || (candidate.first == old.first && (candidate.second < old.second || (candidate.second == old.second && candidate.third < old.third)))) best = candidate
            }
            val b = best!!
            val p = entered[b.third]
            entered.add(b.second)
            left.remove(b.second)
            total += b.first
            edges.add("${name(p)}-${b.second}")
        }
        return total to edges
    }
    fun command(w: List<String>): List<String> {
        val c = w[0]
        val a = w.drop(1)
        fun n(i: Int) = a[i].toInt()
        val out = mutableListOf<String>()
        when(c) {
            "DEPOT" -> {
                depot = n(0) to n(1)
                return listOf("depot at (${a[0]},${a[1]})")
            }
            "START" -> {
                start = time(a[0])
                return listOf("start ${timeText(start)}")
            }
            "STOP" -> {
                val id = n(0)
                if (id in stops) fail("stop $id already exists")
                val window = if (a.size == 7) time(a[5]) to time(a[6]) else null
                if (window != null && window.first > window.second) fail("invalid window")
                stops[id] = Stop(n(1),n(2),n(3),n(4),window)
                tour = null
                plan = null
                return listOf("stop $id added")
            }
            "REMOVE" -> {
                val id = n(0)
                if (stops.remove(id) == null) fail("unknown stop $id")
                if (stops.isEmpty()) {
                    tour = null
                    plan = null
                } else {
                    tour = tour?.filter {
                        it != id
                    }
                    plan?.let {
                        it.routes = normalize(it.routes.map {
                            r -> r.filter {
                                it != id
                            }
                        })
                    }
                }
                return listOf("stop $id removed")
            }
            "LIST" -> {
                out.add(depot?.let {
                    "depot (${it.first},${it.second})"
                }?: "depot none")
                out.add("start ${timeText(start)}")
                out.add("stops ${stops.size}")
                for ((id,s) in stops) out.add("$id at (${s.x},${s.y}) demand ${s.demand} service ${s.service} window "+(s.window?.let {
                    "${timeText(it.first)}-${timeText(it.second)}"
                }?: "none"))
                return out
            }
            "MATRIX" -> {
                if (depot == null) fail("no depot")
                val ids = listOf(0)+stops.keys
                val rows = listOf(listOf("")+ids.map {
                    name(it)
                })+ids.map {
                    x -> listOf(name(x))+ids.map {
                        d(x,it).toString()
                    }
                }
                val width = rows.flatten().maxOf {
                    it.length
                }
                return rows.map {
                    row -> row.joinToString(" ") {
                        it.padStart(width)
                    }
                }
            }
            "TOUR" -> {
                val p = tour()
                return listOf("tour: ${notation(p)} length ${length(p)}")
            }
            "TIMECHECK" -> {
                val p: List<Int>
                if (a.isEmpty()) {
                    p = tour()
                    out.add("timecheck tour depart ${timeText(start)}")
                } else {
                    val plan = plan()
                    val r = n(0)
                    if (r > plan.routes.size) fail("no route $r")
                    p = plan.routes[r-1]
                    out.add("timecheck route $r depart ${timeText(start)}")
                }
                return out+run(p).lines
            }
            "TWOOPT","OROPT","SWAP" -> {
                var p = tour()
                val before = length(p)
                var count = 0
                while (true) {
                    val move = firstTourMove(p,c) ?: break
                    out.add(move.text)
                    p = move.path
                    count++
                }
                tour = p
                out.add("${c.lowercase()}: moves $count, length $before -> ${length(p)}")
                return out
            }
            "ROUTES" -> {
                val p = plan()
                return listOf("plan: capacity ${p.capacity}, routes ${p.routes.size}, length ${total(p)}")+routeLines(p)
            }
            "RELOCATE","EXCHANGE","CROSS" -> {
                val p = plan()
                val before = total(p)
                val countBefore = p.routes.size
                var count = 0
                while (true) {
                    val move = firstPlanMove(p,c) ?: break
                    out.add(move.text)
                    p.routes = normalize(move.routes)
                    count++
                }
                val routePart = if (c == "EXCHANGE") "" else "routes $countBefore -> ${p.routes.size}, "
                out.add("${c.lowercase()}: moves $count, ${routePart}length $before -> ${total(p)}")
                return out
            }
            "ROUTEOPT" -> {
                val p = plan()
                val before = total(p)
                val routes = mutableListOf<List<Int>>()
                for ((i,original) in p.routes.withIndex()) {
                    var route = original
                    var count = 0
                    while (true) {
                        val move = firstTourMove(route,"TWOOPT") ?: break
                        route = move.path
                        count++
                    }
                    out.add("route ${i+1}: moves $count, length ${length(original)} -> ${length(route)}")
                    routes.add(route)
                }
                p.routes = normalize(routes)
                out.add("routeopt: length $before -> ${total(p)}")
                return out
            }
            "REPORT" -> {
                out.add("report: stops ${stops.size}, demand ${stops.values.sumOf { it.demand }}, service ${stops.values.sumOf { it.service }}, windows ${stops.values.count { it.window != null }}")
                val tour = tour
                if (tour == null) out.add("tour: none") else {
                    val run = run(tour)
                    out.add("tour: length ${length(tour)}, return ${timeText(run.returned)}, violations ${run.violations}, lateness ${run.lateness}")
                }
                val p = plan
                if (p == null) out.add("plan: none") else {
                    val runs = p.routes.map {
                        run(it)
                    }
                    val capacity = p.routes.size*p.capacity
                    val u = (2000*stops.values.sumOf {
                        it.demand
                    }+capacity)/(2*capacity)
                    out.add("plan: capacity ${p.capacity}, routes ${p.routes.size}, length ${total(p)}, utilization ${u/10}.${u%10}%, return ${timeText(runs.maxOf { it.returned })}, violations ${runs.sumOf { it.violations }}, lateness ${runs.sumOf { it.lateness }}")
                }
                return out
            }
            "SPLIT" -> {
                val p = tour()
                val q = n(0)
                capacity(q)
                val values = IntArray(p.size+1) {
                    Int.MAX_VALUE
                }
                val previous = IntArray(p.size+1)
                values[0] = 0
                for (j in 1..p.size) for (i in 0 until j) {
                    val part = p.subList(i,j)
                    if (load(part) <= q) {
                        val candidate = values[i]+length(part)
                        if (candidate < values[j]) {
                            values[j] = candidate
                            previous[j] = i
                        }
                    }
                }
                val routes = mutableListOf<List<Int>>()
                var j = p.size
                while (j > 0) {
                    val i = previous[j]
                    routes.add(p.subList(i,j).toList())
                    j = i
                }
                val result = Plan(q,normalize(routes))
                plan = result
                return listOf("split: capacity $q, routes ${result.routes.size}, length ${total(result)}")+routeLines(result)
            }
        }
        construction()
        when(c) {
            "ORDER" -> {
                val ids = a.map {
                    it.toInt()
                }
                for (id in ids) if (id !in stops) fail("unknown stop $id")
                val seen = mutableSetOf<Int>()
                for (id in ids) if (!seen.add(id)) fail("duplicate stop $id")
                if (ids.size != stops.size) fail("order has ${ids.size} stops, expected ${stops.size}")
                tour = ids
            }
            "NEAREST" -> {
                val remaining = stops.keys.toMutableSet()
                val p = mutableListOf<Int>()
                var at = 0
                while (remaining.isNotEmpty()) {
                    val next = remaining.minWith(compareBy<Int> {
                        d(at,it)
                    }.thenBy {
                        it
                    })
                    p.add(next)
                    remaining.remove(next)
                    at = next
                }
                tour = p
            }
            "INSERTION" -> {
                val p = mutableListOf<Int>()
                while (p.size < stops.size) {
                    var best: Triple<Int,Int,Int>? = null
                    for (id in stops.keys) if (id !in p) for (j in 0..p.size) {
                        val left = if (j == 0) 0 else p[j-1]
                        val right = if (j == p.size) 0 else p[j]
                        val gain = d(left,id)+d(id,right)-d(left,right)
                        val old = best
                        if (old == null || gain < old.first || (gain == old.first && (id < old.second || (id == old.second && j < old.third)))) best = Triple(gain,id,j)
                    }
                    val b = best!!
                    p.add(b.third,b.second)
                }
                tour = p
            }
            "EXACT" -> {
                if (stops.size > 10) fail("too many stops for exact (${stops.size})")
                val ids = stops.keys.toList()
                val memo = mutableMapOf<Pair<Int,Int>,Int>()
                val full = (1 shl ids.size)-1
                fun cost(mask: Int,at: Int): Int {
                    if (mask == full) return d(at,0)
                    return memo.getOrPut(mask to at) {
                        ids.indices.filter {
                            mask and (1 shl it) == 0
                        }.minOf {
                            d(at,ids[it])+cost(mask or (1 shl it),ids[it])
                        }
                    }
                }
                val p = mutableListOf<Int>()
                var mask = 0
                var at = 0
                while (mask != full) {
                    val target = cost(mask,at)
                    val i = ids.indices.first {
                        mask and (1 shl it) == 0 && d(at,ids[it])+cost(mask or (1 shl it),ids[it]) == target
                    }
                    at = ids[i]
                    p.add(at)
                    mask = mask or (1 shl i)
                }
                tour = p
            }
            "BOUND" -> {
                val ids = stops.keys.toList()
                val (m,edges) = mst(0,ids)
                val tree = if (ids.size == 1) 2*d(0,ids[0]) else mst(ids[0],ids).first+ids.map {
                    d(0,it)
                }.sorted().take(2).sum()
                val bound = maxOf(m,tree)
                out.add("mst: ${edges.joinToString(" ")} (length $m)")
                out.add("bound: mst $m, one-tree $tree, best $bound")
                val p = tour
                if (p == null) out.add("gap: no tour") else {
                    val l = length(p)
                    val u = if (bound == 0) 0 else (2000*(l-bound)+bound)/(2*bound)
                    out.add("gap: tour $l, ${u/10}.${u%10}%")
                }
                return out
            }
            "VRP","SWEEP" -> {
                val q = n(0)
                capacity(q)
                val limit = if (a.size == 2) n(1) else null
                if (limit != null) for (id in stops.keys) if (2*d(0,id) > limit) fail("stop $id too far for limit $limit")
                var merges = 0
                val routes = mutableListOf<List<Int>>()
                if (c == "VRP") {
                    routes.addAll(stops.keys.map {
                        listOf(it)
                    })
                    val ids = stops.keys.toList()
                    val savings = ids.flatMapIndexed {
                        i,x -> ids.drop(i+1).map {
                            y -> Triple(d(0,x)+d(0,y)-d(x,y),x,y)
                        }
                    }.filter {
                        it.first > 0
                    }.sortedWith(compareByDescending<Triple<Int,Int,Int>> {
                        it.first
                    }.thenBy {
                        it.second
                    }.thenBy {
                        it.third
                    })
                    for ((_,x,y) in savings) {
                        val ia = routes.indexOfFirst {
                            x in it
                        }
                        val ib = routes.indexOfFirst {
                            y in it
                        }
                        if (ia == ib) continue
                        var left = routes[ia]
                        var right = routes[ib]
                        if (x != left.first() && x != left.last() || y != right.first() && y != right.last()) continue
                        if (load(left)+load(right) > q) continue
                        if (left.last() != x) left = left.asReversed()
                        if (right.first() != y) right = right.asReversed()
                        val joined = left+right
                        if (limit != null && length(joined) > limit) continue
                        routes[ia] = joined
                        routes.removeAt(ib)
                        merges++
                    }
                } else {
                    val center = depot!!
                    val ids = stops.keys.sortedWith(Comparator {
                        x,y -> val a = point(x)
                        val b = point(y)
                        val ax = a.first-center.first
                        val ay = a.second-center.second
                        val bx = b.first-center.first
                        val by = b.second-center.second
                        val az = ax == 0 && ay == 0
                        val bz = bx == 0 && by == 0
                        if (az || bz) {
                            if (az != bz) {
                                if (az) -1 else 1
                            } else x.compareTo(y)
                        } else {
                            val ah = if (ay > 0 || ay == 0 && ax > 0) 0 else 1
                            val bh = if (by > 0 || by == 0 && bx > 0) 0 else 1
                            val cross = ax*by-ay*bx
                            if (ah != bh) ah-bh else if (cross != 0) {
                                if (cross > 0) -1 else 1
                            } else if (d(0,x) != d(0,y)) d(0,x)-d(0,y) else x-y
                        }
                    })
                    var route = mutableListOf<Int>()
                    var load = 0
                    for (id in ids) {
                        val demand = stops.getValue(id).demand
                        if (load+demand > q) {
                            routes.add(route)
                            route = mutableListOf()
                            load = 0
                        }
                        route.add(id)
                        load += demand
                    }
                    routes.add(route)
                }
                val result = Plan(q,normalize(routes))
                plan = result
                out.add(if (c == "VRP") "vrp: capacity $q, merges $merges, routes ${result.routes.size}, length ${total(result)}" else "sweep: capacity $q, routes ${result.routes.size}, length ${total(result)}")
                out.addAll(routeLines(result))
                return out
            }
        }
        val p = tour()
        return listOf("${c.lowercase()}: ${notation(p)} length ${length(p)}")
    }
}

fun main() {
    val workbench = Workbench()
    repeat(readLine()!!.toInt()) {
        try {
            workbench.command(readLine()!!.split(' ')).forEach(::println)
        } catch (p: Problem) {
            println(p.text)
        }
    }
}
