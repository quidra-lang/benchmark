import Foundation

let regionNames = ["CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER"]
let quantityNames = ["in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"]

func total<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var result = 0.0
    for value in values { result += value }
    return result
}

func joinedBlocks(_ blocks: [[String]]) -> [String] {
    var lines: [String] = []
    for block in blocks {
        if !lines.isEmpty { lines.append("") }
        lines += block
    }
    return lines
}

func rankOrder(_ values: [Double]) -> [Int] {
    values.indices.sorted { first, second in
        let a = scaled(values[first])
        let b = scaled(values[second])
        return a == b ? first < second : a > b
    }
}

func positions(_ order: [Int]) -> [Int] {
    var ranks = Array(repeating: 0, count: order.count)
    for (position, node) in order.enumerated() { ranks[node] = position + 1 }
    return ranks
}

func topList(_ values: [Double], _ limit: Int) -> [Int] {
    Array(rankOrder(values).filter { scaled(values[$0]) > 0 }.prefix(limit))
}

func rankedCounts(_ counts: [Int], _ limit: Int) -> [Int] {
    Array(counts.indices.filter { counts[$0] > 0 }.sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0] > counts[$1] }.prefix(limit))
}

func distribution(_ values: [Int]) -> [(Int, Int)] {
    var counts: [Int: Int] = [:]
    for value in values { counts[value, default: 0] += 1 }
    return counts.keys.sorted().map { ($0, counts[$0]!) }
}

func runPageRank(_ edges: WeightedEdges, _ teleport: [Int], _ damping: Double, _ settings: Settings) -> PageRankResult {
    powerIteration(edges, teleport, damping, settings.iterations, settings.tolerance)
}

func classifyLinks(_ records: [LinkRecord], _ index: [Int: Int]) -> (accepted: [Link], ignored: [(number: Int, reason: String)]) {
    var accepted: Set<Link> = []
    var ignored: [(Int, String)] = []
    for (number, record) in records.enumerated() {
        guard let source = index[record.source], let target = index[record.target] else {
            ignored.append((number, "unknown"))
            continue
        }
        if source == target { ignored.append((number, "self")) }
        else if !accepted.insert(Link(source, target)).inserted { ignored.append((number, "duplicate")) }
    }
    return (accepted.sorted(), ignored)
}

struct Graph {
    let pages: [Page]
    let links: [Link]
    let linkSet: Set<Link>
    let successors: [[Int]]
    let predecessors: [[Int]]
    var count: Int { pages.count }

    init(_ pages: [Page], _ links: [Link]) {
        self.pages = pages
        let sorted = links.sorted()
        self.links = sorted
        linkSet = Set(sorted)
        var successors = Array(repeating: [Int](), count: pages.count)
        var predecessors = Array(repeating: [Int](), count: pages.count)
        for link in sorted { successors[link.source].append(link.target); predecessors[link.target].append(link.source) }
        self.successors = successors
        self.predecessors = predecessors
    }

    func host(_ node: Int) -> String { pages[node].host }
    func intraHost(_ source: Int, _ target: Int) -> Bool { host(source) == host(target) }
    func interHostLinks(_ links: [Link]) -> [Link] { links.filter { !intraHost($0.source, $0.target) } }
    var dangling: [Int] { pages.indices.filter { successors[$0].isEmpty } }
    func id(_ node: Int) -> Int { pages[node].id }
    var forwardEdges: WeightedEdges { predecessors.map { $0.map { WeightedEdge(source: $0, weight: 1) } } }
    var reverseEdges: WeightedEdges { successors.map { $0.map { WeightedEdge(source: $0, weight: 1) } } }
    func ids(_ nodes: [Int]) -> String { nodes.map { String(id($0)) }.joined(separator: " ") }
    func describe(_ position: Int, _ node: Int, _ values: String) -> String {
        let page = pages[node]
        return "\(position) \(page.id) \(values) \(page.host) \(page.title)"
    }
}

func kcoreNumbers(_ neighbors: [[Int]]) -> [Int] {
    var remaining = neighbors.map(\.count)
    var removed = Array(repeating: false, count: neighbors.count)
    var core = Array(repeating: 0, count: neighbors.count)
    var level = 0
    var left = neighbors.count
    while left > 0 {
        guard let node = neighbors.indices.first(where: { !removed[$0] && remaining[$0] <= level }) else {
            level += 1
            continue
        }
        removed[node] = true
        core[node] = level
        left -= 1
        for neighbor in neighbors[node] where !removed[neighbor] { remaining[neighbor] -= 1 }
    }
    return core
}

struct Undirected {
    let edgeCount: Int
    let closed: Int
    let possible: Int
    let eligible: Int
    let averageClustering: Double
    let kcore: [Int]
    let degeneracy: Int
    let weakCount: Int
    let weakLargest: Int

