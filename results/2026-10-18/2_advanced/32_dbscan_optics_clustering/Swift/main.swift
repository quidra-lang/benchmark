import Foundation

let labelCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

func labelCharacter(_ label: Int) -> Character {
    if label < 0 { return "." }
    return label < labelCharacters.count ? labelCharacters[label] : "#"
}

func integerRoot(_ value: Int) -> Int {
    if value == 0 { return 0 }
    var low = 1
    var high = value
    var result = 0
    while low <= high {
        let middle = low + (high - low) / 2
        if middle <= value / middle {
            result = middle
            low = middle + 1
        } else {
            high = middle - 1
        }
    }
    return result
}

func optionalRoot(_ value: Int) -> String { value == infinity ? "-" : root(value) }
func valueText(_ value: Int) -> String { value == infinity ? "-" : String(value) }
func optionalText(_ value: Int?) -> String { value.map(String.init) ?? "-" }
func joined<S: Sequence>(_ values: S) -> String where S.Element == Int {
    values.map(String.init).joined(separator: " ")
}

func checkText(_ passed: Bool) -> String { passed ? "ok" : "mismatch" }
func conditionText(_ passed: Bool) -> String { passed ? "ok" : "fail" }
func pairCount(_ count: Int) -> Int { count * (count - 1) / 2 }

struct Curve {
    let order: [Int]
    let values: [Int]
    let cross: Int
    let knee: Int
    let eps: Int

    init(_ points: [Point], _ distances: [Int]) {
        let order = points.indices.sorted { a, b in
            distances[a] == distances[b] ? points[a].id < points[b].id : distances[a] > distances[b]
        }
        let values = order.map { distances[$0] }
        let first = values[0]
        let last = values.last!
        let crosses = values.enumerated().map { rank, value in
            abs((points.count - 1) * (value - first) - (last - first) * rank)
        }
        let cross = crosses.max()!
        let knee = crosses.firstIndex(of: cross)!
        let radius = integerRoot(values[knee])
        self.order = order
        self.values = values
        self.cross = cross
        self.knee = knee
        eps = max(1, radius + (radius * radius < values[knee] ? 1 : 0))
    }
}

enum SettingKind {
    case dbscan
    case extract
    case xi
}

struct Setting {
    let name: String
    let kind: SettingKind
    let radius: Int
    let labels: [Int]
    let core: [Bool]
    let members: [[Int]]
    let noise: Int
    let coreCount: Int
    var count: Int { members.count }
    var borderCount: Int { labels.count - noise - coreCount }

    init(_ name: String, _ kind: SettingKind, _ radius: Int, _ labels: [Int], _ core: [Bool]) {
        var members = [[Int]](repeating: [], count: labels.max()! + 1)
        var noise = 0
        var coreCount = 0
        for i in labels.indices {
            if labels[i] == -1 {
                noise += 1
            } else {
                members[labels[i]].append(i)
                if core[i] { coreCount += 1 }
            }
        }
        self.name = name
        self.kind = kind
        self.radius = radius
        self.labels = labels
        self.core = core
        self.members = members
        self.noise = noise
        self.coreCount = coreCount
    }
}

func extractClusters(_ ordering: Ordering, _ radius: Int) -> ([Int], [Bool]) {
    let limit = radius * radius
    var labels = [Int](repeating: -1, count: ordering.points.count)
    var label = -1
    for i in ordering.points {
        if ordering.reach[i] > limit {
            if ordering.core[i] <= limit {
                label += 1
                labels[i] = label
            }
        } else {
            labels[i] = label
        }
    }
    return (labels, ordering.core.map { $0 <= limit })
}

struct SteepArea {
    let down: Bool
    let start: Int
    let end: Int
}

struct DownArea {
    let start: Int
    let end: Int
    var high: Int
}

struct XiCluster {
    let start: Int
    let end: Int
    var label: Int?
    var parent: Int?
    var size: Int { end - start + 1 }
}

