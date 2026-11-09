import kotlin.math.abs

private val REGIONS = listOf("CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER")
private val QUANTITIES = listOf("in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic")
private const val PAGERANK_HEADER = "id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance"
private const val HOSTS_HEADER = "host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank"
private data class Ignored(val record: LinkRecord, val reason: String)
private fun range(count: Int) = (0 until count).toList()
private fun lists(count: Int) = List(count) { mutableListOf<Int>() }
private fun weightedLists(count: Int) = List(count) { mutableListOf<WeightedEdge>() }
private fun line(vararg parts: Any) = parts.joinToString(" ")
private fun blocks(groups: List<List<String>>): List<String> {
    val lines = mutableListOf<String>()
    for (group in groups) { if (lines.isNotEmpty()) lines.add(""); lines.addAll(group) }
    return lines
}
private fun <T> appendValues(prefix: String, values: List<T>) = if (values.isEmpty()) prefix else "$prefix ${values.joinToString(" ")}"
private fun total(values: DoubleArray, nodes: List<Int>): Double {
    var result = 0.0
    for (node in nodes) result += values[node]
    return result
}
private fun rankOrder(values: DoubleArray) = values.indices.sortedWith(compareByDescending<Int> { Report.scaled(values[it]) }.thenBy { it })
private fun positions(order: List<Int>): IntArray {
    val rank = IntArray(order.size)
    for ((position, node) in order.withIndex()) rank[node] = position + 1
    return rank
}
private fun top(values: DoubleArray, limit: Int) = rankOrder(values).filter { Report.scaled(values[it]) > 0 }.take(limit)
private fun rankedCounts(counts: IntArray, limit: Int) = counts.indices.filter { counts[it] > 0 }
    .sortedWith(compareByDescending<Int> { counts[it] }.thenBy { it }).take(limit)
private fun distribution(values: IntArray): Map<Int, Int> {
    val counts = sortedMapOf<Int, Int>()
    for (value in values) counts[value] = counts.getOrDefault(value, 0) + 1
    return counts
}
private fun scaled(values: DoubleArray) = LongArray(values.size) { Report.scaled(values[it]) }
private fun kendall(first: LongArray, second: LongArray): String {
    var concordant = 0
    var discordant = 0
    for (i in first.indices) for (j in i + 1 until first.size) {
        val dx = first[i] - first[j]
        val dy = second[i] - second[j]
        if (dx == 0L || dy == 0L) continue
        if ((dx > 0) == (dy > 0)) concordant++ else discordant++
    }
    return Report.fraction((concordant - discordant).toLong(), first.size.toLong() * (first.size - 1) / 2)
}
private fun pageRank(edges: List<List<WeightedEdge>>, teleport: List<Int>, damping: Double, settings: Settings) =
    PageRank.compute(edges, teleport, damping, settings.iterations, settings.tolerance)
