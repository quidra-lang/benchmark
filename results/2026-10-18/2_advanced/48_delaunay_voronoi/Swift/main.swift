import Foundation

let outputSections: [(String, [String])] = [
    ("triangulation.txt", ["input", "summary", "insertions", "triangles", "edges", "hull", "convex_layers", "quality"]),
    ("voronoi.txt", ["vertices", "voronoi_edges", "cells"]),
    ("derived.txt", ["nearest", "components", "mst", "proximity", "degrees", "empty_circle", "extent", "spanner", "alpha", "sites", "queries"]),
    ("plot.txt", ["delaunay_plot", "voronoi_plot"])
]

func words<S: Sequence>(_ values: S) -> String where S.Element == Int { values.map(String.init).joined(separator: " ") }
func words(_ edge: Edge) -> String { "\(edge.first) \(edge.second)" }
func words(_ point: Point) -> String { "\(point.x) \(point.y)" }
func real(_ value: Double) -> String {
    let text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.000" ? "0.000" : text
}
func triangleNumber(_ value: Int?) -> String { value.map(String.init) ?? "-" }
func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

struct Settings {
    var width = 61
    var height = 31
    var plotLayers = ["edges", "hull", "sites"]
    var sections = ["summary"]
    var alpha: [Int] = []
    var queries: [String] = []
}

func readLines(_ path: String) throws -> [String] { Array(try String(contentsOfFile: path, encoding: .ascii).components(separatedBy: "\n").dropLast()) }

func integerWord(_ word: String) -> Bool {
    var bytes = Array(word.utf8)
    if bytes.first == 45 { bytes.removeFirst() }
    return !bytes.isEmpty && bytes.allSatisfy { $0 >= 48 && $0 <= 57 }
}

func readPoints() throws -> (points: [Point], lineCount: Int, rejected: [String]) {
    let lines = try readLines("input/points.txt")
    var points = [Point(x: 0, y: 0)], accepted: [Point: Int] = [:], rejected: [String] = []
    for (index, line) in lines.enumerated() {
        if line.isEmpty || line.hasPrefix("#") { continue }
        let fields = line.components(separatedBy: " ")
        if fields.count != 2 || !fields.allSatisfy(integerWord) { rejected.append("reject \(index + 1) format"); continue }
        let point = Point(x: Int(fields[0])!, y: Int(fields[1])!)
        if point.x < 0 || point.x > 1000 || point.y < 0 || point.y > 1000 { rejected.append("reject \(index + 1) range"); continue }
        if let earlier = accepted[point] { rejected.append("reject \(index + 1) duplicate \(earlier)"); continue }
        accepted[point] = points.count
        points.append(point)
    }
    return (points, lines.count, rejected)
}

func readSettings() throws -> Settings {
    var params = Settings()
    for line in try readLines("input/params.txt") where !line.isEmpty && !line.hasPrefix("#") {
        let fields = line.components(separatedBy: " "), values = Array(fields.dropFirst())
        switch fields[0] {
        case "plot": params.width = Int(values[0])!; params.height = Int(values[1])!
        case "plot_layers": params.plotLayers = values
        case "sections": params.sections = values
        case "alpha": params.alpha = values.map { Int($0)! }
        default: params.queries.append(values.joined(separator: " "))
        }
    }
    return params
}

struct VoronoiCell {
    let vertices: [Int]
    let clip: Double
    let area: Double?
    let incoming: Point?
    let outgoing: Point?
}