    init(_ graph: Graph) {
        var adjacent = Array(repeating: Set<Int>(), count: graph.count)
        for link in graph.links { adjacent[link.source].insert(link.target); adjacent[link.target].insert(link.source) }
        let neighbors = adjacent.map { $0.sorted() }
        edgeCount = neighbors.reduce(0) { $0 + $1.count } / 2
        var closed = 0
        var possible = 0
        var eligible = 0
        var localSum = 0.0
        for group in neighbors {
            if group.count < 2 { continue }
            var closedPairs = 0
            for (position, first) in group.enumerated() {
                for second in group.dropFirst(position + 1) where adjacent[first].contains(second) { closedPairs += 1 }
            }
            let pairs = group.count * (group.count - 1) / 2
            closed += closedPairs
            possible += pairs
            eligible += 1
            localSum += Double(closedPairs) / Double(pairs)
        }
        self.closed = closed
        self.possible = possible
        self.eligible = eligible
        averageClustering = localSum / Double(eligible)
        let core = kcoreNumbers(neighbors)
        kcore = core
        degeneracy = core.max()!
        let labels = weakComponents(neighbors)
        let count = labels.max()! + 1
        weakCount = count
        var sizes = Array(repeating: 0, count: count)
        for label in labels { sizes[label] += 1 }
        weakLargest = sizes.max()!
    }
}

func longestPath(_ count: Int, _ edges: Set<Link>) -> Int {
    var successors = Array(repeating: [Int](), count: count)
    var pending = Array(repeating: 0, count: count)
    for link in edges.sorted() { successors[link.source].append(link.target); pending[link.target] += 1 }
    var length = Array(repeating: 0, count: count)
    var ready = (0..<count).filter { pending[$0] == 0 }
    while let node = ready.popLast() {
        for target in successors[node] {
            length[target] = max(length[target], length[node] + 1)
            pending[target] -= 1
            if pending[target] == 0 { ready.append(target) }
        }
    }
    return length.max()!
}

struct ComponentTable {
    let groups: [[Int]]
    let label: [Int]
    let incoming: [Int]
    let outgoing: [Int]
    let edgeCount: Int
    let depth: Int
    let core: Int
    let singletons: Int

    init(_ graph: Graph) {
        let groups = strongComponents(graph.successors).map { $0.sorted() }.sorted { $0[0] < $1[0] }
        self.groups = groups
        var label = Array(repeating: 0, count: graph.count)
        for (number, group) in groups.enumerated() { for node in group { label[node] = number } }
        self.label = label
        var incoming = Array(repeating: 0, count: groups.count)
        var outgoing = Array(repeating: 0, count: groups.count)
        var edges: Set<Link> = []
        for link in graph.links {
            let first = label[link.source]
            let second = label[link.target]
            if first != second { outgoing[first] += 1; incoming[second] += 1; edges.insert(Link(first, second)) }
        }
        self.incoming = incoming
        self.outgoing = outgoing
        edgeCount = edges.count
        depth = longestPath(groups.count, edges)
        var core = 0
        for (number, group) in groups.enumerated() where group.count > groups[core].count { core = number }
        self.core = core
        singletons = groups.filter { $0.count == 1 }.count
    }
}

func bowtieRegions(_ graph: Graph, _ corePages: [Int]) -> [Int] {
    let forward = reachable(graph.successors, corePages)
    let backward = reachable(graph.predecessors, corePages)
    var inCore = Array(repeating: false, count: graph.count)
    for node in corePages { inCore[node] = true }
    var regions = Array(repeating: 6, count: graph.count)
    for node in 0..<graph.count {
        if inCore[node] { regions[node] = 0 }
        else if backward[node] { regions[node] = 1 }
        else if forward[node] { regions[node] = 2 }
    }
    let inPages = regions.indices.filter { regions[$0] == 1 }
    let outPages = regions.indices.filter { regions[$0] == 2 }
    let fromIn = reachable(graph.successors, inPages)
    let toOut = reachable(graph.predecessors, outPages)
    for node in 0..<graph.count {
        if inCore[node] || backward[node] || forward[node] { continue }
        if fromIn[node] && toOut[node] { regions[node] = 3 }
        else if fromIn[node] { regions[node] = 4 }
        else if toOut[node] { regions[node] = 5 }
    }
    return regions
}

struct DistanceStats {
    let pairs: Int
    let sum: Int
    let diameter: Int
    let diameterPair: Link
    let histogram: [Int]
    let harmonic: [Double]

    init(_ graph: Graph) {
        var pairs = 0
        var sum = 0
        var diameter = 0
        var diameterPair = Link(0, 0)
        var histogram = Array(repeating: 0, count: graph.count)
        var harmonic = Array(repeating: 0.0, count: graph.count)
        for source in 0..<graph.count {
            let distance = bfsDistances(graph.successors, [source])
            for (target, steps) in distance.enumerated() {
                if target == source || steps < 0 { continue }
                pairs += 1
                sum += steps
                histogram[steps] += 1
                harmonic[target] += 1 / Double(steps)
                if steps > diameter { diameter = steps; diameterPair = Link(source, target) }
            }
        }
        self.pairs = pairs
        self.sum = sum
        self.diameter = diameter
        self.diameterPair = diameterPair
        self.histogram = histogram
        self.harmonic = harmonic
    }