private class Graph(val pages: List<Page>, edges: List<Edge>) {
    val count = pages.size
    val links = edges.sortedWith(compareBy<Edge> { it.source }.thenBy { it.target })
    val linkSet = edges.toSet()
    val successors = lists(count)
    val predecessors = lists(count)
    init {
        for (edge in links) { successors[edge.source].add(edge.target); predecessors[edge.target].add(edge.source) }
    }
    fun host(node: Int) = pages[node].host
    fun id(node: Int) = pages[node].id
    fun intra(edge: Edge) = host(edge.source) == host(edge.target)
    fun inter(edges: List<Edge>) = edges.filter { !intra(it) }
    fun dangling() = (0 until count).filter { successors[it].isEmpty() }
    fun ids(nodes: List<Int>) = nodes.map(::id)
    fun forward(): List<List<WeightedEdge>> {
        val edges = weightedLists(count)
        for (node in 0 until count) for (source in predecessors[node]) edges[node].add(WeightedEdge(source, 1))
        return edges
    }
    fun reverse(): List<List<WeightedEdge>> {
        val edges = weightedLists(count)
        for (node in 0 until count) for (target in successors[node]) edges[node].add(WeightedEdge(target, 1))
        return edges
    }
    fun describe(position: Int, node: Int, vararg values: Any): String =
        (listOf(position, id(node)) + values.toList() + listOf(host(node), pages[node].title)).joinToString(" ")
}
private fun kcores(neighbors: List<List<Int>>): IntArray {
    val count = neighbors.size
    var level = 0
    var left = count
    val degree = IntArray(count) { neighbors[it].size }
    val core = IntArray(count)
    val removed = BooleanArray(count)
    while (left > 0) {
        val candidate = (0 until count).firstOrNull { !removed[it] && degree[it] <= level }
        if (candidate == null) { level++; continue }
        removed[candidate] = true
        core[candidate] = level
        left--
        for (neighbor in neighbors[candidate]) if (!removed[neighbor]) degree[neighbor]--
    }
    return core
}
private class Undirected(graph: Graph) {
    val neighbors = lists(graph.count)
    val adjacent = Array(graph.count) { BooleanArray(graph.count) }
    val edgeCount: Int
    val closed: Int
    val possible: Int
    val eligible: Int
    val degeneracy: Int
    val weakCount: Int
    val weakLargest: Int
    val clustering: Double
    val kcore: IntArray
    init {
        for (edge in graph.links) { adjacent[edge.source][edge.target] = true; adjacent[edge.target][edge.source] = true }
        var degreeSum = 0
        var closedSum = 0
        var possibleSum = 0
        var eligibleCount = 0
        var localSum = 0.0
        for (node in 0 until graph.count) {
            val group = neighbors[node]
            for (other in 0 until graph.count) if (adjacent[node][other]) group.add(other)
            degreeSum += group.size
            if (group.size < 2) continue
            var closedHere = 0
            val possibleHere = group.size * (group.size - 1) / 2
            for (a in group.indices) for (b in a + 1 until group.size) if (adjacent[group[a]][group[b]]) closedHere++
            closedSum += closedHere
            possibleSum += possibleHere
            eligibleCount++
            localSum += closedHere.toDouble() / possibleHere
        }
        edgeCount = degreeSum / 2
        closed = closedSum
        possible = possibleSum
        eligible = eligibleCount
        clustering = localSum / eligible
        kcore = kcores(neighbors)
        degeneracy = kcore.max()
        val labels = Components.weak(neighbors)
        val sizes = IntArray(graph.count)
        for (label in labels) sizes[label]++
        weakCount = labels.max() + 1
        weakLargest = sizes.max()
    }
}
private fun longestPath(count: Int, edges: Set<Edge>): Int {
    val successors = lists(count)
    val pending = IntArray(count)
    val length = IntArray(count)
    for (edge in edges) { successors[edge.source].add(edge.target); pending[edge.target]++ }
    val ready = ArrayDeque<Int>()
    for (node in 0 until count) if (pending[node] == 0) ready.addLast(node)
    while (ready.isNotEmpty()) {
        val node = ready.removeLast()
        for (target in successors[node]) {
            length[target] = maxOf(length[target], length[node] + 1)
            pending[target]--
            if (pending[target] == 0) ready.addLast(target)
        }
    }
    return length.max()
}
private class ComponentTable(graph: Graph) {
    val groups = Components.strong(graph.successors).map { it.sorted() }.sortedBy { it[0] }
    val labels = IntArray(graph.count)
    val incoming = IntArray(groups.size)
    val outgoing = IntArray(groups.size)
    val edgeCount: Int
    val depth: Int
    val core: Int
    val singletons: Int
    init {
        for ((j, group) in groups.withIndex()) for (node in group) labels[node] = j
        val edges = mutableSetOf<Edge>()
        for (edge in graph.links) {
            val a = labels[edge.source]
            val b = labels[edge.target]
            if (a != b) { outgoing[a]++; incoming[b]++; edges.add(Edge(a, b)) }
        }
        edgeCount = edges.size
        depth = longestPath(groups.size, edges)
        var largest = 0
        var singles = 0
        for (j in groups.indices) {
            if (groups[j].size > groups[largest].size) largest = j
            if (groups[j].size == 1) singles++
        }
        core = largest
        singletons = singles
    }
}
private fun bowtie(graph: Graph, core: List<Int>): IntArray {
    val forward = Components.reachable(graph.successors, core)
    val backward = Components.reachable(graph.predecessors, core)
    val inCore = BooleanArray(graph.count)
    for (node in core) inCore[node] = true
    val regions = IntArray(graph.count) { 6 }
    for (node in 0 until graph.count) {
        if (inCore[node]) regions[node] = 0 else if (backward[node]) regions[node] = 1 else if (forward[node]) regions[node] = 2
    }
    val incoming = (0 until graph.count).filter { regions[it] == 1 }
    val outgoing = (0 until graph.count).filter { regions[it] == 2 }
    val fromIn = Components.reachable(graph.successors, incoming)
    val toOut = Components.reachable(graph.predecessors, outgoing)
    for (node in 0 until graph.count) {
        if (inCore[node] || backward[node] || forward[node]) continue
        if (fromIn[node] && toOut[node]) regions[node] = 3 else if (fromIn[node]) regions[node] = 4 else if (toOut[node]) regions[node] = 5
    }
    return regions
}
private class DistanceStats(graph: Graph) {
    var pairs = 0
    var total = 0
    var diameter = 0
    var source = 0
    var target = 0
    val histogram = IntArray(graph.count)
    val harmonic = DoubleArray(graph.count)
    init {
        for (from in 0 until graph.count) {
            val distance = Components.distances(graph.successors, listOf(from))
            for (to in 0 until graph.count) {
                val steps = distance[to]
                if (to == from || steps < 0) continue
                pairs++
                total += steps
                histogram[steps]++
                harmonic[to] += 1.0 / steps
                if (steps > diameter) { diameter = steps; source = from; target = to }
            }
        }
    }
    fun effective(): Int {
        var reached = 0
        for (steps in 1..diameter) { reached += histogram[steps]; if (10 * reached >= 9 * pairs) return steps }
        return diameter
    }
}
private class Scores(graph: Graph, settings: Settings, trusted: List<Int>, val harmonic: DoubleArray) {
    val damping = settings.damping
    val pagerankRun = pageRank(graph.forward(), range(graph.count), damping, settings)
    val cheirankRun = pageRank(graph.reverse(), range(graph.count), damping, settings)
    val trustrankRun = pageRank(graph.forward(), trusted, damping, settings)
    val pagerank = pagerankRun.values
    val cheirank = cheirankRun.values
    val trustrank = trustrankRun.values
    val order = rankOrder(pagerank)
    val rank = positions(order)
    val cheirankRank = positions(rankOrder(cheirank))
    val ratio = DoubleArray(graph.count) { trustrank[it] / pagerank[it] }
    val trustDistance = Components.distances(graph.successors, trusted)
    private val hits = Hits.compute(graph.count, range(graph.count), graph.inter(graph.links), settings.hitsIterations)
    val authority = hits.authority
    val hub = hits.hub
    fun contribution(graph: Graph, source: Int) = (damping * pagerank[source]) / graph.successors[source].size
    fun representative(nodes: List<Int>) = nodes.minBy { rank[it] }
}
private class Sweep(val damping: Double, graph: Graph, scores: Scores, settings: Settings) {
    val run = pageRank(graph.forward(), range(graph.count), damping, settings)
    val overlap: Int
    val footrule: Int
    val shift: Int
    val shiftRank: Int
    val correlation: String
    val top: List<Int>
    init {
        val order = rankOrder(run.values)
        val rank = positions(order)
        var overlapCount = 0
        var footruleSum = 0
        var largest = 0
        for (node in 0 until graph.count) {
            if (rank[node] <= settings.topK && scores.rank[node] <= settings.topK) overlapCount++
            footruleSum += abs(rank[node] - scores.rank[node])
            if (abs(rank[node] - scores.rank[node]) > abs(rank[largest] - scores.rank[largest])) largest = node
        }
        overlap = overlapCount
        footrule = footruleSum
        shift = largest
        shiftRank = rank[shift]
        correlation = kendall(scaled(scores.pagerank), scaled(run.values))
        top = order.take(settings.topK)
    }
}
private class Spam(graph: Graph, scores: Scores, settings: Settings) {
    val suspects = scores.order.take(settings.spamTop).filter { Report.scaled(scores.ratio[it], 4) / 10000.0 < settings.spamThreshold }
    val hosts = suspects.map(graph::host).distinct().sorted()
    val removed: Int
    val run: PageRankResult?
    val rank: IntArray?
    init {
        if (suspects.isEmpty()) { removed = 0; run = null; rank = null }
        else {
            val kept = graph.links.filter { !(graph.intra(it) && graph.host(it.source) in hosts) }
            removed = graph.links.size - kept.size
            val demoted = Graph(graph.pages, kept)
            val result = pageRank(demoted.forward(), range(graph.count), settings.damping, settings)
            run = result
            rank = positions(rankOrder(result.values))
        }
    }
}
private fun salsa(count: Int, links: List<Edge>): DoubleArray {
    val degree = IntArray(count)
    val targets = lists(count)
    val neighbors = lists(count)
    for (edge in links) { degree[edge.target]++; targets[edge.source].add(edge.target) }
    for (group in targets) for (i in 1 until group.size) {
        val a = group[i - 1]
        val b = group[i]
        neighbors[a].add(b)
        neighbors[b].add(a)
    }
    val labels = Components.weak(neighbors)
    val size = IntArray(count)
    val mass = IntArray(count)
    var side = 0
    for (node in 0 until count) if (degree[node] > 0) { side++; size[labels[node]]++; mass[labels[node]] += degree[node] }
    return DoubleArray(count) { node -> if (degree[node] > 0) (size[labels[node]] * degree[node]).toDouble() / (side * mass[labels[node]]) else 0.0 }
}
private fun cocitationCounts(graph: Graph, page: Int): IntArray {
    val counts = IntArray(graph.count)
    for (citing in graph.predecessors[page]) for (cited in graph.successors[citing]) if (cited != page) counts[cited]++
    return counts
}
private fun couplingCounts(graph: Graph, page: Int): IntArray {
    val counts = IntArray(graph.count)
    for (cited in graph.successors[page]) for (citing in graph.predecessors[cited]) if (citing != page) counts[citing]++
    return counts
}
private class SubgraphScores(graph: Graph, base: List<Int>, links: List<Edge>, settings: Settings) {
    private val hits = Hits.compute(graph.count, base, links, settings.hitsIterations)
    val authority = hits.authority
    val hub = hits.hub
    val salsaAuthority = salsa(graph.count, links)
    val salsaHub = salsa(graph.count, links.map { Edge(it.target, it.source) })
    val authorityTop = top(authority, settings.topK)
    val hubTop = top(hub, settings.topK)
    val salsaAuthorityTop = top(salsaAuthority, settings.topK)
    val salsaHubTop = top(salsaHub, settings.topK)
    val authorityOverlap = authorityTop.count { it in salsaAuthorityTop }
    val hubOverlap = hubTop.count { it in salsaHubTop }
    val authorityHosts = authorityTop.map(graph::host).distinct().size
    val cited = authorityTop[0]
    val citing = hubTop[0]
    val cocitation = cocitationCounts(graph, cited)
    val coupling = couplingCounts(graph, citing)
    val related = rankedCounts(cocitation, settings.topK)
    val similar = rankedCounts(coupling, settings.topK)
}
private class QueryResult(val query: Query, graph: Graph, scores: Scores, settings: Settings, index: Map<Int, Int>) {
    val matches: List<Int>
    val personalizedTop: List<Int>
    val rootSize: Int
    val baseSize: Int
    val dropped: Int
    val reach: Int
    val overlap: Int
    val subgraph: List<Edge>
    val personalized: PageRankResult
    val seedMass: Double
    val subScores: SubgraphScores?
    init {
        val include = query.words.filter { !it.startsWith('-') }
        val exclude = query.words.filter { it.startsWith('-') }.map { it.substring(1) }
        matches = scores.order.filter { node -> graph.pages[node].words.containsAll(include) && exclude.none { it in graph.pages[node].words } }
        val root = matches.take(settings.rootLimit)
        rootSize = root.size
        val inBase = BooleanArray(graph.count)
        for (node in root) {
            inBase[node] = true
            for (neighbor in graph.successors[node].take(settings.neighborLimit)) inBase[neighbor] = true
            for (neighbor in graph.predecessors[node].take(settings.neighborLimit)) inBase[neighbor] = true
        }
        val base = (0 until graph.count).filter { inBase[it] }
        baseSize = base.size
        val inside = graph.links.filter { inBase[it.source] && inBase[it.target] }
        subgraph = graph.inter(inside)
        dropped = inside.size - subgraph.size
        val seeds = query.seeds.map { index.getValue(it) }.sorted()
        personalized = pageRank(graph.forward(), seeds, settings.damping, settings)
        personalizedTop = top(personalized.values, settings.topK)
        reach = Components.reachable(graph.successors, seeds).count { it }
        seedMass = total(personalized.values, seeds)
        overlap = personalizedTop.count { scores.rank[it] <= settings.topK }
        subScores = if (subgraph.isEmpty()) null else SubgraphScores(graph, base, subgraph, settings)
    }
}
private class HostGraph(graph: Graph, settings: Settings) {
    val names = graph.pages.map { it.host }.distinct().sorted()
    val members = lists(names.size)
    val ofPage = IntArray(graph.count)
    val internalLinks = IntArray(names.size)
    val outgoing = IntArray(names.size)
    val incoming = IntArray(names.size)
    val weight = Array(names.size) { IntArray(names.size) }
    val edges = mutableListOf<Edge>()
    val heavy: List<Edge>
    val reciprocal: Int
    val componentCount: Int
    val largest: Int
    val run: PageRankResult
    val rank: IntArray
    init {
        val count = names.size
        val index = names.withIndex().associate { it.value to it.index }
        for (node in 0 until graph.count) { ofPage[node] = index.getValue(graph.host(node)); members[ofPage[node]].add(node) }
        for (edge in graph.links) {
            val a = ofPage[edge.source]
            val b = ofPage[edge.target]
            if (a == b) internalLinks[a]++ else { weight[a][b]++; outgoing[a]++; incoming[b]++ }
        }
        var reciprocalCount = 0
        val adjacency = lists(count)
        val incomingEdges = weightedLists(count)
        for (a in 0 until count) for (b in 0 until count) if (weight[a][b] > 0) {
            edges.add(Edge(a, b))
            adjacency[a].add(b)
            incomingEdges[b].add(WeightedEdge(a, weight[a][b]))
            if (weight[b][a] > 0) reciprocalCount++
        }
        reciprocal = reciprocalCount
        val components = Components.strong(adjacency)
        componentCount = components.size
        largest = components.maxOf { it.size }
        run = pageRank(incomingEdges, range(count), settings.damping, settings)
        rank = positions(rankOrder(run.values))
        heavy = edges.sortedWith(compareByDescending<Edge> { weight[it.source][it.target] }.thenBy { it.source }.thenBy { it.target }).take(settings.topK)
    }
}
private fun rankLines(graph: Graph, nodes: List<Int>, values: DoubleArray): List<String> =
    nodes.mapIndexed { index, node -> graph.describe(index + 1, node, Report.fixed(values[node])) }