final class Report {
    let points: [Point]
    let lineCount: Int
    let rejected: [String]
    let params: Settings
    let mesh: Triangulation
    let siteAt: [Point: Int]
    var n: Int { points.count - 1 }
    var t: Int { triangles.count - 1 }
    var e: Int { edges.count }
    var h: Int { hull.count }
    var insertions: [Insertion] = []
    var triangles = [Triangle(0, 0, 0)]
    var edgeTriangles: [Edge: Int] = [:]
    var edges: [Edge] = []
    var length2: [Edge: Int] = [:]
    var hullNext: [Int: Int] = [:]
    var hullPrevious: [Int: Int] = [:]
    var hull: [Int] = []
    var hullEdges: [Edge] = []
    var hullPerimeter = 0.0
    var hullArea2 = 0
    var neighbors: [[Int]] = []
    var degree: [Int] = []
    var area2 = [0]
    var kind = [""]
    var minAngles = [0.0]
    var maxAngles = [0.0]
    var angleBins = Array(repeating: 0, count: 6)
    var minAngleTotal = 0.0
    var minimumTriangle = 1
    var maximumTriangle = 1
    var centers = [Center(x: 0, y: 0, denominator: 1)]
    var radius2 = [0.0]
    var positions = [""]
    var duals: [Edge: String] = [:]
    var cells: [VoronoiCell?] = [nil]
    var cellTotal = 0.0
    var clipTotal = 0.0
    var largestCell: Int?
    var nearest: [Int] = []
    var mutualPairs: [Edge] = []
    var closestPair = Edge(1, 2)
    var components: [[Int]] = []
    var componentNumber: [Int] = []
    var componentPairs: [Edge] = []
    var nnEdges = Set<Edge>()
    var mst: [Edge] = []
    var mstSet = Set<Edge>()
    var mstLength = 0.0
    var gabriel = Set<Edge>()
    var rng = Set<Edge>()
    var graphDegrees: [String: [Int]] = [:]
    var emptyCandidates: [Int] = []
    var emptyVertex: Int?
    var diameter = Edge(1, 2)
    var diameter2 = -1
    var width = Double.infinity
    var widthEdge = Edge(1, 2)
    var enclosingCenter = Center(x: 0, y: 0, denominator: 1)
    var enclosingRadius2 = 0.0
    var enclosingSites: [Int] = []
    var layers: [[Int]] = []
    var depth: [Int] = []
    var shortestPaths: [Int: ShortestPaths] = [:]
    var pairCount: Int { n * (n - 1) / 2 }
    var maximumStretch = -1.0
    var stretchPair = Edge(1, 2)
    var stretchLength = 0.0
    var stretchDistance = 0.0
    var meanStretch = 0.0
    var alphaResults: [String] = []
    var delaunayPlot: [String] = []
    var voronoiPlot: [String] = []

    init(_ points: [Point], _ lineCount: Int, _ rejected: [String], _ params: Settings) {
        self.points = points
        self.lineCount = lineCount
        self.rejected = rejected
        self.params = params
        mesh = Triangulation(points)
        siteAt = Dictionary(uniqueKeysWithValues: points.indices.dropFirst().map { (points[$0], $0) })
    }

    func analyze() {
        buildTriangulation()
        analyzeTriangles()
        analyzeVoronoi()
        analyzeProximity()
        analyzeExtent()
        analyzeLayers()
        analyzeSpanner()
        analyzeAlpha()
        drawPlots()
    }

    func buildTriangulation() {
        if n >= 4 { for site in 4...n { insertions.append(mesh.insert(site)) } }
        triangles += mesh.triangles()
        for (number, triangle) in triangles.enumerated().dropFirst() { for edge in triangle.edges { edgeTriangles[edge] = number } }
        edges = Set(mesh.directed.keys.map { $0.undirected }).sorted()
        length2 = Dictionary(uniqueKeysWithValues: edges.map { ($0, d2(points[$0.first], points[$0.second])) })
        hullNext = Dictionary(uniqueKeysWithValues: mesh.hullEdges().map { ($0.first, $0.second) })
        hullPrevious = Dictionary(uniqueKeysWithValues: hullNext.map { ($0.value, $0.key) })
        let start = hullNext.keys.min()!
        hull = [start]
        while hullNext[hull.last!]! != start { hull.append(hullNext[hull.last!]!) }
        hullEdges = hull.indices.map { Edge(hull[$0], hull[($0 + 1) % hull.count]) }
        for edge in hullEdges {
            let first = points[edge.first], second = points[edge.second]
            hullPerimeter = hullPerimeter + sqrt(Double(d2(first, second)))
            hullArea2 += first.x * second.y - second.x * first.y
        }
        var adjacent = Array(repeating: Set<Int>(), count: n + 1)
        for edge in edges { adjacent[edge.first].insert(edge.second); adjacent[edge.second].insert(edge.first) }
        neighbors = [[]] + (1...n).map { neighborOrder($0, adjacent[$0], mesh.directed, hullNext) }
        degree = neighbors.map { $0.count }
    }