    var effectiveDiameter: Int {
        var reached = 0
        for steps in 1...diameter {
            reached += histogram[steps]
            if 10 * reached >= 9 * pairs { return steps }
        }
        return diameter
    }
}

struct PageScores {
    let pagerankRun: PageRankResult
    let cheirankRun: PageRankResult
    let trustrankRun: PageRankResult
    let order: [Int]
    let rank: [Int]
    let cheirankRank: [Int]
    let trustRatio: [Double]
    let trustDistance: [Int]
    let authority: [Double]
    let hub: [Double]
    let harmonic: [Double]
    var pagerank: [Double] { pagerankRun.values }
    var cheirank: [Double] { cheirankRun.values }
    var trustrank: [Double] { trustrankRun.values }

    init(_ graph: Graph, _ settings: Settings, _ trusted: [Int], _ harmonic: [Double]) {
        let everyone = Array(0..<graph.count)
        let pagerankRun = runPageRank(graph.forwardEdges, everyone, settings.damping, settings)
        let cheirankRun = runPageRank(graph.reverseEdges, everyone, settings.damping, settings)
        let trustrankRun = runPageRank(graph.forwardEdges, trusted, settings.damping, settings)
        self.pagerankRun = pagerankRun
        self.cheirankRun = cheirankRun
        self.trustrankRun = trustrankRun
        let order = rankOrder(pagerankRun.values)
        self.order = order
        rank = positions(order)
        cheirankRank = positions(rankOrder(cheirankRun.values))
        trustRatio = zip(trustrankRun.values, pagerankRun.values).map { trust, score in trust / score }
        trustDistance = bfsDistances(graph.successors, trusted)
        let scores = hits(graph.count, everyone, graph.interHostLinks(graph.links), settings.hitsIterations)
        authority = scores.authority
        hub = scores.hub
        self.harmonic = harmonic
    }

    func contribution(_ graph: Graph, _ source: Int, _ damping: Double) -> Double {
        (damping * pagerank[source]) / Double(graph.successors[source].count)
    }
    func representative(_ nodes: [Int]) -> Int { nodes.min { rank[$0] < rank[$1] }! }
}

func kendall(_ first: [Int], _ second: [Int]) -> String {
    var concordant = 0
    var discordant = 0
    for i in first.indices {
        for j in (i + 1)..<first.count {
            let dx = first[i] - first[j]
            let dy = second[i] - second[j]
            if dx == 0 || dy == 0 { continue }
            if (dx > 0) == (dy > 0) { concordant += 1 }
            else { discordant += 1 }
        }
    }
    return fraction(concordant - discordant, first.count * (first.count - 1) / 2)
}

struct SweepResult {
    let damping: Double
    let run: PageRankResult
    let overlap: Int
    let footrule: Int
    let correlation: String
    let shift: Int
    let shiftRank: Int
    let top: [Int]

    init(_ damping: Double, _ graph: Graph, _ scores: PageScores, _ settings: Settings) {
        self.damping = damping
        let run = runPageRank(graph.forwardEdges, Array(0..<graph.count), damping, settings)
        self.run = run
        let order = rankOrder(run.values)
        let rank = positions(order)
        overlap = (0..<graph.count).filter { rank[$0] <= settings.topK && scores.rank[$0] <= settings.topK }.count
        footrule = (0..<graph.count).reduce(0) { $0 + abs(rank[$1] - scores.rank[$1]) }
        correlation = kendall(scores.pagerank.map { scaled($0) }, run.values.map { scaled($0) })
        var shift = 0
        for node in 0..<graph.count where abs(rank[node] - scores.rank[node]) > abs(rank[shift] - scores.rank[shift]) { shift = node }
        self.shift = shift
        shiftRank = rank[shift]
        top = Array(order.prefix(settings.topK))
    }
}

struct SpamReport {
    let suspects: [Int]
    let hosts: [String]
    let removed: Int
    let run: PageRankResult?
    let rank: [Int]

    init(_ graph: Graph, _ scores: PageScores, _ settings: Settings) {
        let suspects = scores.order.prefix(settings.spamTop).filter { Double(scaled(scores.trustRatio[$0], 4)) / 10000 < settings.spamThreshold }
        self.suspects = suspects
        let hosts = Set(suspects.map { graph.host($0) }).sorted(by: asciiLess)
        self.hosts = hosts
        if suspects.isEmpty { removed = 0; run = nil; rank = [] }
        else {
            let kept = graph.links.filter { !(graph.intraHost($0.source, $0.target) && hosts.contains(graph.host($0.source))) }
            removed = graph.links.count - kept.count
            let demoted = Graph(graph.pages, kept)
            let run = runPageRank(demoted.forwardEdges, Array(0..<graph.count), settings.damping, settings)
            self.run = run
            rank = positions(rankOrder(run.values))
        }
    }
}