struct XiResult {
    let reach: [Int]
    let areas: [SteepArea]
    let clusters: [XiCluster]
    let labels: [Int]

    init(_ reach: [Int], _ params: Params) {
        let count = reach.count - 1
        let alpha = (params.v - params.u) * (params.v - params.u)
        let beta = params.v * params.v
        func xle(_ a: Int, _ b: Int) -> Bool {
            if b == infinity { return true }
            if a == infinity { return false }
            return beta * a <= alpha * b
        }
        let steepUp = (0..<count).map {
            (reach[$0] != infinity || reach[$0 + 1] != infinity) && xle(reach[$0], reach[$0 + 1])
        }
        let steepDown = (0..<count).map {
            (reach[$0] != infinity || reach[$0 + 1] != infinity) && xle(reach[$0 + 1], reach[$0])
        }
        let up = (0..<count).map { reach[$0] < reach[$0 + 1] }
        let down = (0..<count).map { reach[$0] > reach[$0 + 1] }
        func regionEnd(_ start: Int, _ steep: [Bool], _ reverse: [Bool]) -> Int {
            var end = start
            var flat = 0
            for i in start..<count {
                if steep[i] {
                    end = i
                    flat = 0
                } else if reverse[i] {
                    break
                } else {
                    flat += 1
                    if flat > params.minPts { break }
                }
            }
            return end
        }
        var areas: [SteepArea] = []
        var clusters: [XiCluster] = []
        var downAreas: [DownArea] = []
        var index = 0
        var mib = 0
        for start in 0..<count {
            if start < index || (!steepUp[start] && !steepDown[start]) { continue }
            for i in index...start { mib = max(mib, reach[i]) }
            if mib == infinity {
                downAreas.removeAll()
            } else {
                downAreas = downAreas.filter { xle(mib, reach[$0.start]) }
                for i in downAreas.indices { downAreas[i].high = max(downAreas[i].high, mib) }
            }
            if steepDown[start] {
                let end = regionEnd(start, steepDown, up)
                areas.append(SteepArea(down: true, start: start, end: end))
                downAreas.append(DownArea(start: start, end: end, high: 0))
                index = end + 1
                mib = reach[index]
            } else {
                let end = regionEnd(start, steepUp, down)
                areas.append(SteepArea(down: false, start: start, end: end))
                index = end + 1
                mib = reach[index]
                var candidates: [XiCluster] = []
                for area in downAreas {
                    var cs = area.start
                    var ce = end
                    if !xle(area.high, reach[ce + 1]) { continue }
                    let top = reach[area.start]
                    if xle(reach[ce + 1], top) {
                        while cs < area.end && reach[cs + 1] > reach[ce + 1] { cs += 1 }
                    } else if xle(top, reach[ce + 1]) {
                        while ce > start && reach[ce - 1] > top { ce -= 1 }
                    }
                    if ce - cs + 1 >= params.minSize && cs <= area.end && ce >= start {
                        candidates.append(XiCluster(start: cs, end: ce, label: nil, parent: nil))
                    }
                }
                clusters.append(contentsOf: candidates.reversed())
            }
        }
        var labels = [Int](repeating: -1, count: count)
        var nextLabel = 0
        for j in clusters.indices {
            let interval = clusters[j].start...clusters[j].end
            if labels[interval].allSatisfy({ $0 == -1 }) {
                for i in interval { labels[i] = nextLabel }
                clusters[j].label = nextLabel
                nextLabel += 1
            }
        }
        for j in clusters.indices {
            let cluster = clusters[j]
            var parent: Int?
            for i in clusters.indices {
                let other = clusters[i]
                if i == j || other.start > cluster.start || cluster.end > other.end { continue }
                if other.size < cluster.size || (other.size == cluster.size && i < j) { continue }
                if parent == nil || other.size < clusters[parent!].size { parent = i }
            }
            clusters[j].parent = parent
        }
        self.reach = reach
        self.areas = areas
        self.clusters = clusters
        self.labels = labels
    }