    func analyzeTriangles() {
        for triangle in triangles.dropFirst() {
            let a = points[triangle.a], b = points[triangle.b], c = points[triangle.c]
            let area = orient(a, b, c), products = [dot(a, b, c), dot(b, c, a), dot(c, a, b)], lengths = [d2(b, c), d2(c, a), d2(a, b)]
            let kind = products.contains(0) ? "right" : products.min()! < 0 ? "obtuse" : "acute"
            let shortest = lengths.firstIndex(of: lengths.min()!)!, longest = lengths.firstIndex(of: lengths.max()!)!
            let minimum = atan2(Double(area), Double(products[shortest])) * 180 / Double.pi
            let maximum = atan2(Double(area), Double(products[longest])) * 180 / Double.pi
            area2.append(area); self.kind.append(kind); minAngles.append(minimum); maxAngles.append(maximum)
            minAngleTotal = minAngleTotal + minimum
            angleBins[Int(floor(minimum / 10))] += 1
        }
        for number in 2..<triangles.count {
            if minAngles[number] < minAngles[minimumTriangle] { minimumTriangle = number }
            if maxAngles[number] > maxAngles[maximumTriangle] { maximumTriangle = number }
        }
    }

    func analyzeVoronoi() {
        for triangle in triangles.dropFirst() {
            let a = points[triangle.a], b = points[triangle.b], c = points[triangle.c]
            let center = circumcenter(a, b, c)
            centers.append(center); radius2.append(squaredRadius(a, b, c)); positions.append(position(center, points, hull))
        }
        for edge in edges {
            if let left = edgeTriangles[edge], let right = edgeTriangles[edge.reversed] { duals[edge] = "segment \(left) \(right)" }
            else {
                let direction = edgeTriangles[edge] != nil ? edge : edge.reversed
                let normal = outward(points, direction.first, direction.second)
                duals[edge] = "ray \(edgeTriangles[direction]!) \(words(normal))"
            }
        }
        for site in 1...n {
            let order = neighbors[site], vertices = order.compactMap { edgeTriangles[Edge(site, $0)] }
            let clip = clippedArea(points, site, order)
            if let next = hullNext[site] {
                cells.append(VoronoiCell(vertices: vertices, clip: clip, area: nil, incoming: outward(points, site, next), outgoing: outward(points, hullPrevious[site]!, site)))
            } else {
                let area = boundedArea(points[site], vertices.map { centers[$0] })
                cells.append(VoronoiCell(vertices: vertices, clip: clip, area: area, incoming: nil, outgoing: nil))
                cellTotal = cellTotal + area
                if largestCell == nil || area > cells[largestCell!]!.area! { largestCell = site }
            }
            clipTotal = clipTotal + clip
        }
    }