func salsaScores(_ count: Int, _ links: [Link]) -> [Double] {
    var degree = Array(repeating: 0, count: count)
    var targets = Array(repeating: [Int](), count: count)
    for link in links { degree[link.target] += 1; targets[link.source].append(link.target) }
    var neighbors = Array(repeating: [Int](), count: count)
    for group in targets {
        for (first, second) in zip(group, group.dropFirst()) { neighbors[first].append(second); neighbors[second].append(first) }
    }
    let labels = weakComponents(neighbors)
    let side = (0..<count).filter { degree[$0] > 0 }
    var size = Array(repeating: 0, count: count)
    var mass = Array(repeating: 0, count: count)
    for node in side { size[labels[node]] += 1; mass[labels[node]] += degree[node] }
    var scores = Array(repeating: 0.0, count: count)
    for node in side {
        let label = labels[node]
        scores[node] = Double(size[label] * degree[node]) / Double(side.count * mass[label])
    }
    return scores
}

struct SubgraphScores {
    let authority: [Double]
    let hub: [Double]
    let salsaAuthority: [Double]
    let salsaHub: [Double]
    let authorityTop: [Int]
    let hubTop: [Int]
    let salsaAuthorityTop: [Int]
    let salsaHubTop: [Int]
    let authorityOverlap: Int
    let hubOverlap: Int
    let authorityHosts: Int
    let cited: Int
    let cocitation: [Int]
    let related: [Int]
    let citing: Int
    let coupling: [Int]
    let similar: [Int]

    init(_ graph: Graph, _ base: [Int], _ subgraph: [Link], _ settings: Settings) {
        let hitsScores = hits(graph.count, base, subgraph, settings.hitsIterations)
        authority = hitsScores.authority
        hub = hitsScores.hub
        let salsaAuthority = salsaScores(graph.count, subgraph)
        let salsaHub = salsaScores(graph.count, subgraph.map { Link($0.target, $0.source) })
        self.salsaAuthority = salsaAuthority
        self.salsaHub = salsaHub
        let authorityTop = topList(hitsScores.authority, settings.topK)
        let hubTop = topList(hitsScores.hub, settings.topK)
        let salsaAuthorityTop = topList(salsaAuthority, settings.topK)
        let salsaHubTop = topList(salsaHub, settings.topK)
        self.authorityTop = authorityTop
        self.hubTop = hubTop
        self.salsaAuthorityTop = salsaAuthorityTop
        self.salsaHubTop = salsaHubTop
        authorityOverlap = Set(authorityTop).intersection(salsaAuthorityTop).count
        hubOverlap = Set(hubTop).intersection(salsaHubTop).count
        authorityHosts = Set(authorityTop.map { graph.host($0) }).count
        let cited = authorityTop[0]
        self.cited = cited
        var cocitation = Array(repeating: 0, count: graph.count)
        for citing in graph.predecessors[cited] {
            for target in graph.successors[citing] where target != cited { cocitation[target] += 1 }
        }
        self.cocitation = cocitation
        related = rankedCounts(cocitation, settings.topK)
        let citing = hubTop[0]
        self.citing = citing
        var coupling = Array(repeating: 0, count: graph.count)
        for target in graph.successors[citing] {
            for source in graph.predecessors[target] where source != citing { coupling[source] += 1 }
        }
        self.coupling = coupling
        similar = rankedCounts(coupling, settings.topK)
    }
}

struct QueryResult {
    let matches: [Int]
    let rootSize: Int
    let baseSize: Int
    let subgraph: [Link]
    let dropped: Int
    let personalized: PageRankResult
    let reach: Int
    let seedMass: Double
    let personalizedTop: [Int]
    let globalOverlap: Int
    let subgraphScores: SubgraphScores?

    init(_ query: Query, _ graph: Graph, _ scores: PageScores, _ settings: Settings, _ index: [Int: Int]) {
        let include = query.words.filter { !$0.hasPrefix("-") }
        let exclude = query.words.filter { $0.hasPrefix("-") }.map { String($0.dropFirst()) }
        let matches = scores.order.filter { node in
            let words = graph.pages[node].words
            return include.allSatisfy { words.contains($0) } && exclude.allSatisfy { !words.contains($0) }
        }
        self.matches = matches
        let root = matches.prefix(settings.rootLimit)
        rootSize = root.count
        var inBase = Array(repeating: false, count: graph.count)
        for node in root {
            inBase[node] = true
            for neighbor in graph.successors[node].prefix(settings.neighborLimit) { inBase[neighbor] = true }
            for neighbor in graph.predecessors[node].prefix(settings.neighborLimit) { inBase[neighbor] = true }
        }
        let base = (0..<graph.count).filter { inBase[$0] }
        baseSize = base.count
        let inside = graph.links.filter { inBase[$0.source] && inBase[$0.target] }
        let subgraph = graph.interHostLinks(inside)
        self.subgraph = subgraph
        dropped = inside.count - subgraph.count
        let seeds = query.seeds.map { index[$0]! }.sorted()
        let personalized = runPageRank(graph.forwardEdges, seeds, settings.damping, settings)
        self.personalized = personalized
        reach = reachable(graph.successors, seeds).filter { $0 }.count
        seedMass = total(seeds.map { personalized.values[$0] })
        let personalizedTop = topList(personalized.values, settings.topK)
        self.personalizedTop = personalizedTop
        globalOverlap = personalizedTop.filter { scores.rank[$0] <= settings.topK }.count
        subgraphScores = subgraph.isEmpty ? nil : SubgraphScores(graph, base, subgraph, settings)
    }
}

