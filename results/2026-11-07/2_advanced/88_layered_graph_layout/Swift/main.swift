import Foundation
struct Model {
    let layer: [Int], width: [Int], chains: [[Int]], gaps: [[Segment]], upper: [[Int]], lower: [[Int]], initial: [[Int]]
}
func reachability(_ n: Int, _ edges: [(Int, Int)]) -> [[Bool]] {
    var reachable = Array(repeating: Array(repeating: false, count: n), count: n)
    for i in 0..<n {
        reachable[i][i] = true
    }
    for (a, b) in edges {
        reachable[a][b] = true
    }
    for k in 0..<n {
        for i in 0..<n {
            for j in 0..<n {
                reachable[i][j] = reachable[i][j] || reachable[i][k] && reachable[k][j]
            }
        }
    }
    return reachable
}
func analysis(_ graph: Graph) -> (Int, Int, Int, Int, [[Int]]) {
    let n = graph.nodes.count
    var incoming = Array(repeating: 0, count: n), outgoing = incoming
    for (a, b) in graph.edges {
        outgoing[a] += 1;
        incoming[b] += 1
    }
    let sources = (0..<n).filter {
        incoming[$0] == 0 && outgoing[$0] > 0
    }.count, sinks = (0..<n).filter {
        outgoing[$0] == 0 && incoming[$0] > 0
    }.count, isolated = (0..<n).filter {
        incoming[$0] == 0 && outgoing[$0] == 0
    }.count
    var visited: Set<Int> = [], components = 0
    for v in 0..<n where !visited.contains(v) {
        components += 1
        var stack = [v]
        while let a = stack.popLast() {
            if visited.insert(a).inserted {
                for (u, w) in graph.edges {
                    if u == a {
                        stack.append(w)
                    };
                    if w == a {
                        stack.append(u)
                    }
                }
            }
        }
    }
    let connected = reachability(n, graph.edges)
    var remaining = Set(0..<n), scc: [[Int]] = []
    while let v = remaining.min() {
        let group = remaining.filter {
            connected[v][$0] && connected[$0][v]
        }.sorted();
        remaining.subtract(group);
        if group.count > 1 {
            scc.append(group)
        }
    }
    return (sources, sinks, isolated, components, scc)
}
func buildModel(_ graph: Graph, _ heights: [Int], _ dag: [(Int, Int)], _ removed: [Bool]) -> Model {
    let n = graph.nodes.count, h = heights.max()!, raw = heights.map {
        h - $0
    }
    var used = Set(raw)
    for (i, edge) in dag.enumerated() where !removed[i] {
        used.formUnion((raw[edge.0] + 1)..<raw[edge.1])
    }
    let numbering = Dictionary(uniqueKeysWithValues: used.sorted().enumerated().map {
        ($0.element, $0.offset)
    })
    var layer = raw.map {
        numbering[$0]!
    }, width = graph.nodes.map {
        $0.1.count + 2
    }, chains = Array(repeating: [Int](), count: graph.edges.count)
    for (i, edge) in dag.enumerated() where !removed[i] {
        let (a, b) = edge
        var chain = [a]
        for l in (layer[a] + 1)..<layer[b] {
            chain.append(layer.count);
            layer.append(l);
            width.append(1)
        }
        chain.append(b);
        chains[i] = chain
    }
    var gaps = Array(repeating: [Segment](), count: max(0, used.count - 1)), upper = Array(repeating: [Int](), count: layer.count), lower = upper
    for (i, chain) in chains.enumerated() {
        if chain.count < 2 {
            continue
        }
        for j in 1..<chain.count {
            let p = chain[j - 1], q = chain[j]
            gaps[layer[p]].append(Segment(p: p, q: q, edge: i));
            upper[q].append(p);
            lower[p].append(q)
        }
    }
    var initial = Array(repeating: [Int](), count: used.count), visited = Array(repeating: false, count: layer.count)
    func visit(_ v: Int) {
        if visited[v] {
            return
        };
        visited[v] = true;
        initial[layer[v]].append(v);
        for w in lower[v] {
            visit(w)
        }
    }
    for v in 0..<n {
        visit(v)
    }
    return Model(layer: layer, width: width, chains: chains, gaps: gaps, upper: upper, lower: lower, initial: initial)
}
struct Reduction {
    let order: [[Int]], records: [String], csv: [String], initial: Int, swept: Int, run: Int, sweep: Int
}
func reduceCrossings(_ graph: Graph, _ model: Model) -> Reduction {
    let n = model.layer.count
    var random = graph.settings.integer("seed"), records: [String] = [], csv: [String] = [], adopted = model.initial
    var bestCount = Int.max, bestRun = 0, bestSweep = 0, initial = 0
    for run in 0...graph.settings.integer("restarts") {
        var order = model.initial
        if run > 0 {
            for i in order.indices {
                for j in (1..<order[i].count).reversed() {
                    random = 48271 * random % 2147483647;
                    order[i].swapAt(j, random % (j + 1))
                }
            }
        }
        let count = Crossing.total(model.gaps, order, n)
        if run == 0 {
            initial = count
        }
        var runCount = count, runSweep = 0, runOrder = order, history = [order], counts = [count]
        records.append("sweep \(run) 0 initial crossings \(count)");
        csv.append("\(graph.name),\(run),0,\(count)")
        let maximum = graph.settings.integer("sweeps")
        if maximum > 0 {
            for sweep in 1...maximum {
                let last = sweep - 1
                if counts[last] == 0 || last >= 2 && history[last] == history[last - 2] {
                    break
                }
                let old = Crossing.positions(order, n)
                let layers = sweep % 2 == 1 ? Array(1..<order.count) : Array((0..<max(0, order.count - 1)).reversed())
                let reference = sweep % 2 == 1 ? model.upper : model.lower
                for i in layers {
                    let positions = Crossing.positions(order, n)
                    func key(_ v: Int) -> (Int, Int) {
                        let values = reference[v].map {
                            positions[$0]
                        }.sorted()
                        return graph.settings.text("heuristic") == "median" ? (values[(values.count - 1) / 2] + values[values.count / 2], 1) : (values.reduce(0, +), values.count)
                    }
                    let moving = order[i].filter {
                        !reference[$0].isEmpty
                    }.sorted {
                        let a = key($0), b = key($1), x = a.0 * b.1, y = b.0 * a.1
                        return x == y ? positions[$0] < positions[$1] : x < y
                    }
                    var next = 0
                    for j in order[i].indices where !reference[order[i][j]].isEmpty {
                        order[i][j] = moving[next];
                        next += 1
                    }
                }
                var positions = Crossing.positions(order, n), swaps = 0
                let moved = (0..<n).filter {
                    positions[$0] != old[$0]
                }.count
                while true {
                    var changed = false
                    for i in order.indices {
                        for j in 0..<max(0, order[i].count - 1) {
                            let v = order[i][j], w = order[i][j + 1]
                            if Crossing.adjacent(v, w, model.upper, model.lower, positions) > Crossing.adjacent(w, v, model.upper, model.lower, positions) {
                                order[i].swapAt(j, j + 1);
                                positions[v] = j + 1;
                                positions[w] = j;
                                swaps += 1;
                                changed = true
                            }
                        }
                    }
                    if !changed {
                        break
                    }
                }
                let count = Crossing.total(model.gaps, order, n)
                history.append(order);
                counts.append(count)
                records.append("sweep \(run) \(sweep) \(sweep % 2 == 1 ? "down" : "up") moved \(moved) swaps \(swaps) crossings \(count)")
                csv.append("\(graph.name),\(run),\(sweep),\(count)")
                if count < runCount {
                    runCount = count;
                    runSweep = sweep;
                    runOrder = order
                }
            }
        }
        if runCount < bestCount {
            bestCount = runCount;
            bestRun = run;
            bestSweep = runSweep;
            adopted = runOrder
        }
    }
    records.append("best run \(bestRun) sweep \(bestSweep) crossings \(bestCount)")
    if graph.settings.on("sifting") {
        var round = 0
        while true {
            round += 1
            var moves = 0
            for v in 0..<n {
                let i = model.layer[v], old = adopted[i].firstIndex(of: v)!
                var base = adopted[i], costs: [Int] = []
                base.remove(at: old)
                for p in 0...base.count {
                    var row = base;
                    row.insert(v, at: p);
                    adopted[i] = row;
                    costs.append(Crossing.total(model.gaps, adopted, n))
                }
                let minimum = costs.min()!, position = costs[old] == minimum ? old : costs.firstIndex(of: minimum)!
                base.insert(v, at: position);
                adopted[i] = base
                if position != old {
                    moves += 1
                }
            }
            records.append("sift \(round) moves \(moves) crossings \(Crossing.total(model.gaps, adopted, n))")
            if moves == 0 {
                break
            }
        }
    }
    return Reduction(order: adopted, records: records, csv: csv, initial: initial, swept: bestCount, run: bestRun, sweep: bestSweep)
}
struct Geometry {
    let tracks: [Int], gaps: [Int], offsets: [[Int?]], thickness: [Int], starts: [Int], main: Int, secondary: Int
}
func geometry(_ graph: Graph, _ model: Model, _ order: [[Int]], _ coordinates: Coordinates) -> Geometry {
    let x = coordinates.x
    var tracks: [Int] = [], gaps: [Int] = [], offsets: [[Int?]] = []
    for segments in model.gaps {
        var counts: [Int: Int] = [:]
        for segment in segments where x[segment.p] != x[segment.q] {
            counts[segment.p, default: 0] += 1
        }
        var groups: [VertexPair: [Int]] = [:]
        for (k, segment) in segments.enumerated() where x[segment.p] != x[segment.q] {
            let key = counts[segment.p]! >= 2 ? VertexPair(0, segment.p) : VertexPair(1, segment.q)
            groups[key, default: []].append(k)
        }
        let buses = groups.map {
            key, members -> (Int, Int, Int, Int, [Int]) in
            let lo = members.map {
                min(x[segments[$0].p], x[segments[$0].q])
            }.min()!, hi = members.map {
                max(x[segments[$0].p], x[segments[$0].q])
            }.max()!
            return (lo, hi, key.a, x[key.b], members)
        }.sorted {
            ($0.0, $0.1, $0.2, $0.3) < ($1.0, $1.1, $1.2, $1.3)
        }
        var ends: [Int] = [], assignments = Array<Int?>(repeating: nil, count: segments.count)
        for (lo, hi, _, _, members) in buses {
            let track = ends.firstIndex {
                $0 + 1 < lo
            } ?? ends.count
            if track == ends.count {
                ends.append(hi)
            } else {
                ends[track] = hi
            }
            for k in members {
                assignments[k] = track + 1
            }
        }
        let gap = max(graph.settings.integer("layer_gap"), ends.count + 2)
        assignments = assignments.map {
            $0.map {
                $0 + (gap - 2 - ends.count) / 2
            }
        }
        tracks.append(ends.count);
        gaps.append(gap);
        offsets.append(assignments)
    }
    let vertical = ["TB", "BT"].contains(graph.settings.text("direction"))
    let thickness = order.map {
        row in vertical ? 1 : row.map {
            model.width[$0]
        }.max()!
    }
    var starts = Array(repeating: 0, count: order.count)
    for i in 1..<order.count {
        starts[i] = starts[i - 1] + thickness[i - 1] + gaps[i - 1]
    }
    return Geometry(tracks: tracks, gaps: gaps, offsets: offsets, thickness: thickness, starts: starts,
    main: starts.last! + thickness.last!, secondary: model.layer.indices.map {
        x[$0] + coordinates.right[$0]
    }.max()! + 1)
}
func shortestPath(_ graph: Graph, _ removed: [Bool]) -> [Int]? {
    guard let (start, goal) = graph.path else {
        return nil
    }
    var parent = Array<Int?>(repeating: nil, count: graph.nodes.count), visited = Array(repeating: false, count: graph.nodes.count), queue = [start], head = 0
    visited[start] = true
    while head < queue.count {
        let a = queue[head];
        head += 1
        let neighbors = graph.edges.enumerated().filter {
            !removed[$0.offset] && $0.element.0 == a
        }.map {
            $0.element.1
        }.sorted()
        for b in neighbors where !visited[b] {
            visited[b] = true;
            parent[b] = a;
            queue.append(b)
        }
    }
    if !visited[goal] {
        return nil
    }
    var path = [goal], current = goal
    while current != start {
        current = parent[current]!;
        path.append(current)
    }
    return Array(path.reversed())
}
struct Drawing {
    let canvas: Canvas, routes: [[Cell]], lengths: [Int], bends: [Int]
}
func draw(_ graph: Graph, _ model: Model, _ c: Coordinates, _ geo: Geometry, _ reversed: [Bool], _ removed: [Bool], _ path: [Int]?) -> Drawing {
    let direction = graph.settings.text("direction"), vertical = ["TB", "BT"].contains(direction), canvas = Canvas(geo.main, geo.secondary, direction)
    for v in model.layer.indices {
        let i = model.layer[v]
        if v >= graph.nodes.count {
            for j in 0..<geo.thickness[i] {
                canvas.line(geo.starts[i] + j, c.x[v], true)
            }
        }
        else if !vertical && !model.lower[v].isEmpty {
            for j in model.width[v]..<geo.thickness[i] {
                canvas.line(geo.starts[i] + j, c.x[v], true)
            }
        }
    }
    for (i, segments) in model.gaps.enumerated() {
        let g0 = geo.starts[i] + geo.thickness[i], gap = geo.gaps[i]
        for (k, segment) in segments.enumerated() {
            let p = c.x[segment.p], q = c.x[segment.q]
            if let offset = geo.offsets[i][k] {
                for j in 0..<offset {
                    canvas.line(g0 + j, p, true)
                }
                canvas.corner(g0 + offset, p);
                canvas.corner(g0 + offset, q)
                for x in (min(p, q) + 1)..<max(p, q) {
                    canvas.line(g0 + offset, x, false)
                }
                for j in (offset + 1)..<gap {
                    canvas.line(g0 + j, q, true)
                }
            } else {
                for j in 0..<gap {
                    canvas.line(g0 + j, p, true)
                }
            }
        }
    }
    var routes = Array(repeating: [Cell](), count: graph.edges.count), lengths = Array(repeating: 0, count: graph.edges.count), bends = lengths
    for (e, chain) in model.chains.enumerated() where !removed[e] {
        let a = chain[0], b = chain.last!, upper = (geo.starts[model.layer[a]] + (vertical ? 1 : model.width[a]), c.x[a]), lower = (geo.starts[model.layer[b]] - 1, c.x[b])
        var points = [upper]
        for j in 1..<chain.count {
            let p = chain[j - 1], q = chain[j], i = model.layer[p], k = model.gaps[i].firstIndex {
                $0.p == p && $0.q == q
            }!
            if let offset = geo.offsets[i][k] {
                let main = geo.starts[i] + geo.thickness[i] + offset;
                points += [(main, c.x[p]), (main, c.x[q])];
                bends[e] += 2
            }
        }
        points.append(lower)
        var mapped = points.map {
            canvas.map($0.0, $0.1)
        }
        if reversed[e] {
            mapped.reverse();
            canvas.arrow(upper.0, upper.1, true)
        } else {
            canvas.arrow(lower.0, lower.1, false)
        }
        lengths[e] = 1 + (1..<mapped.count).reduce(0) {
            $0 + abs(mapped[$1 - 1].row - mapped[$1].row) + abs(mapped[$1 - 1].column - mapped[$1].column)
        }
        routes[e] = mapped
    }
    let onPath = Set(path ?? [])
    if let path {
        for j in 1..<path.count {
            let e = graph.edges.firstIndex {
                $0.0 == path[j - 1] && $0.1 == path[j]
            }!
            for k in 1..<routes[e].count {
                let a = routes[e][k - 1], b = routes[e][k]
                if a.row == b.row {
                    for column in min(a.column, b.column)...max(a.column, b.column) {
                        canvas.highlight(a.row, column)
                    }
                }
                else {
                    for row in min(a.row, b.row)...max(a.row, b.row) {
                        canvas.highlight(row, a.column)
                    }
                }
            }
        }
    }
    for v in graph.nodes.indices {
        let i = model.layer[v], label = (onPath.contains(v) ? "{" : "[") + graph.nodes[v].1 + (onPath.contains(v) ? "}" : "]"), cell: Cell
        if vertical {
            cell = canvas.map(geo.starts[i], c.x[v] - c.left[v])
        }
        else if direction == "LR" {
            cell = Cell(row: c.x[v], column: geo.starts[i])
        }
        else {
            cell = Cell(row: c.x[v], column: geo.main - geo.starts[i] - model.width[v])
        }
        canvas.label(cell.row, cell.column, label)
    }
    return Drawing(canvas: canvas, routes: routes, lengths: lengths, bends: bends)
}
struct Processed {
    let layout: [String], stats: [String], csv: [String], drawings: [String], totals: [Int]
}
func process(_ graph: Graph) -> Processed {
    let n = graph.nodes.count
    func id(_ v: Int) -> String {
        String(graph.nodes[v].0)
    }
    func edgeName(_ e: Int) -> String {
        id(graph.edges[e].0) + "->" + id(graph.edges[e].1)
    }
    let (sources, sinks, isolated, components, scc) = analysis(graph), sequence = AcyclicLayering.sequence(n, graph.edges)
    var position = Array(repeating: 0, count: n)
    for (i, v) in sequence.enumerated() {
        position[v] = i
    }
    let reversed = graph.edges.map {
        position[$0.0] > position[$0.1]
    }
    let dag = graph.edges.enumerated().map {
        i, edge in reversed[i] ? (edge.1, edge.0) : edge
    }
    let reachable = reachability(n, dag)
    let removed = dag.enumerated().map {
        i, edge in graph.settings.on("reduce") && !reversed[i] && dag.contains {
            $0.0 == edge.0 && $0.1 != edge.1 && reachable[$0.1][edge.1]
        }
    }
    let drawn = dag.enumerated().filter {
        !removed[$0.offset]
    }.map {
        $0.element
    }
    let layering = AcyclicLayering.assign(n, drawn, graph.settings.text("layering") == "coffman", graph.settings.integer("width"), graph.settings.on("promotion"))
    let model = buildModel(graph, layering.heights, dag, removed), reduced = reduceCrossings(graph, model)
    let coordinates = Coordinates.assign(n, reduced.order, model.layer, model.upper, model.lower, model.width, ["TB", "BT"].contains(graph.settings.text("direction")), graph.settings.integer("node_sep"), graph.settings.integer("dummy_sep"))
    let geo = geometry(graph, model, reduced.order, coordinates), path = shortestPath(graph, removed), drawing = draw(graph, model, coordinates, geo, reversed, removed, path), canvas = drawing.canvas, c = coordinates
    let vertices = model.layer.count
    func name(_ v: Int) -> String {
        v < n ? id(v) : "d\(v - n + 1)"
    }
    let positions = Crossing.positions(reduced.order, vertices)
    let counts = model.gaps.enumerated().map {
        Crossing.count($0.element, positions, reduced.order[$0.offset + 1].count)
    }, finalCount = counts.reduce(0, +), brute = model.gaps.reduce(0) {
        $0 + Crossing.brute($1, positions)
    }
    var edgeCrossings = Array(repeating: 0, count: graph.edges.count)
    for gap in model.gaps {
        for i in gap.indices {
            for j in (i + 1)..<gap.count where Crossing.crosses(gap[i], gap[j], positions) {
                edgeCrossings[gap[i].edge] += 1;
                edgeCrossings[gap[j].edge] += 1
            }
        }
    }
    let settings = zip(Settings.names, graph.settings.values).map {
        "\($0.0)=\($0.1)"
    }.joined(separator: " ")
    var layout = ["graph \(graph.name)", "settings \(settings)", "acyclic " + sequence.map(id).joined(separator: " ")]
    if graph.settings.text("layering") == "coffman" {
        layout.append("labels " + (0..<n).map {
            "\(id($0)):\(layering.labels[$0])"
        }.joined(separator: " "))
    }
    for (round, v, diff) in layering.promotions {
        layout.append("promote \(round) \(id(v)) \(diff)")
    }
    layout += reduced.records
    for (i, row) in reduced.order.enumerated() {
        let start = geo.starts[i], end = start + geo.thickness[i] - 1
        let (bandLo, bandHi) = ["BT", "RL"].contains(graph.settings.text("direction")) ? (geo.main - 1 - end, geo.main - 1 - start) : (start, end)
        let lo = row.map {
            c.x[$0] - c.left[$0]
        }.min()!, hi = row.map {
            c.x[$0] + c.right[$0]
        }.max()!
        layout.append("layer \(i) band \(bandLo) \(bandHi) extent \(lo) \(hi) : " + row.map {
            "\(name($0))@\(c.x[$0])"
        }.joined(separator: " "))
    }
    for i in model.gaps.indices {
        layout.append("between \(i) \(i + 1) segments \(model.gaps[i].count) crossings \(counts[i]) tracks \(geo.tracks[i]) gap \(geo.gaps[i])")
    }
    let variants = ["ul", "ur", "dl", "dr"], variantText = (0..<4).map {
        "\(variants[$0])=\(c.blocks[$0])/\(c.widths[$0])"
    }.joined(separator: " ")
    layout.append("bk conflicts \(c.conflicts) \(variantText) smallest \(variants[c.smallest])")
    for row in reduced.order {
        for v in row {
            layout.append("vertex \(name(v)) layer \(model.layer[v]) pos \(positions[v]) ul \(c.aligned[0][v]) ur \(c.aligned[1][v]) dl \(c.aligned[2][v]) dr \(c.aligned[3][v]) x \(c.x[v])")
        }
    }
    for e in graph.edges.indices {
        let (a, b) = graph.edges[e]
        if removed[e] {
            layout.append("edge \(id(a)) \(id(b)) transitive")
        }
        else {
            let chain = reversed[e] ? Array(model.chains[e].reversed()) : model.chains[e]
            let pathText = chain.map {
                String(c.x[$0])
            }.joined(separator: " "), route = drawing.routes[e].map {
                "\($0.row),\($0.column)"
            }.joined(separator: " ")
            layout.append("edge \(id(a)) \(id(b))\(reversed[e] ? " reversed" : "") span \(chain.count - 1) crossings \(edgeCrossings[e]) bends \(drawing.bends[e]) path \(pathText) route \(route)")
        }
    }
    layout.append("end")
    var stats = ["graph \(graph.name)", "nodes \(n) edges \(graph.edges.count) self_loops \(graph.loops) duplicates \(graph.duplicates)", "sources \(sources) sinks \(sinks) isolated \(isolated) components \(components)"]
    for component in scc {
        stats.append("scc " + component.map(id).joined(separator: " "))
    }
    for (label, flags) in [("reversed", reversed), ("transitive", removed)] {
        let names = graph.edges.indices.filter {
            flags[$0]
        }.map(edgeName)
        stats.append("\(label) \(names.count)" + (names.isEmpty ? "" : " " + names.joined(separator: " ")))
    }
    let maxNodes = reduced.order.map {
        $0.filter {
            $0 < n
        }.count
    }.max()!, maxVertices = reduced.order.map(\.count).max()!
    stats.append("layers \(reduced.order.count) max_nodes \(maxNodes) max_vertices \(maxVertices)")
    stats.append(graph.settings.on("promotion") ? "promotion rounds \(layering.rounds) accepted \(layering.promotions.count) dummies_before \(layering.before)" : "promotion off")
    var spans: [Int: Int] = [:]
    for chain in model.chains where !chain.isEmpty {
        spans[chain.count - 1, default: 0] += 1
    }
    let spanTotal = model.chains.filter {
        !$0.isEmpty
    }.reduce(0) {
        $0 + $1.count - 1
    }
    stats.append("dummies \(vertices - n) span_total \(spanTotal) span_max \(spans.keys.max() ?? 0)")
    stats.append("spans " + (spans.isEmpty ? "none" : spans.keys.sorted().map {
        "\($0):\(spans[$0]!)"
    }.joined(separator: " ")))
    let long = model.chains.filter {
        $0.count >= 3
    }, vertical = long.filter {
        chain in chain.dropFirst().dropLast().allSatisfy {
            c.x[$0] == c.x[chain[1]]
        }
    }.count
    stats.append("long_edges \(long.count) vertical \(vertical)")
    stats.append("crossings initial \(reduced.initial) swept \(reduced.swept) best_run \(reduced.run) best_sweep \(reduced.sweep) final \(finalCount) brute \(brute)")
    let segments = model.gaps.flatMap {
        $0
    }, straight = segments.filter {
        c.x[$0.p] == c.x[$0.q]
    }.count, offset = segments.reduce(0) {
        $0 + abs(c.x[$1.p] - c.x[$1.q])
    }
    stats.append("segments \(segments.count) straight \(straight) bent \(segments.count - straight) offset \(offset)")
    let longest = graph.edges.indices.filter {
        !removed[$0]
    }.min {
        drawing.lengths[$0] == drawing.lengths[$1] ? $0 < $1 : drawing.lengths[$0] > drawing.lengths[$1]
    }
    stats.append("routes length \(drawing.lengths.reduce(0, +)) bends \(drawing.bends.reduce(0, +))" + (longest.map {
        " longest \(edgeName($0)) \(drawing.lengths[$0])"
    } ?? ""))
    stats.append("canvas width \(canvas.columns) height \(canvas.rows) crossing_cells \(canvas.crossings())")
    if let (a, b) = graph.path {
        stats.append(path.map {
            "path \(id(a)) \(id(b)) hops \($0.count - 1) : " + $0.map(id).joined(separator: " ")
        } ?? "path \(id(a)) \(id(b)) none")
    }
    stats.append("end")
    return Processed(layout: layout, stats: stats, csv: reduced.csv, drawings: ["graph \(graph.name) \(canvas.columns)x\(canvas.rows)"] + canvas.report(), totals: [n, graph.edges.count, vertices - n, reduced.initial, finalCount])
}
func write(_ file: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + file, atomically: false, encoding: .ascii)
}
func runProgram() {
    let graphs = GraphIO.read()
    var layout: [String] = [], stats: [String] = [], drawings: [String] = [], csv = ["graph,run,sweep,crossings"], totals = [0, 0, 0, 0, 0], errors = 0
    for graph in graphs {
        if !drawings.isEmpty {
            drawings.append("")
        }
        if let (error, line) = graph.error {
            errors += 1
            let block = ["graph \(graph.name)", "error \(error) line \(line)", "end"]
            layout += block;
            stats += block;
            drawings.append("graph \(graph.name) error \(error)")
        } else {
            let output = process(graph)
            layout += output.layout;
            stats += output.stats;
            csv += output.csv;
            drawings += output.drawings
            for i in 0..<5 {
                totals[i] += output.totals[i]
            }
        }
    }
    stats.append("summary graphs \(graphs.count) laid_out \(graphs.count - errors) errors \(errors) nodes \(totals[0]) edges \(totals[1]) dummies \(totals[2]) crossings_initial \(totals[3]) crossings_final \(totals[4])")
    write("layout.txt", layout);
    write("stats.txt", stats);
    write("crossings.csv", csv);
    write("drawings.txt", drawings)
}
runProgram()