    func analyzeProximity() {
        nearest = nearestNeighbors(points, neighbors)
        mutualPairs = (1...n).filter { $0 < nearest[$0] && nearest[nearest[$0]] == $0 }.map { Edge($0, nearest[$0]) }
        closestPair = edges.min { length2[$0]! == length2[$1]! ? $0 < $1 : length2[$0]! < length2[$1]! }!
        components = nearestComponents(nearest)
        componentNumber = Array(repeating: 0, count: n + 1)
        for (index, sites) in components.enumerated() {
            for site in sites { componentNumber[site] = index + 1 }
            let site = sites.first { $0 < nearest[$0] && nearest[nearest[$0]] == $0 }!
            componentPairs.append(Edge(site, nearest[site]))
        }
        nnEdges = Set((1...n).map { Edge($0, nearest[$0]).undirected })
        mst = kruskal(points, edges)
        mstSet = Set(mst)
        for edge in mst { mstLength = mstLength + sqrt(Double(length2[edge]!)) }
        gabriel = Set(edges.filter { isGabriel(points, $0, mesh.directed) })
        rng = Set(edges.filter { isRelativeNeighbor(points, $0) })
        for (name, graph) in [("gg", Array(gabriel)), ("rng", Array(rng)), ("mst", mst)] {
            var degrees = Array(repeating: 0, count: n + 1)
            for edge in graph { degrees[edge.first] += 1; degrees[edge.second] += 1 }
            graphDegrees[name] = degrees
        }
    }

    func circleRelation(_ support: [Int], _ site: Int) -> Int {
        if support.count == 1 { return support[0] == site ? 0 : -1 }
        if support.count == 2 { return -dot(points[site], points[support[0]], points[support[1]]) }
        return incircle(points[support[0]], points[support[1]], points[support[2]], points[site])
    }

    func circleOrder(_ a: Int, _ b: Int, _ c: Int) -> [Int] { orient(points[a], points[b], points[c]) > 0 ? [a, b, c] : [a, c, b] }

    func enclosingCircle() {
        var support: [Int] = []
        for (i, first) in hull.enumerated() {
            if !support.isEmpty && circleRelation(support, first) >= 0 { continue }
            support = [first]
            for j in 0..<i {
                let second = hull[j]
                if circleRelation(support, second) >= 0 { continue }
                support = [first, second]
                for k in 0..<j where circleRelation(support, hull[k]) < 0 { support = circleOrder(first, second, hull[k]) }
            }
        }
        let boundary = (1...n).filter { circleRelation(support, $0) == 0 }
        var diameter: Edge?
        for (offset, first) in boundary.enumerated() {
            for second in boundary.dropFirst(offset + 1) where boundary.allSatisfy({ dot(points[$0], points[first], points[second]) == 0 }) { diameter = Edge(first, second); break }
            if diameter != nil { break }
        }
        if let diameter {
            let a = points[diameter.first], b = points[diameter.second]
            enclosingCenter = Center(x: a.x + b.x, y: a.y + b.y, denominator: 2)
            enclosingRadius2 = Double(d2(a, b)) / 4
        } else {
            let ordered = circleOrder(boundary[0], boundary[1], boundary[2])
            let a = points[ordered[0]], b = points[ordered[1]], c = points[ordered[2]]
            enclosingCenter = circumcenter(a, b, c)
            enclosingRadius2 = squaredRadius(a, b, c)
        }
        enclosingSites = boundary
    }

    func analyzeExtent() {
        emptyCandidates = (1...t).filter { positions[$0] == "inside" }
        for number in emptyCandidates where emptyVertex == nil || radius2[number] > radius2[emptyVertex!] { emptyVertex = number }
        for first in 1..<n {
            for second in (first + 1)...n {
                let length = d2(points[first], points[second])
                if length > diameter2 { diameter = Edge(first, second); diameter2 = length }
            }
        }
        for edge in hullEdges {
            let maximum = hull.map { orient(points[edge.first], points[edge.second], points[$0]) }.max()!
            let candidate = Double(maximum) / sqrt(Double(d2(points[edge.first], points[edge.second])))
            if candidate < width { width = candidate; widthEdge = edge }
        }
        enclosingCircle()
    }