struct HostGraph {
    let names: [String]
    let members: [[Int]]
    let weight: [[Int]]
    let internalLinks: [Int]
    let outgoing: [Int]
    let incoming: [Int]
    let edges: [Link]
    let reciprocal: Int
    let componentCount: Int
    let largest: Int
    let run: PageRankResult
    let rank: [Int]
    let heavy: [Link]

    init(_ graph: Graph, _ settings: Settings) {
        let names = Set(graph.pages.map(\.host)).sorted(by: asciiLess)
        self.names = names
        let count = names.count
        let index = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) })
        let ofPage = graph.pages.map { index[$0.host]! }
        var members = Array(repeating: [Int](), count: count)
        for (node, host) in ofPage.enumerated() { members[host].append(node) }
        self.members = members
        var weight = Array(repeating: Array(repeating: 0, count: count), count: count)
        var internalLinks = Array(repeating: 0, count: count)
        var outgoing = Array(repeating: 0, count: count)
        var incoming = Array(repeating: 0, count: count)
        for link in graph.links {
            let first = ofPage[link.source]
            let second = ofPage[link.target]
            if first == second { internalLinks[first] += 1 }
            else { weight[first][second] += 1; outgoing[first] += 1; incoming[second] += 1 }
        }
        self.weight = weight
        self.internalLinks = internalLinks
        self.outgoing = outgoing
        self.incoming = incoming
        var edges: [Link] = []
        var adjacency = Array(repeating: [Int](), count: count)
        var inEdges = Array(repeating: [WeightedEdge](), count: count)
        for first in 0..<count {
            for second in 0..<count where weight[first][second] > 0 {
                edges.append(Link(first, second))
                adjacency[first].append(second)
                inEdges[second].append(WeightedEdge(source: first, weight: weight[first][second]))
            }
        }
        self.edges = edges
        reciprocal = edges.filter { weight[$0.target][$0.source] > 0 }.count
        let components = strongComponents(adjacency)
        componentCount = components.count
        largest = components.map(\.count).max()!
        let run = runPageRank(inEdges, Array(0..<count), settings.damping, settings)
        self.run = run
        rank = positions(rankOrder(run.values))
        heavy = Array(edges.sorted { first, second in
            let a = weight[first.source][first.target]
            let b = weight[second.source][second.target]
            return a == b ? first < second : a > b
        }.prefix(settings.topK))
    }
}

func appendIDs(_ prefix: String, _ graph: Graph, _ nodes: [Int]) -> String {
    nodes.isEmpty ? prefix : prefix + " " + graph.ids(nodes)
}

