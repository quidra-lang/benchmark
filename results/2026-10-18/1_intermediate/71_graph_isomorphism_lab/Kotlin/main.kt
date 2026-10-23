private class Problem(val text: String) : RuntimeException(text)
private fun fail(reason: String): Nothing = throw Problem("error: $reason")
private fun numbers(values: List<Int>) = values.joinToString(" ")
private fun yes(value: Boolean) = if (value) "yes" else "no"
private fun shown(value: Int?, absent: String) = value?.toString() ?: absent
private fun colorCount(colors: List<Int>) = colors.max()+1
private fun individualize(colors: List<Int>, v: Int) = colors.mapIndexed {
    w, c -> if (c < colors[v] || w == v) c else c+1
}
private fun compareLists(a: List<Int>, b: List<Int>): Int {
    for (i in 0 until minOf(a.size, b.size)) if (a[i] != b[i]) return a[i].compareTo(b[i])
    return a.size.compareTo(b.size)
}
private data class Canonical(var nodes: Int = 0, var leaves: Int = 0, var text: String = "", var label: List<Int> = emptyList(), val winners: MutableList<List<Int>> = mutableListOf())
private data class Invariants(val degrees: List<Int>, val triangles: Int, val sizes: List<Int>, val girth: Int?, val diameter: Int?, val radius: Int?, val bipartite: Boolean)
private class Graph(val n: Int) {
    val adjacent = IntArray(n)
    fun has(u: Int, v: Int) = adjacent[u] and (1 shl v) != 0
    fun join(u: Int, v: Int) {
        adjacent[u] = adjacent[u] or (1 shl v)
        adjacent[v] = adjacent[v] or (1 shl u)
    }
    fun edges(): List<Pair<Int, Int>> = buildList {
        for (u in 0 until n) for (v in u+1 until n) if (has(u, v)) add(u to v)
    }
    fun degrees() = adjacent.map {
        it.countOneBits()
    }
    fun refine(input: List<Int>): Pair<List<Int>, Int> {
        var colors = input
        var rounds = 0
        while (true) {
            val signatures = (0 until n).map {
                v -> colors[v] to (0 until n).filter {
                    has(v, it)
                }.map {
                    colors[it]
                }.sorted()
            }
            val order = Comparator<Pair<Int, List<Int>>> {
                a, b -> a.first.compareTo(b.first).takeIf {
                    it != 0
                } ?: compareLists(a.second, b.second)
            }
            val unique = signatures.distinct().sortedWith(order)
            if (unique.size == colorCount(colors)) return colors to rounds
            colors = signatures.map {
                unique.binarySearch(it, order)
            }
            rounds++
        }
    }
    fun stable(): Pair<List<Int>, Int> {
        val d = degrees()
        val unique = d.distinct().sorted()
        return refine(d.map {
            unique.indexOf(it)
        })
    }
    fun leafString(colors: List<Int>): String {
        val inverse = IntArray(n)
        colors.forEachIndexed {
            v, c -> inverse[c] = v
        }
        return buildString {
            for (i in 0 until n) for (j in i+1 until n) append(if (has(inverse[i], inverse[j])) '1' else '0')
        }
    }
    fun canonical(): Canonical {
        val result = Canonical()
        fun visit(colors: List<Int>) {
            result.nodes++
            val k = colorCount(colors)
            if (k == n) {
                result.leaves++
                val text = leafString(colors)
                if (result.winners.isEmpty() || text > result.text) {
                    result.text = text
                    result.label = colors
                    result.winners.clear()
                    result.winners.add(colors)
                }
                else if (text == result.text) result.winners.add(colors)
                return
            }
            val cell = (0 until k).map {
                c -> colors.count {
                    it == c
                } to c
            }.filter {
                it.first > 1
            }.minWith(compareBy<Pair<Int, Int>> {
                it.first
            }.thenBy {
                it.second
            }).second
            for (v in 0 until n) if (colors[v] == cell) visit(refine(individualize(colors, v)).first)
        }
        visit(stable().first)
        return result
    }
    fun invariants(): Invariants {
        val seen = BooleanArray(n)
        val sizes = mutableListOf<Int>()
        val eccentricities = mutableListOf<Int>()
        var girth: Int? = null
        var bipartite = true
        for (start in 0 until n) {
            val distance = IntArray(n) {
                -1
            }
            val parent = IntArray(n) {
                n
            }
            val queue = ArrayDeque<Int>()
            distance[start] = 0
            queue.addLast(start)
            while (queue.isNotEmpty()) {
                val u = queue.removeFirst()
                for (v in 0 until n) if (has(u, v)) {
                    if (distance[v] < 0) {
                        distance[v] = distance[u]+1
                        parent[v] = u
                        queue.addLast(v)
                    }
                    else {
                        if (distance[u]%2 == distance[v]%2) bipartite = false
                        if (parent[u] != v && parent[v] != u) {
                            val length = distance[u]+distance[v]+1
                            girth = girth?.let {
                                minOf(it, length)
                            } ?: length
                        }
                    }
                }
            }
            if (!seen[start]) {
                sizes.add(distance.count {
                    it >= 0
                })
                for (v in 0 until n) if (distance[v] >= 0) seen[v] = true
            }
            eccentricities.add(distance.max())
        }
        var triangles = 0
        for (u in 0 until n) for (v in u+1 until n) for (w in v+1 until n) if (has(u,v) && has(v,w) && has(u,w)) triangles++
        return Invariants(degrees().sortedDescending(), triangles, sizes.sortedDescending(), girth, if (sizes.size == 1) eccentricities.max() else null, if (sizes.size == 1) eccentricities.min() else null, bipartite)
    }
    fun clique(): List<Int> {
        var best = emptyList<Int>()
        for (mask in 1 until (1 shl n)) {
            val vertices = (0 until n).filter {
                mask and (1 shl it) != 0
            }
            if (vertices.size < best.size) continue
            if (vertices.all {
                (mask xor (1 shl it)) and adjacent[it].inv() == 0
            } && (vertices.size > best.size || compareLists(vertices,best) < 0)) best = vertices
        }
        return best
    }
    fun coloring(): Pair<Int, List<Int>> {
        val colors = mutableListOf<Int>()
        fun find(limit: Int, used: Int): Boolean {
            val v = colors.size
            if (v == n) return true
            for (c in 0 until minOf(limit,used+1)) {
                if ((0 until v).any {
                    has(it,v) && colors[it] == c
                }) continue
                colors.add(c)
                if (find(limit,maxOf(used,c+1))) return true
                colors.removeAt(colors.lastIndex)
            }
            return false
        }
        for (limit in 1..n) {
            colors.clear()
            if (find(limit,0)) return limit to colors.toList()
        }
        error("no coloring")
    }
}
private class UnionFind(n: Int) {
    private val parent = IntArray(n) {
        it
    }
    fun root(v: Int): Int {
        if (parent[v] != v) parent[v] = root(parent[v])
        return parent[v]
    }
    fun join(u: Int, v: Int) {
        parent[root(u)] = root(v)
    }
    fun orbits() = parent.indices.groupBy {
        root(it)
    }.values.sortedBy {
        it[0]
    }
}
private fun graphName(s: String) = s.matches(Regex("[a-z][a-z0-9]{0,7}"))
private fun number(s: String): Int? = if (s.matches(Regex("0|[1-9][0-9]{0,2}"))) s.toInt() else null
private fun edge(s: String): Pair<Int, Int>? {
    val p = s.split('-')
    if (p.size != 2) return null
    return (number(p[0]) ?: return null) to (number(p[1]) ?: return null)
}
private class Lab {
    val registry = sortedMapOf<String, Graph>()
    fun command(w: List<String>): List<String> {
        val c = w[0]
        val a = w.drop(1)
        val count = a.size
        val defining = setOf("GRAPH","CYCLE","PATH","COMPLETE","BIPARTITE","STAR","WHEEL","PETERSEN","HYPERCUBE","CIRCULANT","GRID","COMPLEMENT","LINE","PRODUCT","UNION","RELABEL","INDUCED","CANONIZE")
        val known = setOf("DELETE","LIST","SHOW","INVARIANTS","REFINE","CANON","ISO","AUT","SUBISO","CLASSIFY")
        if (c !in defining && c !in known) fail("unknown command $c")
        val shape = when(c) {
            "GRAPH","RELABEL" -> count >= 2
            "CIRCULANT","INDUCED" -> count >= 3
            "REFINE" -> count >= 1
            "LIST" -> count == 0
            "PETERSEN","DELETE","SHOW","INVARIANTS","CANON","AUT","CLASSIFY" -> count == 1
            "BIPARTITE","GRID","PRODUCT","UNION" -> count == 3
            else -> count == 2
        }
        if (!shape) fail("bad arguments")
        val references = when(c) {
            "COMPLEMENT","LINE","RELABEL","INDUCED","CANONIZE" -> listOf(1)
            "PRODUCT","UNION" -> listOf(1,2)
            "ISO","SUBISO" -> listOf(0,1)
            "DELETE","SHOW","INVARIANTS","REFINE","CANON","AUT" -> listOf(0)
            else -> emptyList()
        }
        val numeric = when(c) {
            "GRAPH","CYCLE","PATH","COMPLETE","STAR","WHEEL","HYPERCUBE" -> listOf(1)
            "BIPARTITE","GRID" -> listOf(1,2)
            "CIRCULANT" -> (1 until count).toList()
            "RELABEL","INDUCED" -> (2 until count).toList()
            "REFINE" -> (1 until count).toList()
            "CLASSIFY" -> listOf(0)
            else -> emptyList()
        }
        for ((i,s) in a.withIndex()) if (!(if (i in numeric) number(s) != null else if (c == "GRAPH" && i >= 2) edge(s) != null else graphName(s))) fail("bad arguments")
        for (i in references) if (a[i] !in registry) fail("no graph ${a[i]}")
        fun num(i: Int) = number(a[i])!!
        fun graph(i: Int) = registry.getValue(a[i])
        fun bounded(n: Int, minimum: Int = 1): Int {
            if (n < minimum) fail("bad value")
            if (n > 16) fail("too large")
            return n
        }
        if (c in defining) {
            val g = when(c) {
                "GRAPH","CYCLE","PATH","COMPLETE","CIRCULANT" -> Graph(bounded(num(1),if (c == "CYCLE" || c == "CIRCULANT") 3 else 1))
                "STAR","WHEEL" -> {
                    if (num(1) < if (c == "STAR") 1 else 3) fail("bad value")
                    Graph(bounded(num(1)+1))
                }
                "BIPARTITE","GRID" -> {
                    if (num(1) == 0 || num(2) == 0) fail("bad value")
                    Graph(bounded(if (c == "GRID") num(1)*num(2) else num(1)+num(2)))
                }
                "HYPERCUBE" -> {
                    if (num(1) == 0) fail("bad value")
                    if (num(1) > 4) fail("too large")
                    Graph(1 shl num(1))
                }
                "PETERSEN" -> Graph(10)
                "COMPLEMENT","RELABEL","CANONIZE" -> Graph(graph(1).n)
                "LINE" -> {
                    val m = graph(1).edges().size
                    if (m == 0) fail("no edges")
                    Graph(bounded(m))
                }
                "INDUCED" -> Graph(count-2)
                "PRODUCT" -> Graph(bounded(graph(1).n*graph(2).n))
                "UNION" -> Graph(bounded(graph(1).n+graph(2).n))
                else -> error("unknown definition")
            }
            val n = g.n
            when(c) {
                "GRAPH" -> for (s in a.drop(2)) {
                    val (u,v) = edge(s)!!
                    if (u >= n || v >= n || u == v) fail("bad edge $s")
                    if (g.has(u,v)) fail("duplicate edge $s")
                    g.join(u,v)
                }
                "CYCLE","PATH" -> {
                    for (i in 0 until n-1) g.join(i,i+1)
                    if (c == "CYCLE") g.join(n-1,0)
                }
                "COMPLETE" -> for (i in 0 until n) for (j in i+1 until n) g.join(i,j)
                "BIPARTITE" -> for (i in 0 until num(1)) for (j in num(1) until n) g.join(i,j)
                "STAR","WHEEL" -> {
                    for (i in 1 until n) g.join(0,i)
                    if (c == "WHEEL") {
                        for (i in 1 until n-1) g.join(i,i+1)
                        g.join(n-1,1)
                    }
                }
                "PETERSEN" -> for (i in 0..4) {
                    g.join(i,(i+1)%5)
                    g.join(i,i+5)
                    g.join(i+5,5+(i+2)%5)
                }
                "HYPERCUBE" -> for (u in 0 until n) for (bit in 0 until num(1)) g.join(u,u xor (1 shl bit))
                "CIRCULANT" -> {
                    val jumps = (2 until count).map(::num)
                    if (jumps.any {
                        it == 0 || it*2 > n
                    } || jumps.zipWithNext().any {
                        it.first >= it.second
                    }) fail("bad value")
                    for (u in 0 until n) for (j in jumps) g.join(u,(u+j)%n)
                }
                "GRID" -> for (x in 0 until num(1)) for (y in 0 until num(2)) {
                    val u = x*num(2)+y
                    if (y+1 < num(2)) g.join(u,u+1)
                    if (x+1 < num(1)) g.join(u,u+num(2))
                }
                "COMPLEMENT" -> {
                    val old = graph(1)
                    for (u in 0 until n) for (v in u+1 until n) if (!old.has(u,v)) g.join(u,v)
                }
                "LINE" -> {
                    val edges = graph(1).edges()
                    for (i in 0 until n) for (j in i+1 until n) if (edges[i].first == edges[j].first || edges[i].first == edges[j].second || edges[i].second == edges[j].first || edges[i].second == edges[j].second) g.join(i,j)
                }
                "PRODUCT" -> {
                    val x = graph(1)
                    val y = graph(2)
                    for (u in 0 until x.n) for ((v,w) in y.edges()) g.join(u*y.n+v,u*y.n+w)
                    for ((u,v) in x.edges()) for (w in 0 until y.n) g.join(u*y.n+w,v*y.n+w)
                }
                "UNION" -> {
                    val x = graph(1)
                    for ((u,v) in x.edges()) g.join(u,v)
                    for ((u,v) in graph(2).edges()) g.join(u+x.n,v+x.n)
                }
                "RELABEL","CANONIZE" -> {
                    val old = graph(1)
                    val p = if (c == "CANONIZE") old.canonical().label else (2 until count).map(::num)
                    if (p.size != n || p.toSet() != (0 until n).toSet()) fail("bad permutation")
                    for ((u,v) in old.edges()) g.join(p[u],p[v])
                }
                "INDUCED" -> {
                    val old = graph(1)
                    val p = (2 until count).map(::num)
                    if (p.any {
                        it >= old.n
                    } || p.toSet().size != p.size) fail("bad vertices")
                    for (u in 0 until n) for (v in u+1 until n) if (old.has(p[u],p[v])) g.join(u,v)
                }
            }
            val output = "${if (a[0] in registry) "redefined" else "defined"} ${a[0]} n $n m ${g.edges().size}"
            registry[a[0]] = g
            return listOf(output)
        }
        if (c == "LIST") return listOf("graphs ${registry.size}")+registry.map {
            (name,g) -> "$name n ${g.n} m ${g.edges().size}"
        }
        if (c == "DELETE") {
            registry.remove(a[0])
            return listOf("deleted ${a[0]}")
        }
        if (c == "CLASSIFY") {
            val n = num(0)
            if (n == 0) fail("bad value")
            if (n > 5) fail("too large")
            val pairs = n*(n-1)/2
            val classes = List(pairs+1) {
                sortedSetOf<String>()
            }
            for (mask in 0 until (1 shl pairs)) {
                val g = Graph(n)
                var bit = 0
                for (u in 0 until n) for (v in u+1 until n) {
                    if (mask and (1 shl bit) != 0) g.join(u,v)
                    bit++
                }
                classes[mask.countOneBits()].add(g.canonical().text)
            }
            return listOf("classify $n total ${classes.sumOf { it.size }}")+classes.mapIndexed {
                m,s -> "edges $m count ${s.size} ${s.joinToString(" ") { it.ifEmpty { "-" } }}"
            }
        }
        val g = graph(0)
        val n = g.n
        when(c) {
            "SHOW" -> return listOf("graph ${a[0]} n $n m ${g.edges().size}")+(0 until n).map {
                u -> "$u:"+(0 until n).filter {
                    g.has(u,it)
                }.joinToString("") {
                    " $it"
                }
            }
            "INVARIANTS" -> {
                val x = g.invariants()
                val out = mutableListOf("invariants ${a[0]}","degrees ${numbers(x.degrees)}","edges ${g.edges().size} triangles ${x.triangles}","components ${x.sizes.size} sizes ${numbers(x.sizes)}","girth ${shown(x.girth,"none")} diameter ${shown(x.diameter,"INF")} radius ${shown(x.radius,"INF")}","bipartite ${yes(x.bipartite)}")
                if (n > 12) out.addAll(listOf("clique -","chromatic -")) else {
                    val clique = g.clique()
                    val (chi,colors) = g.coloring()
                    out.add("clique ${clique.size} ${numbers(clique)}")
                    out.add("chromatic $chi ${numbers(colors)}")
                }
                return out
            }
            "REFINE" -> {
                val vertices = (1 until count).map(::num)
                if (vertices.any {
                    it >= n
                }) fail("bad vertices")
                var (colors,rounds) = g.stable()
                for (v in vertices) {
                    if (colors.count {
                        it == colors[v]
                    } == 1) fail("singleton $v")
                    val (next,r) = g.refine(individualize(colors,v))
                    colors = next
                    rounds += r
                }
                val k = colorCount(colors)
                return listOf("refine ${a[0]} rounds $rounds cells $k")+(0 until k).map {
                    cell -> "$cell: ${numbers((0 until n).filter { colors[it] == cell })}"
                }
            }
            "CANON" -> {
                val x = g.canonical()
                return listOf("canon ${a[0]} nodes ${x.nodes} leaves ${x.leaves}","labels ${numbers(x.label)}","string ${x.text.ifEmpty { "-" }}")
            }
            "ISO" -> {
                val h = graph(1)
                val x = g.invariants()
                val y = h.invariants()
                val difference = when {
                    n != h.n -> "vertices $n ${h.n}"
                    g.edges().size != h.edges().size -> "edges ${g.edges().size} ${h.edges().size}"
                    x.degrees != y.degrees -> "degrees"
                    x.triangles != y.triangles -> "triangles ${x.triangles} ${y.triangles}"
                    x.sizes.size != y.sizes.size -> "components ${x.sizes.size} ${y.sizes.size}"
                    x.girth != y.girth -> "girth ${shown(x.girth,"none")} ${shown(y.girth,"none")}"
                    x.diameter != y.diameter -> "diameter ${shown(x.diameter,"INF")} ${shown(y.diameter,"INF")}"
                    x.bipartite != y.bipartite -> "bipartite ${yes(x.bipartite)} ${yes(y.bipartite)}"
                    else -> null
                }
                if (difference != null) return listOf("not isomorphic $difference")
                val (p,r) = g.stable()
                val (q,s) = h.stable()
                fun sizes(colors: List<Int>) = (0 until colorCount(colors)).map {
                    c -> colors.count {
                        it == c
                    }
                }
                if (r != s || sizes(p) != sizes(q)) return listOf("not isomorphic refinement")
                val ca = g.canonical()
                val cb = h.canonical()
                if (ca.text != cb.text) return listOf("not isomorphic canonical")
                return listOf("isomorphic","mapping ${numbers(ca.label.map { cb.label.indexOf(it) })}")
            }
            "AUT" -> {
                val result = g.canonical()
                val edges = g.edges()
                val vertices = UnionFind(n)
                val edgeSets = UnionFind(edges.size)
                val inverse = IntArray(n)
                result.label.forEachIndexed {
                    v,c -> inverse[c] = v
                }
                for (label in result.winners) {
                    val map = label.map {
                        inverse[it]
                    }
                    for (v in 0 until n) vertices.join(v,map[v])
                    for ((i,e) in edges.withIndex()) {
                        val u = map[e.first]
                        val v = map[e.second]
                        edgeSets.join(i,edges.indexOf(minOf(u,v) to maxOf(u,v)))
                    }
                }
                val vo = vertices.orbits()
                val eo = edgeSets.orbits()
                val out = mutableListOf("aut ${a[0]} order ${result.winners.size}","vertex orbits ${vo.size}")
                out.addAll(vo.map {
                    "orbit ${numbers(it)}"
                })
                out.add("edge orbits ${eo.size}")
                out.addAll(eo.map {
                    orbit -> "orbit ${orbit.joinToString(" ") { "${edges[it].first}-${edges[it].second}" }}"
                })
                out.add("transitive vertex ${yes(vo.size == 1)} edge ${yes(eo.size == 1)}")
                return out
            }
            "SUBISO" -> {
                val target = graph(1)
                val mapping = mutableListOf<Int>()
                var embeddings = 0
                var inducedCount = 0
                val first = mutableListOf<Pair<List<Int>,Boolean>>()
                fun enumerate(used: Int, induced: Boolean) {
                    val v = mapping.size
                    if (v == n) {
                        embeddings++
                        if (induced) inducedCount++
                        if (first.size < 5) first.add(mapping.toList() to induced)
                        return
                    }
                    for (w in 0 until target.n) {
                        if (used and (1 shl w) != 0 || (0 until v).any {
                            g.has(it,v) && !target.has(mapping[it],w)
                        }) continue
                        val next = induced && (0 until v).all {
                            g.has(it,v) == target.has(mapping[it],w)
                        }
                        mapping.add(w)
                        enumerate(used or (1 shl w),next)
                        mapping.removeAt(mapping.lastIndex)
                    }
                }
                if (n <= target.n) enumerate(0,true)
                val order = g.canonical().winners.size
                return listOf("subiso ${a[0]} ${a[1]} embeddings $embeddings induced $inducedCount","copies ${embeddings/order} induced ${inducedCount/order}")+first.map {
                    (map,induced) -> "embedding ${numbers(map)}${if (induced) " induced" else ""}"
                }
            }
        }
        error("unknown command")
    }
}
fun main() {
    val lab = Lab()
    repeat(readLine()!!.toInt()) {
        try {
            lab.command(readLine()!!.split(' ')).forEach(::println)
        } catch (p: Problem) {
            println(p.text)
        }
    }
}