    func walls(_ cluster: XiCluster) -> (Int, Int, Int) {
        let inner = reach[(cluster.start + 1)...cluster.end].filter { $0 != infinity }
        return (reach[cluster.start], reach[cluster.end + 1], inner.min() ?? infinity)
    }
}

func turn(_ origin: Point, _ first: Point, _ second: Point) -> Int {
    (first.x - origin.x) * (second.y - origin.y) - (first.y - origin.y) * (second.x - origin.x)
}

func convexHull(_ members: [Point]) -> [Point] {
    let ordered = members.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
    if ordered.count <= 2 { return ordered }
    func chain<S: Sequence>(_ points: S) -> [Point] where S.Element == Point {
        var result: [Point] = []
        for point in points {
            while result.count >= 2 && turn(result[result.count - 2], result.last!, point) <= 0 {
                result.removeLast()
            }
            result.append(point)
        }
        return result
    }
    return Array(chain(ordered).dropLast()) + Array(chain(ordered.reversed()).dropLast())
}

func clusterLines(_ points: [Point], _ setting: Setting, _ label: Int) -> [String] {
    let members = setting.members[label].map { points[$0] }
    let size = members.count
    let core = setting.members[label].filter { setting.core[$0] }.count
    let sumX = members.reduce(0) { $0 + $1.x }
    let sumY = members.reduce(0) { $0 + $1.y }
    func score(_ point: Point) -> Int {
        let x = size * point.x - sumX
        let y = size * point.y - sumY
        return x * x + y * y
    }
    let medoid = members.min { a, b in score(a) == score(b) ? a.id < b.id : score(a) < score(b) }!
    let xmin = members.map { $0.x }.min()!
    let xmax = members.map { $0.x }.max()!
    let ymin = members.map { $0.y }.min()!
    let ymax = members.map { $0.y }.max()!
    let area = (xmax - xmin + 1) * (ymax - ymin + 1)
    let hull = convexHull(members)
    var doubledArea = 0
    var diameter = 0
    for i in hull.indices {
        let next = hull[(i + 1) % hull.count]
        doubledArea += hull[i].x * next.y - next.x * hull[i].y
        for other in hull { diameter = max(diameter, distance(hull[i], other)) }
    }
    doubledArea = abs(doubledArea)
    let areaText = "\(doubledArea / 2).\(doubledArea % 2 == 0 ? 0 : 5)"
    return [
        "cluster \(label) \(labelCharacter(label)) size \(size) core \(core) border \(size - core) "
            + "centroid \(fraction(sumX, size)) \(fraction(sumY, size)) medoid \(medoid.id)",
        "  bbox \(xmin) \(ymin) \(xmax) \(ymax) area \(area) density \(fraction(size, area))",
        "  hull \(hull.count) hull_area \(areaText) diameter_sq \(diameter) diameter \(root(diameter))"
    ]
}

struct LabelPair: Hashable {
    let first: Int
    let second: Int
}

func adjustedRand(_ first: [Int], _ second: [Int]) -> (Int, Int) {
    var pairs: [LabelPair: Int] = [:]
    var firstCounts: [Int: Int] = [:]
    var secondCounts: [Int: Int] = [:]
    for (a, b) in zip(first, second) {
        pairs[LabelPair(first: a, second: b), default: 0] += 1
        firstCounts[a, default: 0] += 1
        secondCounts[b, default: 0] += 1
    }
    let shared = pairs.values.reduce(0) { $0 + pairCount($1) }
    let a = firstCounts.values.reduce(0) { $0 + pairCount($1) }
    let b = secondCounts.values.reduce(0) { $0 + pairCount($1) }
    let z = pairCount(first.count)
    let numerator = 2 * (z * shared - a * b)
    let denominator = z * (a + b) - 2 * a * b
    return denominator == 0 ? (1, 1) : (numerator, denominator)
}