func graphStatsLines(_ graph: Graph, _ records: [LinkRecord], _ ignored: [(number: Int, reason: String)],
    _ undirected: Undirected, _ table: ComponentTable, _ regions: [Int], _ distances: DistanceStats,
    _ scores: PageScores, _ hosts: HostGraph) -> [String] {
    let intra = graph.links.filter { graph.intraHost($0.source, $0.target) }.count
    let reciprocal = graph.links.filter { graph.linkSet.contains(Link($0.target, $0.source)) }.count
    let indegrees = graph.predecessors.map(\.count)
    let outdegrees = graph.successors.map(\.count)
    let noIn = indegrees.indices.filter { indegrees[$0] == 0 }
    let maxIn = indegrees.max()!
    let maxOut = outdegrees.max()!
    let maxInPages = indegrees.indices.filter { indegrees[$0] == maxIn }
    let maxOutPages = outdegrees.indices.filter { outdegrees[$0] == maxOut }
    let dangling = graph.dangling
    var lines = ["pages \(graph.count)", "hosts \(hosts.names.count)", "link_rows \(records.count)", "links \(graph.links.count)"]
    for reason in ["unknown", "self", "duplicate"] { lines.append("ignored_\(reason) \(ignored.filter { $0.reason == reason }.count)") }
    for item in ignored {
        let record = records[item.number]
        lines.append("ignored line \(record.line) \(record.source),\(record.target) \(item.reason)")
    }
    lines += ["intra_host_links \(intra)", "inter_host_links \(graph.links.count - intra)",
        "mean_degree \(fixed(Double(graph.links.count) / Double(graph.count), 4))",
        "reciprocity \(fraction(reciprocal, graph.links.count))",
        appendIDs("dangling \(dangling.count)", graph, dangling), appendIDs("no_in_links \(noIn.count)", graph, noIn),
        appendIDs("max_in_degree \(maxIn) pages", graph, maxInPages), appendIDs("max_out_degree \(maxOut) pages", graph, maxOutPages)]
    for (name, degrees) in [("in_degree", indegrees), ("out_degree", outdegrees)] {
        lines += ["", name + "_distribution"]
        lines += distribution(degrees).map { value, count in "\(value) \(count)" }
    }
    let degeneracyPages = undirected.kcore.filter { $0 == undirected.degeneracy }.count
    lines += ["", "undirected_links \(undirected.edgeCount)", "transitivity \(fraction(undirected.closed, undirected.possible))",
        "average_clustering \(fixed(undirected.averageClustering, 4)) pages \(undirected.eligible)",
        "degeneracy \(undirected.degeneracy) pages \(degeneracyPages)", "core_distribution"]
    lines += distribution(undirected.kcore).map { value, count in "\(value) \(count)" }
    lines += ["", "strong_components \(table.groups.count) largest \(table.groups[table.core].count) singletons \(table.singletons) condensation_links \(table.edgeCount)",
        "weak_components \(undirected.weakCount) largest \(undirected.weakLargest)", "condensation_depth \(table.depth)"]
    for (number, group) in table.groups.enumerated() {
        if group.count < 2 { continue }
        let mass = total(group.map { scores.pagerank[$0] })
        let suffix = table.outgoing[number] == 0 ? " sink" : ""
        lines.append("scc \(number + 1) size \(group.count) min \(graph.id(group[0])) incoming \(table.incoming[number]) outgoing \(table.outgoing[number]) pagerank \(fixed(mass))\(suffix)")
    }
    lines += ["", "bowtie core_scc \(table.core + 1)"]
    for (region, name) in regionNames.enumerated() {
        let members = regions.indices.filter { regions[$0] == region }
        let mass = total(members.map { scores.pagerank[$0] })
        var text = "\(name) \(members.count) pagerank \(fixed(mass))"
        if !members.isEmpty { text += " top \(graph.id(scores.representative(members)))" }
        if !members.isEmpty && members.count <= 10 { text += " pages \(graph.ids(members))" }
        lines.append(text)
    }
    var counts = Array(repeating: Array(repeating: 0, count: 7), count: 7)
    for link in graph.links { counts[regions[link.source]][regions[link.target]] += 1 }
    lines.append("region_links")
    for first in 0..<7 { for second in 0..<7 where counts[first][second] > 0 {
        lines.append("\(regionNames[first]) \(regionNames[second]) \(counts[first][second])")
    } }
    let pair = distances.diameterPair
    lines += ["", "distances", "reachable_pairs \(distances.pairs)", "average \(fraction(distances.sum, distances.pairs))",
        "diameter \(distances.diameter) from \(graph.id(pair.source)) to \(graph.id(pair.target))", "effective_diameter \(distances.effectiveDiameter)"]
    for steps in 1...distances.diameter { lines.append("\(steps) \(distances.histogram[steps])") }
    return lines
}

func pagerankCSVLines(_ graph: Graph, _ table: ComponentTable, _ regions: [Int], _ undirected: Undirected, _ scores: PageScores) -> [String] {
    var lines = ["id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance"]
    for node in 0..<graph.count {
        let fields = [String(graph.id(node)), String(graph.predecessors[node].count), String(graph.successors[node].count),
            String(table.label[node] + 1), regionNames[regions[node]], String(undirected.kcore[node]), fixed(scores.harmonic[node]),
            fixed(scores.pagerank[node]), String(scores.rank[node]), fixed(scores.cheirank[node]), String(scores.cheirankRank[node]),
            fixed(scores.authority[node]), fixed(scores.hub[node]), fixed(scores.trustrank[node]), fixed(scores.trustRatio[node], 4), String(scores.trustDistance[node])]
        lines.append(fields.joined(separator: ","))
    }
    return lines
}

func rankLines(_ graph: Graph, _ nodes: [Int], _ values: [Double]) -> [String] {
    nodes.enumerated().map { position, node in graph.describe(position + 1, node, fixed(values[node])) }
}

func scoreBlock(_ name: String, _ graph: Graph, _ values: [Double], _ limit: Int) -> [String] {
    ["\(name) top \(limit)"] + rankLines(graph, topList(values, limit), values)
}