    func analyzeLayers() {
        var remaining = Set(1...n)
        depth = Array(repeating: 0, count: n + 1)
        while !remaining.isEmpty {
            var layer: [Int]
            if remaining.count <= 2 { layer = remaining.sorted() }
            else {
                let ordered = remaining.sorted { points[$0] < points[$1] }
                func halfHull<S: Sequence>(_ sequence: S) -> [Int] where S.Element == Int {
                    var half: [Int] = []
                    for site in sequence {
                        while half.count >= 2 && orient(points[half[half.count - 2]], points[half.last!], points[site]) <= 0 { half.removeLast() }
                        half.append(site)
                    }
                    return Array(half.dropLast())
                }
                layer = halfHull(ordered) + halfHull(ordered.reversed())
                let start = layer.firstIndex(of: layer.min()!)!
                layer = Array(layer[start...]) + Array(layer[..<start])
            }
            layers.append(layer)
            for site in layer { depth[site] = layers.count }
            remaining.subtract(layer)
        }
    }

    func shortestFrom(_ site: Int) -> ShortestPaths {
        if let paths = shortestPaths[site] { return paths }
        let paths = dijkstra(points, neighbors, site)
        shortestPaths[site] = paths
        return paths
    }

    func analyzeSpanner() {
        var total = 0.0
        for first in 1..<n {
            let distances = shortestFrom(first).distances
            for second in (first + 1)...n {
                let length = distances[second], distance = sqrt(Double(d2(points[first], points[second]))), stretch = length / distance
                total = total + stretch
                if stretch > maximumStretch { maximumStretch = stretch; stretchPair = Edge(first, second); stretchLength = length; stretchDistance = distance }
            }
        }
        meanStretch = total / Double(pairCount)
    }

    func analyzeAlpha() {
        for alpha in params.alpha {
            let selected = (1...t).filter { radius2[$0] <= Double(alpha) }
            var incidence: [Edge: Int] = [:], area = 0
            for number in selected {
                area += area2[number]
                for edge in triangles[number].edges { incidence[edge.undirected, default: 0] += 1 }
            }
            var edges = Set(incidence.keys)
            for edge in gabriel where length2[edge]! <= 4 * alpha { edges.insert(edge) }
            let sets = DisjointSets(n)
            var incident = Set<Int>()
            for edge in edges.sorted() { sets.union(edge.first, edge.second); incident.insert(edge.first); incident.insert(edge.second) }
            let boundary = incidence.values.filter { $0 == 1 }.count, dangling = edges.filter { incidence[$0, default: 0] == 0 }.count
            alphaResults.append("alpha \(alpha) triangles \(selected.count) edges \(edges.count) boundary \(boundary) dangling \(dangling) isolated \(n - incident.count) components \(sets.count) holes \(sets.count - (n - edges.count + selected.count)) area2 \(area)")
        }
    }

    func locateQuery(_ query: Point) -> String {
        let nearest = (1...n).min { d2(points[$0], query) == d2(points[$1], query) ? $0 < $1 : d2(points[$0], query) < d2(points[$1], query) }!
        var location = "outside"
        if let site = siteAt[query] { location = "vertex \(site)" }
        else if let edge = edges.first(where: { orient(points[$0.first], points[$0.second], query) == 0 && dot(query, points[$0.first], points[$0.second]) < 0 }) { location = "edge \(words(edge))" }
        else if let triangle = triangles.dropFirst().first(where: { $0.edges.allSatisfy { orient(points[$0.first], points[$0.second], query) > 0 } }) { location = "triangle \(words(triangle.sites))" }
        return "\(location) nearest \(nearest) d2 \(d2(points[nearest], query))"
    }

    func walkQuery(_ query: Point) -> String {
        let walk = mesh.visibilityWalk(query, triangles, edgeTriangles)
        let stopping = walk.outside.map { "outside " + words($0) } ?? "triangle \(walk.path.last!)"
        return "steps \(walk.path.count - 1) \(stopping) path \(words(walk.path))"
    }