struct Analysis {
    let points: [Point]
    let params: Params
    let curves: [Curve]
    let kdist: [Int]
    let grids: [Grid]
    let neighborhoods: [Int: [[Int]]]
    let settings: [Setting]
    let knee: Setting
    let ordering: Ordering
    let xi: XiResult
    let xiSetting: Setting
    let mapCells: [Cell]
    var k: Int { params.minPts - 1 }
    var curve: Curve { curves[k - 1] }
    var dbSettings: [Setting] { settings.filter { $0.kind == .dbscan } }

    init(_ points: [Point], _ params: Params) {
        let rows = points.indices.map { i in
            points.indices.filter { $0 != i }.map { distance(points[i], points[$0]) }.sorted()
        }
        let curves = (0..<(2 * params.minPts)).map { j in Curve(points, rows.map { $0[j] }) }
        let curve = curves[params.minPts - 2]
        let kdist = rows.map { $0[params.minPts - 2] }
        let radii = Set(params.eps + [curve.eps, params.maxEps]).sorted()
        let grids = radii.map { Grid(points, $0) }
        let neighborhoods = Dictionary(uniqueKeysWithValues: grids.map { ($0.radius, $0.neighborhoods) })
        var settings: [Setting] = []
        for radius in params.eps {
            let (labels, core) = dbscan(neighborhoods[radius]!, params.minPts)
            settings.append(Setting("db\(radius)", .dbscan, radius, labels, core))
        }
        let (kneeLabels, kneeCore) = dbscan(neighborhoods[curve.eps]!, params.minPts)
        let knee = Setting("knee\(curve.eps)", .dbscan, curve.eps, kneeLabels, kneeCore)
        settings.append(knee)
        let ordering = opticsOrder(points, neighborhoods[params.maxEps]!, params.minPts)
        for radius in params.extract {
            let (labels, core) = extractClusters(ordering, radius)
            settings.append(Setting("op\(radius)", .extract, radius, labels, core))
        }
        let positions = ordering.points.map { ordering.reach[$0] } + [infinity]
        let xi = XiResult(positions, params)
        var labels = [Int](repeating: -1, count: points.count)
        for (position, i) in ordering.points.enumerated() { labels[i] = xi.labels[position] }
        let xiSetting = Setting("xi", .xi, params.maxEps, labels, ordering.core.map { $0 != infinity })
        settings.append(xiSetting)
        let xmin = points.map { $0.x }.min()!
        let xmax = points.map { $0.x }.max()!
        let ymin = points.map { $0.y }.min()!
        let ymax = points.map { $0.y }.max()!
        let cells = points.map {
            Cell(
                x: ($0.x - xmin) * params.width / (xmax - xmin + 1),
                y: (ymax - $0.y) * params.height / (ymax - ymin + 1)
            )
        }
        self.points = points
        self.params = params
        self.curves = curves
        self.kdist = kdist
        self.grids = grids
        self.neighborhoods = neighborhoods
        self.settings = settings
        self.knee = knee
        self.ordering = ordering
        self.xi = xi
        self.xiSetting = xiSetting
        mapCells = cells
    }

    func labelsLines() -> [String] {
        ["id," + settings.map { $0.name }.joined(separator: ",")] + points.indices.map { i in
            ([String(points[i].id)] + settings.map { String($0.labels[i]) }).joined(separator: ",")
        }
    }

    func opticsLines() -> [String] {
        ["order,id,core_sq,reach_sq,reach,predecessor"] + ordering.points.enumerated().map { position, i in
            let predecessor = ordering.predecessor[i].map { points[$0].id }
            return [
                String(position + 1), String(points[i].id), valueText(ordering.core[i]),
                valueText(ordering.reach[i]), optionalRoot(ordering.reach[i]), optionalText(predecessor)
            ].joined(separator: ",")
        }
    }