func rankingsLines(_ graph: Graph, _ scores: PageScores, _ undirected: Undirected, _ sweeps: [SweepResult],
    _ spam: SpamReport, _ hosts: HostGraph, _ settings: Settings) -> [String] {
    let limit = settings.topK
    var pagerank = scoreBlock("pagerank", graph, scores.pagerank, limit)
    pagerank.append("dangling_mass \(fixed(total(graph.dangling.map { scores.pagerank[$0] })))")
    for node in topList(scores.pagerank, limit) {
        let contributors = graph.predecessors[node].sorted { first, second in
            let a = scaled(scores.contribution(graph, first, settings.damping))
            let b = scaled(scores.contribution(graph, second, settings.damping))
            return a == b ? first < second : a > b
        }
        var parts = ["contributors", String(graph.id(node))]
        for source in contributors.prefix(3) { parts += [String(graph.id(source)), fixed(scores.contribution(graph, source, settings.damping))] }
        pagerank.append(parts.joined(separator: " "))
    }
    var blocks = [pagerank]
    for (name, values) in [("cheirank", scores.cheirank), ("authority", scores.authority), ("hub", scores.hub),
        ("trustrank", scores.trustrank), ("harmonic", scores.harmonic)] { blocks.append(scoreBlock(name, graph, values, limit)) }
    var series = [graph.predecessors.map(\.count)]
    for values in [scores.pagerank, scores.cheirank, scores.authority, scores.hub, scores.trustrank, scores.harmonic] {
        series.append(values.map { scaled($0) })
    }
    var correlations = ["correlation"]
    for first in 0..<7 { for second in (first + 1)..<7 {
        correlations.append("\(quantityNames[first]) \(quantityNames[second]) \(kendall(series[first], series[second]))")
    } }
    blocks.append(correlations)
    var sweepLines = ["damping_sweep"]
    for sweep in sweeps {
        sweepLines.append("damping \(fixed(sweep.damping, 4)) overlap \(sweep.overlap) footrule \(sweep.footrule) kendall \(sweep.correlation) largest_shift \(graph.id(sweep.shift)) \(scores.rank[sweep.shift]) \(sweep.shiftRank)")
        sweepLines.append(appendIDs("top", graph, sweep.top))
    }
    blocks.append(sweepLines)
    var spamLines = ["spam top \(settings.spamTop) threshold \(fixed(settings.spamThreshold, 4))"]
    for node in spam.suspects {
        spamLines.append("suspect \(graph.id(node)) rank \(scores.rank[node]) pagerank \(fixed(scores.pagerank[node])) trustrank \(fixed(scores.trustrank[node])) trust_ratio \(fixed(scores.trustRatio[node], 4)) trust_distance \(scores.trustDistance[node]) kcore \(undirected.kcore[node]) \(graph.host(node))")
    }
    spamLines += ["count \(spam.suspects.count)", "trust_by_distance"]
    var distances = Set(scores.trustDistance.filter { $0 >= 0 }).sorted()
    if scores.trustDistance.contains(-1) { distances.append(-1) }
    for distance in distances {
        let members = scores.trustDistance.indices.filter { scores.trustDistance[$0] == distance }
        let label = distance == -1 ? "unreachable" : String(distance)
        spamLines.append("\(label) pages \(members.count) trustrank \(fixed(total(members.map { scores.trustrank[$0] }))) pagerank \(fixed(total(members.map { scores.pagerank[$0] })))")
    }
    blocks.append(spamLines)
    var demotion = ["demotion none"]
    if let run = spam.run {
        demotion = ["demotion hosts \(spam.hosts.joined(separator: " ")) removed_links \(spam.removed)"]
        for (position, node) in topList(run.values, limit).enumerated() {
            demotion.append(graph.describe(position + 1, node, "\(fixed(run.values[node])) was \(scores.rank[node])"))
        }
        for node in spam.suspects { demotion.append("suspect \(graph.id(node)) before \(scores.rank[node]) after \(spam.rank[node])") }
    }
    blocks.append(demotion)
    var hostLines = ["host_graph hosts \(hosts.names.count) links \(hosts.edges.count) reciprocal \(hosts.reciprocal) strong_components \(hosts.componentCount) largest \(hosts.largest)", "host_links top \(limit)"]
    for link in hosts.heavy { hostLines.append("\(hosts.names[link.source]) \(hosts.names[link.target]) \(hosts.weight[link.source][link.target])") }
    blocks.append(hostLines)
    return joinedBlocks(blocks)
}

func convergenceBlock(_ heading: String, _ run: PageRankResult) -> [String] {
    var lines = ["", heading]
    for step in stride(from: 10, through: run.changes.count, by: 10) { lines.append("iteration \(step) l1 \(fixed(run.changes[step - 1], 10))") }
    lines.append("converged_at \(run.convergedAt.map(String.init) ?? "none")")
    return lines
}

func convergenceLines(_ scores: PageScores, _ sweeps: [SweepResult], _ spam: SpamReport, _ queries: [Query],
    _ results: [QueryResult], _ hosts: HostGraph, _ settings: Settings) -> [String] {
    let damping = fixed(settings.damping, 4)
    var lines = ["iterations \(settings.iterations) tolerance \(fixed(settings.tolerance, 10))"]
    lines += convergenceBlock("pagerank damping \(damping)", scores.pagerankRun)
    lines += convergenceBlock("cheirank damping \(damping)", scores.cheirankRun)
    lines += convergenceBlock("trustrank damping \(damping) seeds \(settings.trusted.count)", scores.trustrankRun)
    for sweep in sweeps { lines += convergenceBlock("sweep damping \(fixed(sweep.damping, 4))", sweep.run) }
    if let run = spam.run { lines += convergenceBlock("demoted damping \(damping)", run) }
    for (query, result) in zip(queries, results) { lines += convergenceBlock("personalized query \(query.number) damping \(damping)", result.personalized) }
    lines += convergenceBlock("host_pagerank damping \(damping) hosts \(hosts.names.count)", hosts.run)
    return lines
}