    func naturalQuery(_ query: Point) -> String {
        let selected = triangles.dropFirst().filter { incircle(points[$0.a], points[$0.b], points[$0.c], query) > 0 }
        let sites = Set(selected.flatMap { $0.sites }).sorted()
        return "triangles \(selected.count) sites \(sites.isEmpty ? "-" : words(sites))"
    }

    func pathQuery(_ first: Int, _ second: Int) -> String {
        let shortest = shortestFrom(first)
        var path = [second]
        while path.last! != first { path.append(shortest.previous[path.last!]) }
        path.reverse()
        let length = shortest.distances[second]
        let stretch = first == second ? "-" : real(length / sqrt(Double(d2(points[first], points[second]))))
        return "length \(real(length)) stretch \(stretch) hops \(path.count - 1) sites \(words(path))"
    }

    func edgeQuery(_ first: Int, _ second: Int) -> String {
        let edge = Edge(first, second).undirected
        if let length = length2[edge] { return "delaunay len2 \(length) gabriel \(yesNo(gabriel.contains(edge))) rng \(yesNo(rng.contains(edge))) mst \(yesNo(mstSet.contains(edge))) dual \(duals[edge]!)" }
        let a = points[first], b = points[second]
        let crossings = edges.filter { edge in
            let p = points[edge.first], q = points[edge.second]
            return orient(a, b, p) * orient(a, b, q) < 0 && orient(p, q, a) * orient(p, q, b) < 0
        }
        return "missing crossings \(crossings.count)" + (crossings.isEmpty ? "" : " " + crossings.map { "\($0.first)-\($0.second)" }.joined(separator: " "))
    }

    func answerQuery(_ query: String) -> String {
        let fields = query.components(separatedBy: " "), name = fields[0], values = fields.dropFirst().map { Int($0)! }
        if ["route", "path", "neighbors", "edge"].contains(name) {
            if values.contains(where: { $0 < 1 || $0 > n }) { return query + " error unknown_site" }
            if name == "edge" && values[0] == values[1] { return query + " error same_site" }
        }
        let answer: String
        switch name {
        case "locate": answer = locateQuery(Point(x: values[0], y: values[1]))
        case "walk": answer = walkQuery(Point(x: values[0], y: values[1]))
        case "natural": answer = naturalQuery(Point(x: values[0], y: values[1]))
        case "route":
            let route = greedyRoute(points, neighbors, values[0], values[1])
            answer = "hops \(route.path.count - 1) length \(real(route.length)) path \(words(route.path))"
        case "path": answer = pathQuery(values[0], values[1])
        case "neighbors": answer = "degree \(degree[values[0]]) sites \(words(neighbors[values[0]]))"
        default: answer = edgeQuery(values[0], values[1])
        }
        return query + " " + answer
    }

    func drawPlots() {
        var canvas = Canvas(params.width, params.height)
        for layer in params.plotLayers {
            if layer == "sites" { for point in points.dropFirst() { canvas.mark(point, "o") } }
            else if layer == "circle" { if let vertex = emptyVertex { canvas.mark(centers[vertex], "@") } }
            else {
                let graph: [Edge] = layer == "edges" ? edges : layer == "mst" ? mst : hullEdges
                let character: Character = layer == "edges" ? "." : layer == "mst" ? "*" : "#"
                for edge in graph { canvas.line(points[edge.first], points[edge.second], character) }
            }
        }
        delaunayPlot = canvas.framed()
        canvas = Canvas(params.width, params.height)
        canvas.drawVoronoi(points)
        voronoiPlot = canvas.framed()
    }