private fun scoreBlock(name: String, graph: Graph, values: DoubleArray, limit: Int) =
    mutableListOf(line(name, "top", limit)).apply { addAll(rankLines(graph, top(values, limit), values)) }
private fun graphStats(graph: Graph, records: List<LinkRecord>, ignored: List<Ignored>, undirected: Undirected,
    table: ComponentTable, regions: IntArray, distances: DistanceStats, scores: Scores): List<String> {
    val intra = graph.links.count { graph.intra(it) }
    val reciprocal = graph.links.count { Edge(it.target, it.source) in graph.linkSet }
    val incoming = IntArray(graph.count) { graph.predecessors[it].size }
    val outgoing = IntArray(graph.count) { graph.successors[it].size }
    val maxIn = incoming.max()
    val maxOut = outgoing.max()
    val lines = mutableListOf(line("pages", graph.count), line("hosts", graph.pages.map { it.host }.distinct().size), line("link_rows", records.size), line("links", graph.links.size))
    for (reason in listOf("unknown", "self", "duplicate")) lines.add(line("ignored_$reason", ignored.count { it.reason == reason }))
    for ((record, reason) in ignored) lines.add(line("ignored", "line", record.line, "${record.source},${record.target}", reason))
    lines.addAll(listOf(line("intra_host_links", intra), line("inter_host_links", graph.links.size - intra),
        line("mean_degree", Report.fixed(graph.links.size.toDouble() / graph.count, 4)), line("reciprocity", Report.fraction(reciprocal, graph.links.size))))
    val dangling = graph.dangling()
    val noIn = (0 until graph.count).filter { incoming[it] == 0 }
    lines.add(appendValues(line("dangling", dangling.size), graph.ids(dangling)))
    lines.add(appendValues(line("no_in_links", noIn.size), graph.ids(noIn)))
    lines.add(appendValues(line("max_in_degree", maxIn, "pages"), graph.ids((0 until graph.count).filter { incoming[it] == maxIn })))
    lines.add(appendValues(line("max_out_degree", maxOut, "pages"), graph.ids((0 until graph.count).filter { outgoing[it] == maxOut })))
    for ((name, degrees) in listOf("in_degree_distribution" to incoming, "out_degree_distribution" to outgoing)) {
        lines.add("")
        lines.add(name)
        for ((value, count) in distribution(degrees)) lines.add(line(value, count))
    }
    lines.addAll(listOf("", line("undirected_links", undirected.edgeCount), line("transitivity", Report.fraction(undirected.closed, undirected.possible)),
        line("average_clustering", Report.fixed(undirected.clustering, 4), "pages", undirected.eligible),
        line("degeneracy", undirected.degeneracy, "pages", undirected.kcore.count { it == undirected.degeneracy }), "core_distribution"))
    for ((value, count) in distribution(undirected.kcore)) lines.add(line(value, count))
    lines.addAll(listOf("", line("strong_components", table.groups.size, "largest", table.groups[table.core].size, "singletons", table.singletons, "condensation_links", table.edgeCount),
        line("weak_components", undirected.weakCount, "largest", undirected.weakLargest), line("condensation_depth", table.depth)))
    for ((j, group) in table.groups.withIndex()) {
        if (group.size < 2) continue
        val text = line("scc", j + 1, "size", group.size, "min", graph.id(group[0]), "incoming", table.incoming[j], "outgoing", table.outgoing[j], "pagerank", Report.fixed(total(scores.pagerank, group)))
        lines.add(text + if (table.outgoing[j] == 0) " sink" else "")
    }
    lines.add("")
    lines.add(line("bowtie", "core_scc", table.core + 1))
    for (region in REGIONS.indices) {
        val members = (0 until graph.count).filter { regions[it] == region }
        var text = line(REGIONS[region], members.size, "pagerank", Report.fixed(total(scores.pagerank, members)))
        if (members.isNotEmpty()) text += " top ${graph.id(scores.representative(members))}"
        if (members.size in 1..10) text = appendValues("$text pages", graph.ids(members))
        lines.add(text)
    }
    val counts = Array(REGIONS.size) { IntArray(REGIONS.size) }
    for (edge in graph.links) counts[regions[edge.source]][regions[edge.target]]++
    lines.add("region_links")
    for (a in REGIONS.indices) for (b in REGIONS.indices) if (counts[a][b] > 0) lines.add(line(REGIONS[a], REGIONS[b], counts[a][b]))
    lines.addAll(listOf("", "distances", line("reachable_pairs", distances.pairs), line("average", Report.fraction(distances.total, distances.pairs)),
        line("diameter", distances.diameter, "from", graph.id(distances.source), "to", graph.id(distances.target)), line("effective_diameter", distances.effective())))
    for (steps in 1..distances.diameter) lines.add(line(steps, distances.histogram[steps]))
    return lines
}
private fun pagerankCsv(graph: Graph, table: ComponentTable, regions: IntArray, undirected: Undirected, scores: Scores): List<String> {
    val lines = mutableListOf(PAGERANK_HEADER)
    for (node in 0 until graph.count) lines.add(listOf(graph.id(node), graph.predecessors[node].size, graph.successors[node].size,
        table.labels[node] + 1, REGIONS[regions[node]], undirected.kcore[node], Report.fixed(scores.harmonic[node]), Report.fixed(scores.pagerank[node]), scores.rank[node],
        Report.fixed(scores.cheirank[node]), scores.cheirankRank[node], Report.fixed(scores.authority[node]), Report.fixed(scores.hub[node]),
        Report.fixed(scores.trustrank[node]), Report.fixed(scores.ratio[node], 4), scores.trustDistance[node]).joinToString(","))
    return lines
}
private fun rankings(graph: Graph, scores: Scores, undirected: Undirected, sweeps: List<Sweep>, spam: Spam, hosts: HostGraph, settings: Settings): List<String> {
    val limit = settings.topK
    val groups = mutableListOf<List<String>>()
    val pagerank = scoreBlock("pagerank", graph, scores.pagerank, limit)
    pagerank.add(line("dangling_mass", Report.fixed(total(scores.pagerank, graph.dangling()))))
    for (node in top(scores.pagerank, limit)) {
        val contributors = graph.predecessors[node].sortedWith(compareByDescending<Int> { Report.scaled(scores.contribution(graph, it)) }.thenBy { it }).take(3)
        val parts = mutableListOf<Any>("contributors", graph.id(node))
        for (source in contributors) { parts.add(graph.id(source)); parts.add(Report.fixed(scores.contribution(graph, source))) }
        pagerank.add(parts.joinToString(" "))
    }
    groups.add(pagerank)
    groups.add(scoreBlock("cheirank", graph, scores.cheirank, limit))
    groups.add(scoreBlock("authority", graph, scores.authority, limit))
    groups.add(scoreBlock("hub", graph, scores.hub, limit))
    groups.add(scoreBlock("trustrank", graph, scores.trustrank, limit))
    groups.add(scoreBlock("harmonic", graph, scores.harmonic, limit))
    val series = listOf(LongArray(graph.count) { graph.predecessors[it].size.toLong() }, scaled(scores.pagerank), scaled(scores.cheirank),
        scaled(scores.authority), scaled(scores.hub), scaled(scores.trustrank), scaled(scores.harmonic))
    val correlation = mutableListOf("correlation")
    for (a in QUANTITIES.indices) for (b in a + 1 until QUANTITIES.size) correlation.add(line(QUANTITIES[a], QUANTITIES[b], kendall(series[a], series[b])))
    groups.add(correlation)
    val sweepLines = mutableListOf("damping_sweep")
    for (sweep in sweeps) {
        sweepLines.add(line("damping", Report.fixed(sweep.damping, 4), "overlap", sweep.overlap, "footrule", sweep.footrule, "kendall", sweep.correlation,
            "largest_shift", graph.id(sweep.shift), scores.rank[sweep.shift], sweep.shiftRank))
        sweepLines.add(appendValues("top", graph.ids(sweep.top)))
    }
    groups.add(sweepLines)
    val spamLines = mutableListOf(line("spam", "top", settings.spamTop, "threshold", Report.fixed(settings.spamThreshold, 4)))
    for (node in spam.suspects) spamLines.add(line("suspect", graph.id(node), "rank", scores.rank[node], "pagerank", Report.fixed(scores.pagerank[node]),
        "trustrank", Report.fixed(scores.trustrank[node]), "trust_ratio", Report.fixed(scores.ratio[node], 4), "trust_distance", scores.trustDistance[node], "kcore", undirected.kcore[node], graph.host(node)))
    spamLines.add(line("count", spam.suspects.size))
    spamLines.add("trust_by_distance")
    val distances = scores.trustDistance.filter { it >= 0 }.distinct().sorted().toMutableList()
    if (-1 in scores.trustDistance) distances.add(-1)
    for (distance in distances) {
        val members = (0 until graph.count).filter { scores.trustDistance[it] == distance }
        spamLines.add(line(if (distance == -1) "unreachable" else distance, "pages", members.size,
            "trustrank", Report.fixed(total(scores.trustrank, members)), "pagerank", Report.fixed(total(scores.pagerank, members))))
    }
    groups.add(spamLines)
    val demotion = mutableListOf<String>()
    val demoted = spam.run
    if (demoted == null) demotion.add("demotion none")
    else {
        demotion.add(appendValues("demotion hosts", spam.hosts) + " removed_links ${spam.removed}")
        val nodes = top(demoted.values, limit)
        for ((i, node) in nodes.withIndex()) demotion.add(graph.describe(i + 1, node, Report.fixed(demoted.values[node]), "was", scores.rank[node]))
        val demotedRank = requireNotNull(spam.rank)
        for (node in spam.suspects) demotion.add(line("suspect", graph.id(node), "before", scores.rank[node], "after", demotedRank[node]))
    }
    groups.add(demotion)
    val hostLines = mutableListOf(line("host_graph", "hosts", hosts.names.size, "links", hosts.edges.size, "reciprocal", hosts.reciprocal,
        "strong_components", hosts.componentCount, "largest", hosts.largest), line("host_links", "top", limit))
    for (edge in hosts.heavy) hostLines.add(line(hosts.names[edge.source], hosts.names[edge.target], hosts.weight[edge.source][edge.target]))
    groups.add(hostLines)
    return blocks(groups)
}
private fun convergenceBlock(heading: String, run: PageRankResult): List<String> {
    val lines = mutableListOf("", heading)
    for (step in 10..run.changes.size step 10) lines.add(line("iteration", step, "l1", Report.fixed(run.changes[step - 1], 10)))
    lines.add(line("converged_at", run.convergedAt?.toString() ?: "none"))
    return lines
}
private fun convergence(scores: Scores, sweeps: List<Sweep>, spam: Spam, queries: List<QueryResult>, hosts: HostGraph, settings: Settings): List<String> {
    val damping = Report.fixed(settings.damping, 4)
    val lines = mutableListOf(line("iterations", settings.iterations, "tolerance", Report.fixed(settings.tolerance, 10)))
    lines.addAll(convergenceBlock(line("pagerank", "damping", damping), scores.pagerankRun))
    lines.addAll(convergenceBlock(line("cheirank", "damping", damping), scores.cheirankRun))
    lines.addAll(convergenceBlock(line("trustrank", "damping", damping, "seeds", settings.trusted.size), scores.trustrankRun))
    for (sweep in sweeps) lines.addAll(convergenceBlock(line("sweep", "damping", Report.fixed(sweep.damping, 4)), sweep.run))
    spam.run?.let { lines.addAll(convergenceBlock(line("demoted", "damping", damping), it)) }
    for (query in queries) lines.addAll(convergenceBlock(line("personalized", "query", query.query.number, "damping", damping), query.personalized))
    lines.addAll(convergenceBlock(line("host_pagerank", "damping", damping, "hosts", hosts.names.size), hosts.run))
    return lines
}
private fun queryLines(graph: Graph, scores: Scores, result: QueryResult, limit: Int): List<String> {
    val query = result.query
    val heading = appendValues(appendValues(line("query", query.number, "words"), query.words) + " seeds", query.seeds.toList())
    val lines = mutableListOf(heading, line("matched", result.matches.size, "root", result.rootSize, "base", result.baseSize,
        "links", result.subgraph.size, "dropped_intra_host", result.dropped), "results")
    lines.addAll(rankLines(graph, result.matches.take(limit), scores.pagerank))
    lines.add(line("personalized", "reach", result.reach, "seed_mass", Report.fixed(result.seedMass)))
    lines.addAll(rankLines(graph, result.personalizedTop, result.personalized.values))
    lines.add(line("overlap_with_global", result.overlap))
    val sub = result.subScores
    if (sub == null) { lines.add("hits none"); return lines }
    lines.add("hits authorities")
    lines.addAll(rankLines(graph, sub.authorityTop, sub.authority))
    lines.add("hits hubs")
    lines.addAll(rankLines(graph, sub.hubTop, sub.hub))
    lines.add("salsa authorities")
    lines.addAll(rankLines(graph, sub.salsaAuthorityTop, sub.salsaAuthority))
    lines.add("salsa hubs")
    lines.addAll(rankLines(graph, sub.salsaHubTop, sub.salsaHub))
    lines.add(line("hits_salsa_overlap", "authorities", sub.authorityOverlap, "hubs", sub.hubOverlap, "authority_hosts", sub.authorityHosts))
    lines.add(line("related_to", graph.id(sub.cited), "citing", graph.predecessors[sub.cited].size))
    for ((i, node) in sub.related.withIndex()) lines.add(graph.describe(i + 1, node, sub.cocitation[node]))
    lines.add(line("coupled_to", graph.id(sub.citing), "cited", graph.successors[sub.citing].size))
    for ((i, node) in sub.similar.withIndex()) lines.add(graph.describe(i + 1, node, sub.coupling[node]))
    return lines
}
private fun hostsCsv(graph: Graph, regions: IntArray, scores: Scores, hosts: HostGraph): List<String> {
    val lines = mutableListOf(HOSTS_HEADER)
    for (number in hosts.names.indices) {
        val members = hosts.members[number]
        val size = members.size
        val density = if (size >= 2) hosts.internalLinks[number].toDouble() / (size * (size - 1)) else 0.0
        lines.add(listOf(hosts.names[number], size, members.count { regions[it] == 0 }, hosts.internalLinks[number], Report.fixed(density, 4), hosts.outgoing[number],
            hosts.incoming[number], members.count { graph.successors[it].isEmpty() }, Report.fixed(total(scores.pagerank, members)), graph.id(scores.representative(members)),
            Report.fixed(hosts.run.values[number]), hosts.rank[number]).joinToString(","))
    }
    return lines
}
fun main() {
    val input = GraphIO.read("input")
    val pages = input.pages.sortedBy { it.id }
    val settings = input.settings
    val index = pages.withIndex().associate { it.value.id to it.index }
    val accepted = mutableSetOf<Edge>()
    val ignored = mutableListOf<Ignored>()
    for (record in input.records) {
        val source = index[record.source]
        val target = index[record.target]
        if (source == null || target == null) { ignored.add(Ignored(record, "unknown")); continue }
        val edge = Edge(source, target)
        if (source == target) ignored.add(Ignored(record, "self")) else if (!accepted.add(edge)) ignored.add(Ignored(record, "duplicate"))
    }
    val graph = Graph(pages, accepted.toList())
    val undirected = Undirected(graph)
    val table = ComponentTable(graph)
    val regions = bowtie(graph, table.groups[table.core])
    val distances = DistanceStats(graph)
    val trusted = settings.trusted.map { index.getValue(it) }.sorted()
    val scores = Scores(graph, settings, trusted, distances.harmonic)
    val sweeps = settings.sweep.map { Sweep(it, graph, scores, settings) }
    val spam = Spam(graph, scores, settings)
    val results = input.queries.map { QueryResult(it, graph, scores, settings, index) }
    val hosts = HostGraph(graph, settings)
    val queryBlocks = results.map { queryLines(graph, scores, it, settings.topK) }
    Report.write(linkedMapOf("graph_stats.txt" to graphStats(graph, input.records, ignored, undirected, table, regions, distances, scores),
        "pagerank.csv" to pagerankCsv(graph, table, regions, undirected, scores), "rankings.txt" to rankings(graph, scores, undirected, sweeps, spam, hosts, settings),
        "convergence.txt" to convergence(scores, sweeps, spam, results, hosts, settings), "queries.txt" to blocks(queryBlocks), "hosts.csv" to hostsCsv(graph, regions, scores, hosts)))
}