func queryBlock(_ graph: Graph, _ scores: PageScores, _ query: Query, _ result: QueryResult, _ limit: Int) -> [String] {
    let seeds = query.seeds.map(String.init).joined(separator: " ")
    var lines = ["query \(query.number) words \(query.words.joined(separator: " ")) seeds \(seeds)",
        "matched \(result.matches.count) root \(result.rootSize) base \(result.baseSize) links \(result.subgraph.count) dropped_intra_host \(result.dropped)", "results"]
    lines += rankLines(graph, Array(result.matches.prefix(limit)), scores.pagerank)
    lines.append("personalized reach \(result.reach) seed_mass \(fixed(result.seedMass))")
    lines += rankLines(graph, result.personalizedTop, result.personalized.values)
    lines.append("overlap_with_global \(result.globalOverlap)")
    guard let sub = result.subgraphScores else { lines.append("hits none"); return lines }
    for (heading, nodes, values) in [("hits authorities", sub.authorityTop, sub.authority), ("hits hubs", sub.hubTop, sub.hub),
        ("salsa authorities", sub.salsaAuthorityTop, sub.salsaAuthority), ("salsa hubs", sub.salsaHubTop, sub.salsaHub)] {
        lines.append(heading)
        lines += rankLines(graph, nodes, values)
    }
    lines.append("hits_salsa_overlap authorities \(sub.authorityOverlap) hubs \(sub.hubOverlap) authority_hosts \(sub.authorityHosts)")
    lines.append("related_to \(graph.id(sub.cited)) citing \(graph.predecessors[sub.cited].count)")
    for (position, node) in sub.related.enumerated() { lines.append(graph.describe(position + 1, node, String(sub.cocitation[node]))) }
    lines.append("coupled_to \(graph.id(sub.citing)) cited \(graph.successors[sub.citing].count)")
    for (position, node) in sub.similar.enumerated() { lines.append(graph.describe(position + 1, node, String(sub.coupling[node]))) }
    return lines
}

func hostsCSVLines(_ graph: Graph, _ regions: [Int], _ scores: PageScores, _ hosts: HostGraph) -> [String] {
    var lines = ["host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank"]
    for (number, name) in hosts.names.enumerated() {
        let members = hosts.members[number]
        let size = members.count
        let density = size >= 2 ? Double(hosts.internalLinks[number]) / Double(size * (size - 1)) : 0
        let core = members.filter { regions[$0] == 0 }.count
        let dangling = members.filter { graph.successors[$0].isEmpty }.count
        let mass = total(members.map { scores.pagerank[$0] })
        let fields = [name, String(size), String(core), String(hosts.internalLinks[number]), fixed(density, 4),
            String(hosts.outgoing[number]), String(hosts.incoming[number]), String(dangling), fixed(mass),
            String(graph.id(scores.representative(members))), fixed(hosts.run.values[number]), String(hosts.rank[number])]
        lines.append(fields.joined(separator: ","))
    }
    return lines
}

let pages = try readPages("input/pages.csv").sorted { $0.id < $1.id }
let records = try readLinks("input/links.csv")
let queries = try readQueries("input/queries.txt")
let settings = try readSettings("input/params.txt")
let index = Dictionary(uniqueKeysWithValues: pages.enumerated().map { ($0.element.id, $0.offset) })
let classified = classifyLinks(records, index)
let graph = Graph(pages, classified.accepted)
let undirected = Undirected(graph)
let table = ComponentTable(graph)
let regions = bowtieRegions(graph, table.groups[table.core])
let distances = DistanceStats(graph)
let trusted = settings.trusted.map { index[$0]! }.sorted()
let scores = PageScores(graph, settings, trusted, distances.harmonic)
let sweeps = settings.sweep.map { SweepResult($0, graph, scores, settings) }
let spam = SpamReport(graph, scores, settings)
let results = queries.map { QueryResult($0, graph, scores, settings, index) }
let hosts = HostGraph(graph, settings)
let queryBlocks = zip(queries, results).map { query, result in queryBlock(graph, scores, query, result, settings.topK) }
let outputs = [
    ("graph_stats.txt", graphStatsLines(graph, records, classified.ignored, undirected, table, regions, distances, scores, hosts)),
    ("pagerank.csv", pagerankCSVLines(graph, table, regions, undirected, scores)),
    ("rankings.txt", rankingsLines(graph, scores, undirected, sweeps, spam, hosts, settings)),
    ("convergence.txt", convergenceLines(scores, sweeps, spam, queries, results, hosts, settings)),
    ("queries.txt", joinedBlocks(queryBlocks)), ("hosts.csv", hostsCSVLines(graph, regions, scores, hosts))
]
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, lines) in outputs { try writeLines("output/\(name)", lines) }
