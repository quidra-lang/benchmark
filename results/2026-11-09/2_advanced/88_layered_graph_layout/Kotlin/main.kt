import java.io.File
import kotlin.math.abs
typealias Order = List<List<Int>>
fun copyOrder(order: Order): MutableList<MutableList<Int>> = order.map {
    it.toMutableList()
}.toMutableList()
data class Model(val layer: List<Int>, val width: List<Int>, val chains: List<List<Int>>, val gaps: List<List<Segment>>,
val upper: List<List<Int>>, val lower: List<List<Int>>, val initial: Order)
fun reachability(n: Int, edges: List<Edge>): Array<BooleanArray> {
    val reachable = Array(n) {
        BooleanArray(n)
    }
    for (i in 0 until n) reachable[i][i] = true
    for ((a, b) in edges) reachable[a][b] = true
    for (k in 0 until n) for (i in 0 until n) for (j in 0 until n) reachable[i][j] = reachable[i][j] || reachable[i][k] && reachable[k][j]
    return reachable
}
data class Analysis(val sources: Int, val sinks: Int, val isolated: Int, val components: Int, val scc: List<List<Int>>)
fun analysis(graph: Graph): Analysis {
    val n = graph.nodes.size
    val incoming = IntArray(n)
    val outgoing = IntArray(n)
    for ((a, b) in graph.edges) {
        outgoing[a]++; incoming[b]++
    }
    val sources = (0 until n).count {
        incoming[it] == 0 && outgoing[it] > 0
    }
    val sinks = (0 until n).count {
        outgoing[it] == 0 && incoming[it] > 0
    }
    val isolated = (0 until n).count {
        outgoing[it] == 0 && incoming[it] == 0
    }
    val visited = mutableSetOf<Int>()
    var components = 0
    for (v in 0 until n) if (v !in visited) {
        components++
        val stack = mutableListOf(v)
        while (stack.isNotEmpty()) {
            val a = stack.removeAt(stack.lastIndex)
            if (visited.add(a)) {
                for ((u, w) in graph.edges) {
                    if (u == a) stack.add(w); if (w == a) stack.add(u)
                }
            }
        }
    }
    val connected = reachability(n, graph.edges)
    val remaining = (0 until n).toMutableSet()
    val scc = mutableListOf<List<Int>>()
    while (remaining.isNotEmpty()) {
        val v = remaining.minOrNull()!!
        val group = remaining.filter {
            connected[v][it] && connected[it][v]
        }.sorted()
        remaining.removeAll(group.toSet())
        if (group.size > 1) scc.add(group)
    }
    return Analysis(sources, sinks, isolated, components, scc)
}
fun buildModel(graph: Graph, heights: IntArray, dag: List<Edge>, removed: BooleanArray): Model {
    val n = graph.nodes.size
    val h = heights.maxOrNull()!!
    val raw = heights.map {
        h - it
    }
    val used = raw.toMutableSet()
    for ((i, edge) in dag.withIndex()) if (!removed[i]) used.addAll(raw[edge.a] + 1 until raw[edge.b])
    val numbering = used.sorted().withIndex().associate {
        it.value to it.index
    }
    val layer = raw.map {
        numbering.getValue(it)
    }.toMutableList()
    val width = graph.nodes.map {
        it.label.length + 2
    }.toMutableList()
    val chains = List(graph.edges.size) {
        mutableListOf<Int>()
    }
    for ((i, edge) in dag.withIndex()) if (!removed[i]) {
        val (a, b) = edge
        chains[i].add(a)
        for (l in layer[a] + 1 until layer[b]) {
            chains[i].add(layer.size); layer.add(l); width.add(1)
        }
        chains[i].add(b)
    }
    val gaps = List(maxOf(0, used.size - 1)) {
        mutableListOf<Segment>()
    }
    val upper = List(layer.size) {
        mutableListOf<Int>()
    }
    val lower = List(layer.size) {
        mutableListOf<Int>()
    }
    for ((i, chain) in chains.withIndex()) for (j in 1 until chain.size) {
        val p = chain[j - 1]
        val q = chain[j]
        gaps[layer[p]].add(Segment(p, q, i)); upper[q].add(p); lower[p].add(q)
    }
    val initial = List(used.size) {
        mutableListOf<Int>()
    }
    val visited = BooleanArray(layer.size)
    fun visit(v: Int) {
        if (visited[v]) return
        visited[v] = true; initial[layer[v]].add(v)
        for (w in lower[v]) visit(w)
    }
    for (v in 0 until n) visit(v)
    return Model(layer, width, chains, gaps, upper, lower, initial)
}
data class Reduction(val order: Order, val records: List<String>, val csv: List<String>, val initial: Int,
val swept: Int, val run: Int, val sweep: Int)
fun reduceCrossings(graph: Graph, model: Model): Reduction {
    val n = model.layer.size
    var random = graph.settings.integer("seed").toLong()
    val records = mutableListOf<String>()
    val csv = mutableListOf<String>()
    var adopted = copyOrder(model.initial)
    var bestCount = Int.MAX_VALUE
    var bestRun = 0
    var bestSweep = 0
    var initial = 0
    for (run in 0..graph.settings.integer("restarts")) {
        val order = copyOrder(model.initial)
        if (run > 0) {
            for (row in order) for (j in row.lastIndex downTo 1) {
                random = 48271L * random % 2147483647L
                val k = (random % (j + 1)).toInt()
                val saved = row[j]; row[j] = row[k]; row[k] = saved
            }
        }
        val count = Crossing.total(model.gaps, order, n)
        if (run == 0) initial = count
        var runCount = count
        var runSweep = 0
        var runOrder = copyOrder(order)
        val history = mutableListOf<Order>(copyOrder(order))
        val counts = mutableListOf(count)
        records.add("sweep $run 0 initial crossings $count")
        csv.add("${graph.name},$run,0,$count")
        for (sweep in 1..graph.settings.integer("sweeps")) {
            val last = sweep - 1
            if (counts[last] == 0 || last >= 2 && history[last] == history[last - 2]) break
            val old = Crossing.positions(order, n)
            val layers = if (sweep % 2 == 1) (1 until order.size).toList() else (order.size - 2 downTo 0).toList()
            val reference = if (sweep % 2 == 1) model.upper else model.lower
            for (i in layers) {
                val positions = Crossing.positions(order, n)
                fun key(v: Int): Pair<Int, Int> {
                    val values = reference[v].map {
                        positions[it]
                    }.sorted()
                    return if (graph.settings.text("heuristic") == "median") Pair(values[(values.size - 1) / 2] + values[values.size / 2], 1) else Pair(values.sum(), values.size)
                }
                val moving = order[i].filter {
                    reference[it].isNotEmpty()
                }.sortedWith(Comparator {
                    a, b ->
                    val x = key(a)
                    val y = key(b)
                    val comparison = (x.first * y.second).compareTo(y.first * x.second)
                    if (comparison == 0) positions[a].compareTo(positions[b]) else comparison
                })
                var next = 0
                for (j in order[i].indices) if (reference[order[i][j]].isNotEmpty()) order[i][j] = moving[next++]
            }
            val positions = Crossing.positions(order, n)
            val moved = (0 until n).count {
                positions[it] != old[it]
            }
            var swaps = 0
            while (true) {
                var changed = false
                for (i in order.indices) for (j in 0 until order[i].size - 1) {
                    val v = order[i][j]
                    val w = order[i][j + 1]
                    if (Crossing.adjacent(v, w, model.upper, model.lower, positions) > Crossing.adjacent(w, v, model.upper, model.lower, positions)) {
                        order[i][j] = w; order[i][j + 1] = v; positions[v] = j + 1; positions[w] = j; swaps++; changed = true
                    }
                }
                if (!changed) break
            }
            val currentCount = Crossing.total(model.gaps, order, n)
            history.add(copyOrder(order)); counts.add(currentCount)
            records.add("sweep $run $sweep ${if (sweep % 2 == 1) "down" else "up"} moved $moved swaps $swaps crossings $currentCount")
            csv.add("${graph.name},$run,$sweep,$currentCount")
            if (currentCount < runCount) {
                runCount = currentCount; runSweep = sweep; runOrder = copyOrder(order)
            }
        }
        if (runCount < bestCount) {
            bestCount = runCount; bestRun = run; bestSweep = runSweep; adopted = runOrder
        }
    }
    records.add("best run $bestRun sweep $bestSweep crossings $bestCount")
    if (graph.settings.on("sifting")) {
        var round = 0
        while (true) {
            round++
            var moves = 0
            for (v in 0 until n) {
                val i = model.layer[v]
                val old = adopted[i].indexOf(v)
                val base = adopted[i].toMutableList()
                base.removeAt(old)
                val costs = mutableListOf<Int>()
                for (p in 0..base.size) {
                    val row = base.toMutableList(); row.add(p, v); adopted[i] = row
                    costs.add(Crossing.total(model.gaps, adopted, n))
                }
                val minimum = costs.minOrNull()!!
                val position = if (costs[old] == minimum) old else costs.indexOf(minimum)
                base.add(position, v); adopted[i] = base
                if (position != old) moves++
            }
            records.add("sift $round moves $moves crossings ${Crossing.total(model.gaps, adopted, n)}")
            if (moves == 0) break
        }
    }
    return Reduction(adopted, records, csv, initial, bestCount, bestRun, bestSweep)
}
data class Bus(val lo: Int, val hi: Int, val side: Int, val x: Int, val members: List<Int>)
data class Geometry(val tracks: List<Int>, val gaps: List<Int>, val offsets: List<List<Int?>>, val thickness: List<Int>,
val starts: IntArray, val main: Int, val secondary: Int)
fun geometry(graph: Graph, model: Model, order: Order, coordinates: Coordinates): Geometry {
    val x = coordinates.x
    val tracks = mutableListOf<Int>()
    val gaps = mutableListOf<Int>()
    val offsets = mutableListOf<List<Int?>>()
    for (segments in model.gaps) {
        val counts = segments.filter {
            x[it.p] != x[it.q]
        }.groupingBy {
            it.p
        }.eachCount()
        val groups = segments.indices.filter {
            x[segments[it].p] != x[segments[it].q]
        }.groupBy {
            val segment = segments[it]
            if (counts.getValue(segment.p) >= 2) VertexPair(0, segment.p) else VertexPair(1, segment.q)
        }
        val buses = groups.map {
            (key, members) ->
            Bus(members.minOf {
                minOf(x[segments[it].p], x[segments[it].q])
            }, members.maxOf {
                maxOf(x[segments[it].p], x[segments[it].q])
            }, key.a, x[key.b], members)
        }.sortedWith(compareBy<Bus> {
            it.lo
        }.thenBy {
            it.hi
        }.thenBy {
            it.side
        }.thenBy {
            it.x
        })
        val ends = mutableListOf<Int>()
        val assignments = MutableList<Int?>(segments.size) {
            null
        }
        for (bus in buses) {
            var track = ends.indexOfFirst {
                it + 1 < bus.lo
            }
            if (track < 0) {
                track = ends.size; ends.add(bus.hi)
            } else ends[track] = bus.hi
            for (k in bus.members) assignments[k] = track + 1
        }
        val gap = maxOf(graph.settings.integer("layer_gap"), ends.size + 2)
        tracks.add(ends.size); gaps.add(gap); offsets.add(assignments.map {
            it?.plus((gap - 2 - ends.size) / 2)
        })
    }
    val vertical = graph.settings.text("direction") in listOf("TB", "BT")
    val thickness = order.map {
        row -> if (vertical) 1 else row.maxOf {
            model.width[it]
        }
    }
    val starts = IntArray(order.size)
    for (i in 1 until order.size) starts[i] = starts[i - 1] + thickness[i - 1] + gaps[i - 1]
    return Geometry(tracks, gaps, offsets, thickness, starts, starts.last() + thickness.last(), model.layer.indices.maxOf {
        x[it] + coordinates.right[it]
    } + 1)
}
fun shortestPath(graph: Graph, removed: BooleanArray): List<Int>? {
    val endpoints = graph.path ?: return null
    val (start, goal) = endpoints
    val parent = IntArray(graph.nodes.size) {
        -1
    }
    val visited = BooleanArray(graph.nodes.size)
    val queue = ArrayDeque<Int>()
    visited[start] = true; queue.addLast(start)
    while (queue.isNotEmpty()) {
        val a = queue.removeFirst()
        val neighbors = graph.edges.indices.filter {
            !removed[it] && graph.edges[it].a == a
        }.map {
            graph.edges[it].b
        }.sorted()
        for (b in neighbors) if (!visited[b]) {
            visited[b] = true; parent[b] = a; queue.addLast(b)
        }
    }
    if (!visited[goal]) return null
    val path = mutableListOf(goal)
    var current = goal
    while (current != start) {
        current = parent[current]; path.add(current)
    }
    return path.reversed()
}
data class Drawing(val canvas: Canvas, val routes: List<List<Cell>>, val lengths: IntArray, val bends: IntArray)
fun draw(graph: Graph, model: Model, c: Coordinates, geo: Geometry, reversed: BooleanArray, removed: BooleanArray, path: List<Int>?): Drawing {
    val direction = graph.settings.text("direction")
    val vertical = direction in listOf("TB", "BT")
    val canvas = Canvas(geo.main, geo.secondary, direction)
    for (v in model.layer.indices) {
        val i = model.layer[v]
        if (v >= graph.nodes.size) {
            for (j in 0 until geo.thickness[i]) canvas.line(geo.starts[i] + j, c.x[v], true)
        } else if (!vertical && model.lower[v].isNotEmpty()) {
            for (j in model.width[v] until geo.thickness[i]) canvas.line(geo.starts[i] + j, c.x[v], true)
        }
    }
    for ((i, segments) in model.gaps.withIndex()) {
        val g0 = geo.starts[i] + geo.thickness[i]
        val gap = geo.gaps[i]
        for ((k, segment) in segments.withIndex()) {
            val p = c.x[segment.p]
            val q = c.x[segment.q]
            val offset = geo.offsets[i][k]
            if (offset != null) {
                for (j in 0 until offset) canvas.line(g0 + j, p, true)
                canvas.corner(g0 + offset, p); canvas.corner(g0 + offset, q)
                for (x in minOf(p, q) + 1 until maxOf(p, q)) canvas.line(g0 + offset, x, false)
                for (j in offset + 1 until gap) canvas.line(g0 + j, q, true)
            } else {
                for (j in 0 until gap) canvas.line(g0 + j, p, true)
            }
        }
    }
    val routes = MutableList<List<Cell>>(graph.edges.size) {
        emptyList()
    }
    val lengths = IntArray(graph.edges.size)
    val bends = IntArray(graph.edges.size)
    for ((e, chain) in model.chains.withIndex()) if (!removed[e]) {
        val a = chain[0]
        val b = chain.last()
        val upper = Pair(geo.starts[model.layer[a]] + if (vertical) 1 else model.width[a], c.x[a])
        val lower = Pair(geo.starts[model.layer[b]] - 1, c.x[b])
        val points = mutableListOf(upper)
        for (j in 1 until chain.size) {
            val p = chain[j - 1]
            val q = chain[j]
            val i = model.layer[p]
            val k = model.gaps[i].indexOfFirst {
                it.p == p && it.q == q
            }
            val offset = geo.offsets[i][k]
            if (offset != null) {
                val main = geo.starts[i] + geo.thickness[i] + offset
                points.add(Pair(main, c.x[p])); points.add(Pair(main, c.x[q])); bends[e] += 2
            }
        }
        points.add(lower)
        var mapped = points.map {
            canvas.map(it.first, it.second)
        }
        if (reversed[e]) {
            mapped = mapped.reversed(); canvas.arrow(upper.first, upper.second, true)
        } else canvas.arrow(lower.first, lower.second, false)
        lengths[e] = 1 + (1 until mapped.size).sumOf {
            abs(mapped[it - 1].row - mapped[it].row) + abs(mapped[it - 1].column - mapped[it].column)
        }
        routes[e] = mapped
    }
    val onPath = path?.toSet() ?: emptySet()
    if (path != null) {
        for (j in 1 until path.size) {
            val e = graph.edges.indexOfFirst {
                it.a == path[j - 1] && it.b == path[j]
            }
            for (k in 1 until routes[e].size) {
                val a = routes[e][k - 1]
                val b = routes[e][k]
                if (a.row == b.row) {
                    for (column in minOf(a.column, b.column)..maxOf(a.column, b.column)) canvas.highlight(a.row, column)
                } else {
                    for (row in minOf(a.row, b.row)..maxOf(a.row, b.row)) canvas.highlight(row, a.column)
                }
            }
        }
    }
    for (v in graph.nodes.indices) {
        val i = model.layer[v]
        val label = (if (v in onPath) "{" else "[") + graph.nodes[v].label + if (v in onPath) "}" else "]"
        val cell = if (vertical) canvas.map(geo.starts[i], c.x[v] - c.left[v]) else if (direction == "LR") Cell(c.x[v], geo.starts[i]) else Cell(c.x[v], geo.main - geo.starts[i] - model.width[v])
        canvas.label(cell.row, cell.column, label)
    }
    return Drawing(canvas, routes, lengths, bends)
}
data class Processed(val layout: List<String>, val stats: List<String>, val csv: List<String>, val drawings: List<String>, val totals: IntArray)
fun process(graph: Graph): Processed {
    val n = graph.nodes.size
    fun id(v: Int): String = graph.nodes[v].id.toString()
    fun edgeName(e: Int): String = id(graph.edges[e].a) + "->" + id(graph.edges[e].b)
    val analysis = analysis(graph)
    val sequence = AcyclicLayering.sequence(n, graph.edges)
    val position = IntArray(n)
    for ((i, v) in sequence.withIndex()) position[v] = i
    val reversed = BooleanArray(graph.edges.size) {
        position[graph.edges[it].a] > position[graph.edges[it].b]
    }
    val dag = graph.edges.mapIndexed {
        i, edge -> if (reversed[i]) Edge(edge.b, edge.a) else edge
    }
    val reachable = reachability(n, dag)
    val removed = BooleanArray(dag.size) {
        i -> val edge = dag[i]; graph.settings.on("reduce") && !reversed[i] && dag.any {
            it.a == edge.a && it.b != edge.b && reachable[it.b][edge.b]
        }
    }
    val drawn = dag.filterIndexed {
        i, _ -> !removed[i]
    }
    val layering = AcyclicLayering.assign(n, drawn, graph.settings.text("layering") == "coffman", graph.settings.integer("width"), graph.settings.on("promotion"))
    val model = buildModel(graph, layering.heights, dag, removed)
    val reduced = reduceCrossings(graph, model)
    val c = Coordinates.assign(n, reduced.order, model.layer, model.upper, model.lower, model.width, graph.settings.text("direction") in listOf("TB", "BT"), graph.settings.integer("node_sep"), graph.settings.integer("dummy_sep"))
    val geo = geometry(graph, model, reduced.order, c)
    val path = shortestPath(graph, removed)
    val drawing = draw(graph, model, c, geo, reversed, removed, path)
    val canvas = drawing.canvas
    val vertices = model.layer.size
    fun name(v: Int): String = if (v < n) id(v) else "d${v - n + 1}"
    val positions = Crossing.positions(reduced.order, vertices)
    val counts = model.gaps.mapIndexed {
        i, gap -> Crossing.count(gap, positions, reduced.order[i + 1].size)
    }
    val finalCount = counts.sum()
    val brute = model.gaps.sumOf {
        Crossing.brute(it, positions)
    }
    val edgeCrossings = IntArray(graph.edges.size)
    for (gap in model.gaps) for (i in gap.indices) for (j in i + 1 until gap.size) if (Crossing.crosses(gap[i], gap[j], positions)) {
        edgeCrossings[gap[i].edge]++; edgeCrossings[gap[j].edge]++
    }
    val settings = Settings.names.zip(graph.settings.values).joinToString(" ") {
        "${it.first}=${it.second}"
    }
    val layout = mutableListOf("graph ${graph.name}", "settings $settings", "acyclic " + sequence.joinToString(" ") {
        id(it)
    })
    if (graph.settings.text("layering") == "coffman") layout.add("labels " + (0 until n).joinToString(" ") {
        "${id(it)}:${layering.labels[it]}"
    })
    for ((round, v, diff) in layering.promotions) layout.add("promote $round ${id(v)} $diff")
    layout.addAll(reduced.records)
    for ((i, row) in reduced.order.withIndex()) {
        val start = geo.starts[i]
        val end = start + geo.thickness[i] - 1
        val backwards = graph.settings.text("direction") in listOf("BT", "RL")
        val bandLo = if (backwards) geo.main - 1 - end else start
        val bandHi = if (backwards) geo.main - 1 - start else end
        val lo = row.minOf {
            c.x[it] - c.left[it]
        }
        val hi = row.maxOf {
            c.x[it] + c.right[it]
        }
        layout.add("layer $i band $bandLo $bandHi extent $lo $hi : " + row.joinToString(" ") {
            "${name(it)}@${c.x[it]}"
        })
    }
    for (i in model.gaps.indices) layout.add("between $i ${i + 1} segments ${model.gaps[i].size} crossings ${counts[i]} tracks ${geo.tracks[i]} gap ${geo.gaps[i]}")
    val variants = listOf("ul", "ur", "dl", "dr")
    layout.add("bk conflicts ${c.conflicts} " + (0..3).joinToString(" ") {
        "${variants[it]}=${c.blocks[it]}/${c.widths[it]}"
    } + " smallest ${variants[c.smallest]}")
    for (row in reduced.order) for (v in row) layout.add("vertex ${name(v)} layer ${model.layer[v]} pos ${positions[v]} ul ${c.aligned[0][v]} ur ${c.aligned[1][v]} dl ${c.aligned[2][v]} dr ${c.aligned[3][v]} x ${c.x[v]}")
    for (e in graph.edges.indices) {
        val (a, b) = graph.edges[e]
        if (removed[e]) layout.add("edge ${id(a)} ${id(b)} transitive")
        else {
            val chain = if (reversed[e]) model.chains[e].reversed() else model.chains[e]
            val pathText = chain.joinToString(" ") {
                c.x[it].toString()
            }
            val route = drawing.routes[e].joinToString(" ") {
                "${it.row},${it.column}"
            }
            layout.add("edge ${id(a)} ${id(b)}${if (reversed[e]) " reversed" else ""} span ${chain.size - 1} crossings ${edgeCrossings[e]} bends ${drawing.bends[e]} path $pathText route $route")
        }
    }
    layout.add("end")
    val stats = mutableListOf("graph ${graph.name}", "nodes $n edges ${graph.edges.size} self_loops ${graph.loops} duplicates ${graph.duplicates}", "sources ${analysis.sources} sinks ${analysis.sinks} isolated ${analysis.isolated} components ${analysis.components}")
    for (component in analysis.scc) stats.add("scc " + component.joinToString(" ") {
        id(it)
    })
    for ((label, flags) in listOf(Pair("reversed", reversed), Pair("transitive", removed))) {
        val names = graph.edges.indices.filter {
            flags[it]
        }.map {
            edgeName(it)
        }
        stats.add("$label ${names.size}" + if (names.isEmpty()) "" else " " + names.joinToString(" "))
    }
    stats.add("layers ${reduced.order.size} max_nodes ${reduced.order.maxOf { row -> row.count { it < n } }} max_vertices ${reduced.order.maxOf { it.size }}")
    stats.add(if (graph.settings.on("promotion")) "promotion rounds ${layering.rounds} accepted ${layering.promotions.size} dummies_before ${layering.before}" else "promotion off")
    val spans = model.chains.filter {
        it.isNotEmpty()
    }.groupingBy {
        it.size - 1
    }.eachCount().toSortedMap()
    val spanTotal = model.chains.filter {
        it.isNotEmpty()
    }.sumOf {
        it.size - 1
    }
    stats.add("dummies ${vertices - n} span_total $spanTotal span_max ${spans.keys.maxOrNull() ?: 0}")
    stats.add("spans " + if (spans.isEmpty()) "none" else spans.entries.joinToString(" ") {
        "${it.key}:${it.value}"
    })
    val long = model.chains.filter {
        it.size >= 3
    }
    val vertical = long.count {
        chain -> chain.drop(1).dropLast(1).all {
            c.x[it] == c.x[chain[1]]
        }
    }
    stats.add("long_edges ${long.size} vertical $vertical")
    stats.add("crossings initial ${reduced.initial} swept ${reduced.swept} best_run ${reduced.run} best_sweep ${reduced.sweep} final $finalCount brute $brute")
    val segments = model.gaps.flatten()
    val straight = segments.count {
        c.x[it.p] == c.x[it.q]
    }
    val offset = segments.sumOf {
        abs(c.x[it.p] - c.x[it.q])
    }
    stats.add("segments ${segments.size} straight $straight bent ${segments.size - straight} offset $offset")
    val longest = graph.edges.indices.filter {
        !removed[it]
    }.minWithOrNull(compareByDescending<Int> {
        drawing.lengths[it]
    }.thenBy {
        it
    })
    stats.add("routes length ${drawing.lengths.sum()} bends ${drawing.bends.sum()}" + if (longest == null) "" else " longest ${edgeName(longest)} ${drawing.lengths[longest]}")
    stats.add("canvas width ${canvas.columns} height ${canvas.rows} crossing_cells ${canvas.crossings()}")
    graph.path?.let {
        (a, b) -> stats.add(if (path == null) "path ${id(a)} ${id(b)} none" else "path ${id(a)} ${id(b)} hops ${path.size - 1} : " + path.joinToString(" ") {
            id(it)
        })
    }
    stats.add("end")
    return Processed(layout, stats, reduced.csv, listOf("graph ${graph.name} ${canvas.columns}x${canvas.rows}") + canvas.report(), intArrayOf(n, graph.edges.size, vertices - n, reduced.initial, finalCount))
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val graphs = GraphIO.read()
    val layout = mutableListOf<String>()
    val stats = mutableListOf<String>()
    val drawings = mutableListOf<String>()
    val csv = mutableListOf("graph,run,sweep,crossings")
    val totals = IntArray(5)
    var errors = 0
    for (graph in graphs) {
        if (drawings.isNotEmpty()) drawings.add("")
        val error = graph.error
        if (error != null) {
            errors++
            val block = listOf("graph ${graph.name}", "error ${error.first} line ${error.second}", "end")
            layout.addAll(block); stats.addAll(block); drawings.add("graph ${graph.name} error ${error.first}")
        } else {
            val output = process(graph)
            layout.addAll(output.layout); stats.addAll(output.stats); csv.addAll(output.csv); drawings.addAll(output.drawings)
            for (i in 0 until 5) totals[i] += output.totals[i]
        }
    }
    stats.add("summary graphs ${graphs.size} laid_out ${graphs.size - errors} errors $errors nodes ${totals[0]} edges ${totals[1]} dummies ${totals[2]} crossings_initial ${totals[3]} crossings_final ${totals[4]}")
    write("layout.txt", layout); write("stats.txt", stats); write("crossings.csv", csv); write("drawings.txt", drawings)
}