    func summarySection() -> [String] {
        var maximum = "max_flips none"
        if var best = insertions.first {
            for insertion in insertions.dropFirst() where insertion.flips > best.flips { best = insertion }
            maximum = "max_flips \(best.site) \(best.flips)"
        }
        return ["sites \(n)", "triangles \(t)", "edges \(e)", "hull_vertices \(h)", "interior_sites \(n - h)", "euler \(n - e + t)",
                "flips \(insertions.reduce(0) { $0 + $1.flips })", "outside_insertions \(insertions.filter { $0.containing == nil }.count)", maximum,
                "acute \(kind.filter { $0 == "acute" }.count)", "right \(kind.filter { $0 == "right" }.count)", "obtuse \(kind.filter { $0 == "obtuse" }.count)"]
    }

    func cellsSection() -> [String] {
        var lines = ["bounded \(n - h)", "unbounded \(h)", "total_area \(real(cellTotal))", "clip_total \(real(clipTotal))"]
        if let largest = largestCell { lines.append("largest \(largest) area \(real(cells[largest]!.area!))") } else { lines.append("largest none") }
        for site in 1...n {
            let cell = cells[site]!, vertices = words(cell.vertices), count = cell.vertices.count
            if let area = cell.area {
                lines.append("cell \(site) bounded \(count) area \(real(area)) clip \(real(cell.clip)) vertices \(vertices)")
            } else {
                lines.append("cell \(site) unbounded \(count) clip \(real(cell.clip)) from \(words(cell.incoming!)) vertices \(vertices) to \(words(cell.outgoing!))")
            }
        }
        return lines
    }