    func kdistLines() -> [String] {
        var lines = ["k_distance k \(k) points \(points.count)", "rank id kdist_sq kdist"]
        for (rank, i) in curve.order.enumerated() {
            lines.append("\(rank + 1) \(points[i].id) \(curve.values[rank]) \(root(curve.values[rank]))")
        }
        let value = curve.values[curve.knee]
        lines += [
            "", "knee rank \(curve.knee + 1) id \(points[curve.order[curve.knee]].id) "
                + "kdist_sq \(value) kdist \(root(value)) cross \(curve.cross)",
            "suggested_eps \(curve.eps)", "", "knee_table"
        ]
        for (j, row) in curves.enumerated() {
            lines.append(
                "k \(j + 1) rank \(row.knee + 1) id \(points[row.order[row.knee]].id) "
                    + "kdist_sq \(row.values[row.knee]) eps \(row.eps)"
            )
        }
        lines += ["", "core_check"]
        for setting in dbSettings {
            let core = kdist.filter { $0 <= setting.radius * setting.radius }.count
            let gridCore = setting.core.filter { $0 }.count
            lines.append(
                "eps \(setting.radius) core \(core) non_core \(points.count - core) "
                    + "grid_core \(gridCore) \(checkText(core == gridCore))"
            )
        }
        let defined = points.indices.filter { ordering.core[$0] != infinity }
        let consistent = defined.allSatisfy { ordering.core[$0] == kdist[$0] }
        lines.append("optics max_eps \(params.maxEps) core \(defined.count) \(checkText(consistent))")
        return lines
    }

    func gridLines() -> [String] {
        var lines = ["grid"]
        for grid in grids {
            let (x, y, size) = grid.busiest
            lines.append(
                "eps \(grid.radius) cells \(grid.cells.count) busiest \(x) \(y) \(size) "
                    + "candidates \(grid.candidates) pairs \(grid.pairs) brute_pairs \(grid.brutePairs) "
                    + checkText(grid.consistent)
            )
            let occupancy = grid.occupancy.keys.sorted().map { "\($0):\(grid.occupancy[$0]!)" }
            lines.append("  occupancy " + occupancy.joined(separator: " "))
        }
        return lines
    }

    func checkLines(_ setting: Setting) -> [String] {
        var linked = true
        var supported = true
        var separated = true
        var isolated = 0
        var ambiguous: [String] = []
        for (i, neighbors) in neighborhoods[setting.radius]!.enumerated() {
            let label = setting.labels[i]
            let coreLabels = neighbors.filter { setting.core[$0] }.map { setting.labels[$0] }
            if setting.core[i] {
                linked = linked && coreLabels.allSatisfy { $0 == label }
            } else if label != -1 {
                supported = supported && coreLabels.contains(label)
                let others = Set(coreLabels.filter { $0 != label }).sorted()
                if !others.isEmpty {
                    ambiguous.append("  \(points[i].id) cluster \(label) also \(joined(others))")
                }
            } else {
                separated = separated && coreLabels.isEmpty
                if neighbors.count == 1 { isolated += 1 }
            }
        }
        return [
            "check \(conditionText(linked)) \(conditionText(supported)) \(conditionText(separated))",
            "isolated \(isolated)", "ambiguous \(ambiguous.count)"
        ] + ambiguous
    }

    func settingLines(_ setting: Setting) -> [String] {
        var lines = [
            "setting \(setting.name) eps \(setting.radius) clusters \(setting.count) noise \(setting.noise) "
                + "core \(setting.coreCount) border \(setting.borderCount)"
        ]
        for label in setting.members.indices { lines += clusterLines(points, setting, label) }
        if setting.kind == .dbscan { lines += checkLines(setting) }
        return lines
    }

    func hierarchyLines() -> [String] {
        let ordered = dbSettings.enumerated().sorted { a, b in
            a.element.radius == b.element.radius ? a.offset < b.offset : a.element.radius < b.element.radius
        }.map { $0.element }
        var lines = ["hierarchy"]
        for (smaller, larger) in zip(ordered, ordered.dropFirst()) {
            lines.append("\(smaller.name) -> \(larger.name)")
            var sources = [[Int]](repeating: [], count: larger.count)
            for (label, members) in smaller.members.enumerated() {
                let firstCore = members.first { smaller.core[$0] }!
                sources[larger.labels[firstCore]].append(label)
            }
            for (label, clusters) in sources.enumerated() {
                lines.append("  \(label) <- " + (clusters.isEmpty ? "-" : joined(clusters)))
            }
        }
        return lines
    }

    func comparisonLines() -> [String] {
        var lines = ["optics_vs_dbscan"]
        for extracted in settings where extracted.kind == .extract {
            guard let reference = dbSettings.first(where: { $0.radius == extracted.radius }) else { continue }
            let pairs = Set(points.indices.filter { extracted.core[$0] }.map {
                LabelPair(first: extracted.labels[$0], second: reference.labels[$0])
            })
            let same = pairs.count == Set(pairs.map { $0.first }).count
                && pairs.count == Set(pairs.map { $0.second }).count
            let borderNoise = points.indices.filter { extracted.labels[$0] == -1 && reference.labels[$0] != -1 }.count
            var moved = "-"
            if same {
                let mapping = Dictionary(uniqueKeysWithValues: pairs.map { ($0.first, $0.second) })
                moved = String(points.indices.filter {
                    extracted.labels[$0] != -1 && mapping[extracted.labels[$0]]! != reference.labels[$0]
                }.count)
            }
            lines.append(
                "\(extracted.name) \(reference.name) core_partition \(same ? "same" : "different") "
                    + "border_as_noise \(borderNoise) moved \(moved)"
            )
        }
        return lines
    }

    func opticsSummaryLines() -> [String] {
        var components: [Int] = []
        for i in ordering.points {
            if ordering.reach[i] == infinity { components.append(0) }
            components[components.count - 1] += 1
        }
        let core = ordering.core.filter { $0 != infinity }.count
        return [
            "optics max_eps \(params.maxEps) core \(core) components \(components.count) "
                + "singletons \(components.filter { $0 == 1 }.count) largest \(components.max()!)"
        ]
    }

    func sweepLines() -> [String] {
        var lines = ["sweep max_eps \(params.maxEps)", "eps clusters noise largest"]
        var counts: [Int] = []
        for radius in 1...params.maxEps {
            let (labels, core) = extractClusters(ordering, radius)
            let setting = Setting("", .extract, radius, labels, core)
            counts.append(setting.count)
            let largest = setting.members.map { $0.count }.max() ?? 0
            lines.append("\(radius) \(setting.count) \(setting.noise) \(largest)")
        }
        var start = 0
        var stable: (Int, Int, Int, Int)?
        for radius in 1...params.maxEps {
            if radius < params.maxEps && counts[radius] == counts[start] { continue }
            let length = radius - start
            if counts[start] >= 2 && (stable == nil || length > stable!.3) {
                stable = (counts[start], start + 1, radius, length)
            }
            start = radius
        }
        if let stable {
            lines.append("stable clusters \(stable.0) eps \(stable.1) \(stable.2) length \(stable.3)")
        } else {
            lines.append("stable -")
        }
        return lines
    }

    func xiLines() -> [String] {
        var lines = ["xi \(params.xi) min_size \(params.minSize) steep_areas \(xi.areas.count)"]
        for area in xi.areas {
            lines.append("\(area.down ? "down" : "up") \(area.start + 1) \(area.end + 1)")
        }
        lines.append("xi_clusters \(xi.clusters.count)")
        for (j, cluster) in xi.clusters.enumerated() {
            let (left, right, valley) = xi.walls(cluster)
            lines.append(
                "\(j) start \(cluster.start + 1) end \(cluster.end + 1) size \(cluster.size) "
                    + "label \(optionalText(cluster.label)) parent \(optionalText(cluster.parent)) "
                    + "walls \(optionalRoot(left)) \(optionalRoot(right)) valley \(optionalRoot(valley))"
            )
        }
        return lines
    }