    func section(_ name: String) -> [String] {
        switch name {
        case "input": return ["lines \(lineCount)", "accepted \(n)", "rejected \(rejected.count)"] + rejected
        case "summary": return summarySection()
        case "insertions":
            return ["init \(words(mesh.initial.sites))"] + insertions.map { insertion in
                let description = insertion.containing.map { "inside " + words($0.sites) } ?? "outside \(insertion.visible)"
                return "insert \(insertion.site) \(description) flips \(insertion.flips) triangles \(insertion.triangles) hull \(insertion.hull)"
            }
        case "triangles":
            return (1...t).map { number in
                let triangle = triangles[number]
                let adjacent = [Edge(triangle.c, triangle.b), Edge(triangle.a, triangle.c), Edge(triangle.b, triangle.a)].map { triangleNumber(edgeTriangles[$0]) }.joined(separator: " ")
                return "tri \(number) \(words(triangle.sites)) area2 \(area2[number]) \(kind[number]) adj \(adjacent)"
            }
        case "edges":
            return edges.map { edge in
                let left = edgeTriangles[edge], right = edgeTriangles[edge.reversed], kind = left != nil && right != nil ? "inner" : "hull"
                return "edge \(words(edge)) \(kind) len2 \(length2[edge]!) left \(triangleNumber(left)) right \(triangleNumber(right))"
            }
        case "hull": return ["hull_vertices \(h)", "order \(words(hull))", "perimeter \(real(hullPerimeter))", "area2 \(hullArea2)"]
        case "convex_layers": return ["layers \(layers.count)"] + layers.enumerated().map { "layer \($0.offset + 1) size \($0.element.count) sites \(words($0.element))" }
        case "quality":
            return ["min_angle \(real(minAngles[minimumTriangle])) tri \(minimumTriangle)", "max_angle \(real(maxAngles[maximumTriangle])) tri \(maximumTriangle)", "mean_min_angle \(real(minAngleTotal / Double(t)))"] + angleBins.enumerated().map { "bin \($0.offset * 10) \(($0.offset + 1) * 10) \($0.element)" }
        case "vertices":
            return ["inside", "on", "outside"].map { position in "\(position) \(positions.filter { $0 == position }.count)" } + (1...t).map { number in
                let center = centers[number]
                return "v \(number) \(fraction(center.x, center.denominator)) \(fraction(center.y, center.denominator)) r \(real(sqrt(radius2[number]))) \(positions[number])"
            }
        case "voronoi_edges": return ["segments \(e - h)", "rays \(h)"] + edges.map { "ve \(words($0)) \(duals[$0]!)" }
        case "cells": return cellsSection()
        case "nearest":
            return ["mutual_pairs \(mutualPairs.count)", "closest_pair \(words(closestPair)) d2 \(length2[closestPair]!)"] + (1...n).map { site in
                let other = nearest[site]
                return "nn \(site) \(other) d2 \(d2(points[site], points[other])) \(nearest[other] == site ? "mutual" : "-")"
            }
        case "components": return ["components \(components.count)"] + components.enumerated().map { "component \($0.offset + 1) size \($0.element.count) pair \(words(componentPairs[$0.offset])) sites \(words($0.element))" }
        case "mst":
            let longest = mst.last!
            return ["edges \(n - 1)", "total_length \(real(mstLength))", "longest \(words(longest)) len2 \(length2[longest]!)"] + mst.map { "mst \(words($0)) len2 \(length2[$0]!)" }
        case "proximity": return ["delaunay \(e)", "gabriel \(gabriel.count)", "rng \(rng.count)", "mst \(n - 1)", "nn \(nnEdges.count)"] + edges.filter { rng.contains($0) && !mstSet.contains($0) }.map { "rng_extra \(words($0)) len2 \(length2[$0]!)" }
        case "degrees":
            let counts = Dictionary(grouping: degree.dropFirst(), by: { $0 }).mapValues { $0.count }
            return ["min \(counts.keys.min()!)", "max \(counts.keys.max()!)"] + counts.keys.sorted().map { "degree \($0) count \(counts[$0]!)" }
        case "empty_circle":
            var lines = ["candidates \(emptyCandidates.count)"]
            guard let vertex = emptyVertex else { return lines + ["none"] }
            let center = centers[vertex]
            lines += ["vertex \(vertex)", "center \(fraction(center.x, center.denominator)) \(fraction(center.y, center.denominator))", "radius \(real(sqrt(radius2[vertex])))", "sites \(words(triangles[vertex].sites))"]
            return lines
        case "extent": return ["diameter \(words(diameter)) d2 \(diameter2)", "width \(real(width)) edge \(words(widthEdge))", "enclosing_center \(fraction(enclosingCenter.x, enclosingCenter.denominator)) \(fraction(enclosingCenter.y, enclosingCenter.denominator))", "enclosing_radius \(real(sqrt(enclosingRadius2)))", "enclosing_sites \(words(enclosingSites))"]
        case "spanner": return ["pairs \(pairCount)", "max_stretch \(real(maximumStretch)) pair \(words(stretchPair)) length \(real(stretchLength)) distance \(real(stretchDistance))", "mean_stretch \(real(meanStretch))"]
        case "alpha": return alphaResults
        case "sites": return (1...n).map { site in
            "site \(site) \(words(points[site])) \(hullNext[site] != nil ? "hull" : "inner") dt \(degree[site]) gg \(graphDegrees["gg"]![site]) rng \(graphDegrees["rng"]![site]) mst \(graphDegrees["mst"]![site]) nn \(nearest[site]) comp \(componentNumber[site]) depth \(depth[site])"
        }
        case "queries": return params.queries.map { answerQuery($0) }
        case "delaunay_plot": return delaunayPlot
        default: return voronoiPlot
        }
    }

    func write() throws {
        let owners = Dictionary(uniqueKeysWithValues: outputSections.flatMap { filename, sections in sections.map { ($0, filename) } })
        var contents: [String: [String]] = Dictionary(uniqueKeysWithValues: outputSections.map { ($0.0, []) })
        for name in params.sections { contents[owners[name]!]! += ["[\(name)]"] + section(name) }
        for (filename, _) in outputSections {
            let lines = contents[filename]!, text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
            try text.write(toFile: "output/" + filename, atomically: false, encoding: .ascii)
        }
    }
}

let input = try readPoints()
let report = try Report(input.points, input.lineCount, input.rejected, readSettings())
report.analyze()
try report.write()