    func outlierLines() -> [String] {
        let corePoints = points.indices.filter { knee.core[$0] }
        var rows: [(Int, Int, Int)] = []
        for i in points.indices where knee.labels[i] == -1 {
            let nearest = corePoints.min { a, b in
                let first = distance(points[i], points[a])
                let second = distance(points[i], points[b])
                return first == second ? points[a].id < points[b].id : first < second
            }!
            rows.append((distance(points[i], points[nearest]), i, nearest))
        }
        rows.sort { a, b in a.0 == b.0 ? points[a.1].id < points[b.1].id : a.0 > b.0 }
        return ["outliers \(knee.name) count \(rows.count)"] + rows.map { d, i, nearest in
            "\(points[i].id) nearest_core \(points[nearest].id) cluster \(knee.labels[nearest]) "
                + "dist_sq \(d) dist \(root(d))"
        }
    }

    func gapLines() -> [String] {
        var lines = ["gaps \(knee.name)"]
        for a in 0..<knee.count {
            for b in (a + 1)..<knee.count {
                var best: (Int, Int, Int)?
                for i in knee.members[a] {
                    for j in knee.members[b] {
                        let d = distance(points[i], points[j])
                        if best == nil || d < best!.0 { best = (d, i, j) }
                    }
                }
                let (d, i, j) = best!
                lines.append("\(a) \(b) dist_sq \(d) dist \(root(d)) between \(points[i].id) \(points[j].id)")
            }
        }
        return lines
    }

    func contingencyLines() -> [String] {
        var table = [[Int]](repeating: [Int](repeating: 0, count: xiSetting.count + 1), count: knee.count + 1)
        for i in points.indices { table[knee.labels[i] + 1][xiSetting.labels[i] + 1] += 1 }
        var lines = ["contingency \(knee.name) xi", "columns " + joined(-1..<xiSetting.count)]
        for row in -1..<knee.count { lines.append("\(row) " + joined(table[row + 1])) }
        for column in 0..<xiSetting.count {
            var row = 0
            for candidate in 1..<knee.count {
                if table[candidate + 1][column + 1] > table[row + 1][column + 1] { row = candidate }
            }
            let shared = table[row + 1][column + 1]
            let union = knee.members[row].count + xiSetting.members[column].count - shared
            lines.append("match \(column) \(row) shared \(shared) jaccard \(fraction(shared, union))")
        }
        return lines
    }

    func ariLines() -> [String] {
        var lines = ["ari"]
        for i in settings.indices {
            for j in (i + 1)..<settings.count {
                let (numerator, denominator) = adjustedRand(settings[i].labels, settings[j].labels)
                lines.append("\(settings[i].name) \(settings[j].name) \(ari(numerator, denominator))")
            }
        }
        return lines
    }

    func clustersLines() -> [String] {
        let header = [
            "points \(points.count) min_pts \(params.minPts)",
            "settings " + settings.map { $0.name }.joined(separator: " ")
        ]
        let parts = [header, gridLines()] + settings.map(settingLines) + [
            hierarchyLines(), comparisonLines(), opticsSummaryLines(), sweepLines(), xiLines(),
            outlierLines(), gapLines(), contingencyLines(), ariLines()
        ]
        var lines: [String] = []
        for part in parts {
            if !lines.isEmpty { lines.append("") }
            lines += part
        }
        return lines
    }

    func clusterMap(_ setting: Setting) -> [String] {
        var cells = [[[Int]]](
            repeating: [[Int]](repeating: [], count: params.width), count: params.height
        )
        for i in points.indices { cells[mapCells[i].y][mapCells[i].x].append(setting.labels[i]) }
        return cells.map { row in
            String(row.map { labels -> Character in
                let clusters = Set(labels.filter { $0 != -1 })
                if labels.isEmpty { return " " }
                if clusters.isEmpty { return "." }
                return clusters.count == 1 ? labelCharacter(clusters.first!) : "*"
            })
        }
    }

    func kindMap() -> [String] {
        var cells = [[Int]](repeating: [Int](repeating: 0, count: params.width), count: params.height)
        for i in points.indices {
            let kind = knee.core[i] ? 3 : knee.labels[i] != -1 ? 2 : 1
            let cell = mapCells[i]
            cells[cell.y][cell.x] = max(cells[cell.y][cell.x], kind)
        }
        let symbols = Array(" .+#")
        return cells.map { String($0.map { symbols[$0] }) }
    }

    func kdistPlot() -> ([String], Int) {
        let width = params.kWidth
        let height = params.kHeight
        let count = points.count
        let top = curve.values[0]
        var heights: [Int] = []
        var kneeColumn = 0
        for column in 0..<width {
            let first = column * count / width
            let last = (column + 1) * count / width
            heights.append(integerRoot(height * height * curve.values[first] / top))
            if first <= curve.knee && curve.knee < last { kneeColumn = column }
        }
        let rows = (0..<height).map { row in
            String((0..<width).map { column -> Character in
                if height - row <= heights[column] { return "#" }
                return column == kneeColumn ? ":" : " "
            })
        }
        return (rows, kneeColumn)
    }

    func reachabilityLines() -> [String] {
        let width = params.plotWidth
        let top = ordering.reach.filter { $0 != infinity }.max()!
        let columns = settings.filter { $0.kind == .extract } + [xiSetting]
        var lines = [
            "reachability width \(width) max_reach \(root(top)) columns "
                + columns.map { $0.name }.joined(separator: " ")
        ]
        func pad(_ text: String, _ width: Int) -> String {
            String(repeating: " ", count: max(0, width - text.count)) + text
        }
        for (position, i) in ordering.points.enumerated() {
            let reach = ordering.reach[i]
            let bar = reach == infinity ? String(repeating: "-", count: width)
                : String(repeating: "#", count: integerRoot(width * width * reach / top))
            let characters = String(columns.map { labelCharacter($0.labels[i]) })
            lines.append(
                pad(String(position + 1), 4) + " " + pad(String(points[i].id), 5) + " "
                    + pad(optionalRoot(reach), 7) + " \(characters) |\(bar)"
            )
        }
        return lines
    }

    func mapsLines() -> [String] {
        var lines: [String] = []
        for setting in settings {
            lines.append("map \(setting.name) clusters \(setting.count) noise \(setting.noise)")
            lines += framed(clusterMap(setting), params.width)
            let legend = setting.members.enumerated().map { label, members in
                "\(labelCharacter(label))=\(members.count)"
            }
            lines.append("legend " + (legend.isEmpty ? "-" : legend.joined(separator: " ")))
            lines.append("")
        }
        lines.append("kinds \(knee.name)")
        lines += framed(kindMap(), params.width)
        let (rows, kneeColumn) = kdistPlot()
        lines += ["", "kdist_plot k \(k) max \(root(curve.values[0])) knee_column \(kneeColumn + 1)"]
        lines += framed(rows, params.kWidth)
        lines.append("")
        lines += reachabilityLines()
        return lines
    }
}

let (points, params) = try readInputs()
let analysis = Analysis(points, params)
for (name, lines) in [
    ("labels.csv", analysis.labelsLines()), ("optics_order.csv", analysis.opticsLines()),
    ("kdist.txt", analysis.kdistLines()), ("clusters.txt", analysis.clustersLines()),
    ("maps.txt", analysis.mapsLines())
] {
    try writeLines(name, lines)
}
