import Foundation

func real(_ value: Double) -> String {
    let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.0000" ? "0.0000" : text
}
func optionalReal(_ value: Double?) -> String { value.map(real) ?? "-" }
func reals<S: Sequence>(_ values: S) -> String where S.Element == Double { values.map(real).joined(separator: " ") }
func integers(_ values: [Int]) -> String { values.map(String.init).joined(separator: " ") }
func fourDigit(_ value: Double) -> Double { Double(real(value))! }
func ariText(_ fraction: Fraction) -> String { "\(fraction.numerator)/\(fraction.denominator) \(real(fraction.value))" }
func pairValues(_ matrix: [[Double]]) -> [Double] {
    var values: [Double] = []
    for i in matrix.indices { for j in (i + 1)..<matrix.count { values.append(matrix[i][j]) } }
    return values
}
func histogramBin(_ value: Double, _ maximum: Double) -> Int { min(9, Int(floor(10.0 * value / maximum))) }
func centroid(_ vectors: [[Double]]) -> [Double] {
    vectors[0].indices.map { f in sequentialSum(vectors.map { $0[f] }) / Double(vectors.count) }
}
func clusterMembers(_ partition: [Int], _ groups: Int) -> [[Int]] {
    var members = Array(repeating: [Int](), count: groups)
    for (i, number) in partition.enumerated() { members[number - 1].append(i) }
    return members
}
func majorityClass(_ row: [Int]) -> Int {
    var best = 0
    for t in 1..<row.count { if row[t] > row[best] { best = t } }
    return best
}
func joinParts(_ parts: [[String]]) -> [String] {
    var lines: [String] = []
    for part in parts { if !lines.isEmpty { lines.append("") }; lines.append(contentsOf: part) }
    return lines
}
func partitionARI(_ first: [Int], _ second: [Int]) -> Fraction {
    adjustedRandIndex(contingencyTable(first.map { $0 - 1 }, second.map { $0 - 1 }, first.max()!, second.max()!))
}

struct Minstd {
    var state: Int
    mutating func draw() -> Int { state = 48271 * state % 2147483647; return state }
}

struct Tree {
    let merges: [Merge]
    let n: Int
    let children: [(Int, Int)]
    let order: [Int]
    let members: [[Int]]
    let depths: [Int]
    let subtreeHeights: [Double]

    init(_ merges: [Merge], _ n: Int) {
        let children = orderedChildren(merges, n)
        var members = (0..<n).map { [$0] }, depths = Array(repeating: 0, count: n)
        var maxima = Array(repeating: 0.0, count: n), subtreeHeights: [Double] = []
        for merge in merges {
            members.append(members[merge.a] + members[merge.b])
            depths.append(1 + max(depths[merge.a], depths[merge.b]))
            let maximum = max(merge.height, max(maxima[merge.a], maxima[merge.b]))
            maxima.append(maximum)
            subtreeHeights.append(maximum)
        }
        self.merges = merges
        self.n = n
        self.children = children
        order = leafOrder(children, n)
        self.members = members
        self.depths = depths
        self.subtreeHeights = subtreeHeights
    }
    var root: Int { 2 * n - 2 }
    var heights: [Double] { merges.map(\.height) }
    func height(_ node: Int) -> Double { node < n ? 0.0 : merges[node - n].height }
    func partition(_ selected: [Bool]) -> [Int] {
        var owner = Array(0..<n)
        for (step, chosen) in selected.enumerated() where chosen { for u in members[n + step] { owner[u] = n + step } }
        var numbers = Array(repeating: 0, count: 2 * n - 1), groups = 0
        for u in order where numbers[owner[u]] == 0 { groups += 1; numbers[owner[u]] = groups }
        return owner.map { numbers[$0] }
    }
    func cutAtHeight(_ height: Double) -> [Int] { partition(subtreeHeights.map { $0 <= height }) }
    func cutInto(_ k: Int) -> [Int] { partition((0..<(n - 1)).map { $0 < n - k }) }
    func cophenetic() -> [[Double]] {
        var matrix = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for merge in merges {
            for i in members[merge.a] { for j in members[merge.b] { matrix[i][j] = merge.height; matrix[j][i] = merge.height } }
        }
        return matrix
    }
    func joiningHeights() -> [Double] {
        var values = Array(repeating: 0.0, count: n)
        for merge in merges { for child in [merge.a, merge.b] where child < n { values[child] = merge.height } }
        return values
    }
    func heightSequence(_ step: Int, _ depth: Int) -> [Double] {
        if depth == 0 { return [] }
        let merge = merges[step]
        var sequence = [merge.height]
        for child in [merge.a, merge.b] where child >= n { sequence.append(contentsOf: heightSequence(child - n, depth - 1)) }
        return sequence
    }
    func newick(_ node: Int, _ ids: [String]) -> String {
        if node < n { return ids[node] }
        let (upper, lower) = children[node - n]
        let h = height(node)
        return "(\(newick(upper, ids)):\(real(h - height(upper))),\(newick(lower, ids)):\(real(h - height(lower))))"
    }
}

struct Evaluation {
    let partition: [Int]
    let sizes: [Int]
    let silhouette: Double?
    let dunn: Double?
    let wss: Double
    let ch: Double?
    let ari: Fraction
    var text: String { "sizes \(integers(sizes)) silhouette \(optionalReal(silhouette)) dunn \(optionalReal(dunn)) wss \(real(wss)) ch \(optionalReal(ch)) ari \(ariText(ari))" }
}
struct LinkageResult {
    let method: Linkage
    let tree: Tree
    let cophenetic: [Double]
    let correlation: Double
    let heightCuts: [Evaluation]
    let countCuts: [Evaluation]
    let labelPartition: [Int]
}

final class Study {
    let features: [String]
    let settings: Settings
    let n: Int
    let ids: [String]
    let labels: [String]
    let classes: [String]
    let targets: [Int]
    let raw: [[Double]]
    let means: [Double]
    let deviations: [Double]
    let vectors: [[Double]]
    let delta: [[Double]]
    let pairs: [Double]
    let distanceMax: Double
    let neighbors: [Int]
    var results: [LinkageResult] = []
    var chosenIndex = 0
    var position = 0

    init(_ features: [String], _ observations: [Observation], _ settings: Settings) {
        let labels = observations.map(\.label), classes = Array(Set(observations.map(\.label))).sorted()
        let raw = observations.map(\.values)
        let (means, deviations) = featureStatistics(raw)
        let vectors = settings.standardize ? standardize(raw, means, deviations) : raw
        let delta = distanceMatrix(vectors, settings.distance), pairs = pairValues(delta)
        let n = observations.count
        var neighbors: [Int] = []
        for i in 0..<n {
            var best = i == 0 ? 1 : 0
            for j in 0..<n where j != i && delta[i][j] < delta[i][best] { best = j }
            neighbors.append(best)
        }
        self.features = features
        self.settings = settings
        self.n = n
        ids = observations.map(\.id)
        self.labels = labels
        self.classes = classes
        targets = labels.map { classes.firstIndex(of: $0)! }
        self.raw = raw
        self.means = means
        self.deviations = deviations
        self.vectors = vectors
        self.delta = delta
        self.pairs = pairs
        distanceMax = pairs.max()!
        self.neighbors = neighbors
        for method in settings.linkages { results.append(analyseLinkage(method)) }
        for r in results.indices { for k in settings.cutCounts.indices {
            if results[r].countCuts[k].ari.greater(results[chosenIndex].countCuts[position].ari) { chosenIndex = r; position = k }
        } }
    }
    var chosen: LinkageResult { results[chosenIndex] }
    var selectedCut: Evaluation { chosen.countCuts[position] }
    var selected: [Int] { selectedCut.partition }
    var kappa: Int { settings.cutCounts[position] }
    var members: [[Int]] { clusterMembers(selected, kappa) }
    func classTable(_ partition: [Int]) -> [[Int]] { contingencyTable(partition.map { $0 - 1 }, targets, partition.max()!, classes.count) }
    func labelARI(_ partition: [Int]) -> Fraction { adjustedRandIndex(classTable(partition)) }
    func matchCount(_ partition: [Int]) -> Int { classTable(partition).reduce(0) { $0 + $1.max()! } }
    func meanSilhouette(_ partition: [Int], _ distances: [[Double]]) -> Double? {
        let groups = partition.max()!
        if groups < 2 { return nil }
        return sequentialSum(silhouetteValues(partition, groups, distances)) / Double(partition.count)
    }
    func centroids(_ partition: [Int]) -> [[Double]] { clusterMembers(partition, partition.max()!).map { group in centroid(group.map { vectors[$0] }) } }
    func withinSum(_ partition: [Int]) -> Double {
        let centers = centroids(partition)
        return sequentialSum(partition.enumerated().map { i, number in squaredDistance(vectors[i], centers[number - 1]) })
    }
    func evaluate(_ partition: [Int]) -> Evaluation {
        let groups = partition.max()!, members = clusterMembers(partition, partition.max()!)
        let sizes = members.map(\.count), wss = withinSum(partition)
        var diameter = 0.0, separation = Double.infinity
        for i in 0..<n { for j in (i + 1)..<n {
            if partition[i] == partition[j] { diameter = max(diameter, delta[i][j]) }
            else { separation = min(separation, delta[i][j]) }
        } }
        let dunn: Double? = groups >= 2 && diameter > 0 ? separation / diameter : nil
        var ch: Double? = nil
        if groups >= 2 && groups < n {
            let overall = centroid(vectors), centers = centroids(partition)
            let bss = sequentialSum(zip(sizes, centers).map { size, center in Double(size) * squaredDistance(center, overall) })
            ch = (bss / Double(groups - 1)) / (wss / Double(n - groups))
        }
        return Evaluation(partition: partition, sizes: sizes, silhouette: meanSilhouette(partition, delta), dunn: dunn, wss: wss, ch: ch, ari: labelARI(partition))
    }
    func analyseLinkage(_ method: Linkage) -> LinkageResult {
        let tree = Tree(agglomerate(delta, method), n)
        let cophenetic = pairValues(tree.cophenetic())
        return LinkageResult(method: method, tree: tree, cophenetic: cophenetic, correlation: correlation(pairs, cophenetic), heightCuts: settings.cutHeights.map { evaluate(tree.cutAtHeight($0)) }, countCuts: settings.cutCounts.map { evaluate(tree.cutInto($0)) }, labelPartition: tree.cutInto(classes.count))
    }
    func linkageTable() -> [String] {
        var lines = ["method,step,a,b,height,size"]
        for result in results { for (step, merge) in result.tree.merges.enumerated() {
            lines.append("\(result.method.rawValue),\(step + 1),\(merge.a),\(merge.b),\(real(merge.height)),\(merge.size)")
        } }
        return lines
    }
    func clustersTable() -> [String] {
        var header = ["id", "label"]
        for result in results {
            for j in 1...settings.cutHeights.count { header.append("\(result.method.rawValue)_h\(j)") }
            for k in settings.cutCounts { header.append("\(result.method.rawValue)_k\(k)") }
        }
        var lines = [header.joined(separator: ",")]
        for i in 0..<n {
            var fields = [ids[i], labels[i]]
            for result in results { for cut in result.heightCuts + result.countCuts { fields.append(String(cut.partition[i])) } }
            lines.append(fields.joined(separator: ","))
        }
        return lines
    }
    func dendrogramReport() -> [String] {
        var parts: [[String]] = []
        for result in results {
            let tree = result.tree, maximum = result.tree.heights.max()!
            let cuts = settings.cutHeights.map { column($0, maximum, settings.width) }
            var lines = ["dendrogram \(result.method.rawValue) height_max \(real(maximum)) width \(settings.width)"]
            lines.append(contentsOf: dendrogramRows(tree.merges, tree.children, tree.order, ids, labels, maximum, cuts, settings.width))
            for (height, x) in zip(settings.cutHeights, cuts) { lines.append("cut \(real(height)) column \(x <= settings.width ? String(x) : "-")") }
            parts.append(lines)
        }
        return joinParts(parts)
    }
    func treesReport() -> [String] { results.map { "\($0.method.rawValue) \($0.tree.newick($0.tree.root, ids));" } }
    func pairText(_ pair: (Int, Int)) -> String { "\(real(delta[pair.0][pair.1])) \(ids[pair.0]) \(ids[pair.1])" }
    func dataPart() -> [String] {
        var lines = ["data n \(n) features \(features.count) classes \(classes.count) distance \(settings.distance.rawValue) standardize \(settings.standardize ? "yes" : "no")"]
        for f in features.indices { lines.append("feature \(features[f]) mean \(real(means[f])) sd \(real(deviations[f]))") }
        var smallest = (0, 1), largest = (0, 1)
        for i in 0..<n { for j in (i + 1)..<n {
            if delta[i][j] < delta[smallest.0][smallest.1] { smallest = (i, j) }
            if delta[i][j] > delta[largest.0][largest.1] { largest = (i, j) }
        } }
        lines.append("distances pairs \(pairs.count) min \(pairText(smallest)) max \(pairText(largest)) mean \(real(sequentialSum(pairs) / Double(pairs.count)))")
        let nearestMean = sequentialSum((0..<n).map { delta[$0][neighbors[$0]] }) / Double(n)
        let reciprocal = (0..<n).filter { $0 < neighbors[$0] && neighbors[neighbors[$0]] == $0 }.count
        lines.append("nearest_neighbors mean \(real(nearestMean)) reciprocal_pairs \(reciprocal)")
        lines.append("labels " + evaluate(targets.map { $0 + 1 }).text)
        return lines
    }
    func correlationPart() -> [String] {
        let columns = features.indices.map { f in raw.map { $0[f] } }
        var lines = ["correlation " + features.joined(separator: " ")]
        for (f, first) in columns.enumerated() { lines.append(features[f] + " " + reals(columns.map { correlation(first, $0) })) }
        return lines
    }
    func histogramPart() -> [String] {
        var counts = Array(repeating: 0, count: 10)
        for value in pairs { counts[histogramBin(value, distanceMax)] += 1 }
        let highest = counts.max()!
        var lines = ["histogram"]
        for (b, count) in counts.enumerated() {
            var line = "\(real(Double(b) * distanceMax / 10.0)) \(real(Double(b + 1) * distanceMax / 10.0)) \(count)"
            let length = count * 50 / highest
            if length > 0 { line += " " + String(repeating: "#", count: length) }
            lines.append(line)
        }
        return lines
    }
    func inconsistencyLine(_ tree: Tree, _ step: Int) -> String {
        let sequence = tree.heightSequence(step, settings.inconsistencyDepth)
        let size = sequence.count
        let mean = sequentialSum(sequence) / Double(size)
        let deviation = size == 1 ? 0.0 : sqrt(sequentialSum(sequence.map { ($0 - mean) * ($0 - mean) }) / Double(size - 1))
        let coefficient = size == 1 ? 0.0 : (tree.merges[step].height - mean) / deviation
        return "step \(step + 1) height \(real(tree.merges[step].height)) mean \(real(mean)) sd \(real(deviation)) count \(size) coefficient \(real(coefficient))"
    }
    func linkagePart(_ result: LinkageResult) -> [String] {
        let tree = result.tree, heights = result.tree.heights
        let leafPath = sequentialSum((0..<(n - 1)).map { delta[tree.order[$0]][tree.order[$0 + 1]] })
        let inversions = (1..<(n - 1)).filter { heights[$0] < heights[$0 - 1] }
        var lines = ["linkage \(result.method.rawValue)", "cophenetic \(real(result.correlation)) leaf_path \(real(leafPath))", "heights min \(real(heights.min()!)) max \(real(heights.max()!)) inversions \(inversions.count)"]
        for step in inversions { lines.append("inversion step \(step + 1) height \(real(heights[step])) previous \(real(heights[step - 1]))") }
        let ordered = tree.subtreeHeights.sorted()
        let gaps = (2...settings.gapMaxK).map { ordered[n - $0] - ordered[n - $0 - 1] }
        var suggested = 2
        if settings.gapMaxK >= 3 {
            for k in 3...settings.gapMaxK where fourDigit(gaps[k - 2]) > fourDigit(gaps[suggested - 2]) { suggested = k }
        }
        lines.append("gaps " + reals(gaps))
        lines.append("suggested_k \(suggested)")
        let joining = tree.joiningHeights()
        let late = (0..<n).sorted { joining[$0] == joining[$1] ? $0 < $1 : joining[$0] > joining[$1] }.prefix(settings.listSize)
        lines.append("late_joiners " + late.map { "\(ids[$0]):\(real(joining[$0]))" }.joined(separator: " "))
        var kinds = [0, 0, 0]
        for merge in tree.merges { let leaves = (merge.a < n ? 1 : 0) + (merge.b < n ? 1 : 0); kinds[2 - leaves] += 1 }
        lines.append("merges leaf_leaf \(kinds[0]) leaf_cluster \(kinds[1]) cluster_cluster \(kinds[2]) depth \(tree.depths[tree.root])")
        let matches = matchCount(result.labelPartition)
        lines.append("label_cut k \(classes.count) purity \(matches)/\(n) \(real(Double(matches) / Double(n)))")
        lines.append("inconsistency depth \(settings.inconsistencyDepthText)")
        for step in (n - settings.inconsistencyCount - 1)..<(n - 1) { lines.append(inconsistencyLine(tree, step)) }
        for (height, cut) in zip(settings.cutHeights, result.heightCuts) { lines.append("cut height \(real(height)) clusters \(cut.sizes.count) \(cut.text)") }
        for (k, cut) in zip(settings.cutCounts, result.countCuts) { lines.append("cut k \(k) \(cut.text)") }
        return lines
    }
    func mstPart(_ single: LinkageResult) -> [String] {
        let edges = minimumSpanningTree(delta)
        let total = sequentialSum(edges.map(\.weight))
        let weights = edges.map(\.weight).sorted()
        let heightsMatch = zip(weights, single.tree.heights).allSatisfy { a, b in abs(a - b) <= 0.000000001 }
        var linked = Array(repeating: Array(repeating: false, count: n), count: n)
        for edge in edges { linked[edge.parent][edge.child] = true; linked[edge.child][edge.parent] = true }
        let nnEdges = (0..<n).filter { linked[$0][neighbors[$0]] }.count
        var lines = ["mst total \(real(total)) heights \(heightsMatch ? "match" : "mismatch") nn_edges \(nnEdges)/\(n)"]
        let ordered = edges.indices.sorted { edges[$0].weight == edges[$1].weight ? $0 < $1 : edges[$0].weight < edges[$1].weight }
        for (k, cut) in zip(settings.cutCounts, single.countCuts) {
            var components = Array(0..<n)
            for number in ordered.prefix(n - k) {
                let edge = edges[number]
                let old = components[edge.child], new = components[edge.parent]
                for u in 0..<n where components[u] == old { components[u] = new }
            }
            var agrees = true
            for i in 0..<n { for j in (i + 1)..<n {
                if (components[i] == components[j]) != (cut.partition[i] == cut.partition[j]) { agrees = false }
            } }
            lines.append("mst partition k \(k) \(agrees ? "match" : "mismatch")")
        }
        return lines
    }
    func comparePart() -> [String] {
        var lines = ["compare linkage \(settings.compareLinkage.rawValue) k \(classes.count)"]
        for kind in DistanceKind.allCases {
            let distances = distanceMatrix(vectors, kind)
            let tree = Tree(agglomerate(distances, settings.compareLinkage), n)
            let cophenetic = correlation(pairValues(distances), pairValues(tree.cophenetic()))
            let partition = tree.cutInto(classes.count)
            lines.append("metric \(kind.rawValue) cophenetic \(real(cophenetic)) silhouette \(optionalReal(meanSilhouette(partition, distances))) ari \(ariText(labelARI(partition)))")
        }
        return lines
    }
    func copheneticPart() -> [String] {
        var lines = ["cophenetic_matrix", "linkage " + settings.linkages.map(\.rawValue).joined(separator: " ")]
        for first in results { lines.append(first.method.rawValue + " " + reals(results.map { correlation(first.cophenetic, $0.cophenetic) })) }
        return lines
    }
    func agreementPart() -> [String] {
        var lines = ["agreement k \(classes.count)", "linkage " + settings.linkages.map(\.rawValue).joined(separator: " ")]
        for first in results { lines.append(first.method.rawValue + " " + reals(results.map { partitionARI(first.labelPartition, $0.labelPartition).value })) }
        return lines
    }
    func summaryPart() -> [String] {
        let ranking = results.indices.sorted {
            let a = fourDigit(results[$0].correlation), b = fourDigit(results[$1].correlation)
            return a == b ? $0 < $1 : a > b
        }
        var lines = ["summary", "cophenetic_ranking " + ranking.map { results[$0].method.rawValue }.joined(separator: " ")]
        for (position, k) in settings.cutCounts.enumerated() {
            var best = 0
            for r in 1..<results.count { if results[r].countCuts[position].ari.greater(results[best].countCuts[position].ari) { best = r } }
            lines.append("best_ari k \(k) \(results[best].method.rawValue) \(ariText(results[best].countCuts[position].ari))")
        }
        for result in results {
            var best = 0
            for position in 1..<settings.cutCounts.count { if fourDigit(result.countCuts[position].silhouette!) > fourDigit(result.countCuts[best].silhouette!) { best = position } }
            lines.append("best_silhouette \(result.method.rawValue) k \(settings.cutCounts[best]) \(optionalReal(result.countCuts[best].silhouette))")
        }
        lines.append("selected \(chosen.method.rawValue) k \(kappa)")
        return lines
    }
    func validationReport() -> [String] {
        var parts = [dataPart(), correlationPart(), histogramPart()]
        for result in results { parts.append(linkagePart(result)) }
        if let single = results.first(where: { $0.method == .single }) { parts.append(mstPart(single)) }
        parts.append(contentsOf: [comparePart(), copheneticPart(), agreementPart(), summaryPart()])
        return joinParts(parts)
    }
    func separation(_ first: [Int], _ second: [Int]) -> Double {
        var best = Double.infinity
        for i in first { for j in second { best = min(best, delta[i][j]) } }
        return best
    }
    func selectionPart() -> [String] {
        let groups = members, table = classTable(selected), silhouettes = silhouetteValues(selected, kappa, delta)
        var lines = ["selected linkage \(chosen.method.rawValue) k \(kappa) ari \(ariText(selectedCut.ari)) silhouette \(optionalReal(selectedCut.silhouette))"]
        for (g, group) in groups.enumerated() {
            let size = group.count, silhouette = sequentialSum(group.map { silhouettes[$0] }) / Double(group.count)
            let majority = majorityClass(table[g])
            let count = table[g][majority]
            let means = features.indices.map { f in sequentialSum(group.map { raw[$0][f] }) / Double(size) }
            var medoid = group[0], medoidSum = Double.infinity
            for i in group {
                let total = sequentialSum(group.map { delta[i][$0] })
                if total < medoidSum { medoid = i; medoidSum = total }
            }
            var widest: (Int, Int)? = nil
            for (position, i) in group.enumerated() { for j in group.dropFirst(position + 1) {
                if widest == nil || delta[i][j] > delta[widest!.0][widest!.1] { widest = (i, j) }
            } }
            let diameter = widest.map(pairText) ?? "0.0000 - -"
            var nearest = 0, nearestSeparation = Double.infinity
            for (h, other) in groups.enumerated() where h != g {
                let value = separation(group, other)
                if value < nearestSeparation { nearest = h; nearestSeparation = value }
            }
            lines.append("cluster \(g + 1) size \(size) silhouette \(real(silhouette)) majority \(classes[majority]) purity \(count)/\(size) \(real(Double(count) / Double(size)))")
            lines.append("  mean " + reals(means))
            lines.append("  medoid \(ids[medoid]) diameter \(diameter) nearest \(nearest + 1) separation \(real(nearestSeparation))")
        }
        return lines
    }
    func centroidPart() -> [String] {
        let centers = centroids(selected)
        var lines = ["centroid_distances"]
        for (g, first) in centers.enumerated() { lines.append("\(g + 1) " + reals(centers.map { sqrt(squaredDistance(first, $0)) })) }
        return lines
    }
    func profilePart() -> [String] {
        let width = features.map(\.count).max()!
        var lines = ["profile_bars"]
        for (g, group) in members.enumerated() {
            lines.append("cluster \(g + 1)")
            for (f, name) in features.enumerated() {
                let zeta = sequentialSum(group.map { (raw[$0][f] - means[f]) / deviations[f] }) / Double(group.count)
                let length = min(10, Int(floor(abs(zeta) * 4.0)))
                let bar = String(repeating: "#", count: length)
                let left = zeta < 0 ? String(repeating: " ", count: 10 - length) + bar : String(repeating: " ", count: 10)
                let right = zeta < 0 ? String(repeating: " ", count: 10) : bar + String(repeating: " ", count: 10 - length)
                lines.append(name.padding(toLength: width, withPad: " ", startingAt: 0) + " " + left + "|" + right + " " + real(zeta))
            }
        }
        return lines
    }
    func contingencyPart() -> [String] {
        let table = classTable(selected)
        var lines = ["contingency", "cluster " + classes.joined(separator: " ") + " total"]
        for (g, row) in table.enumerated() { lines.append("\(g + 1) \(integers(row)) \(row.reduce(0, +))") }
        let totals = classes.indices.map { t in table.reduce(0) { $0 + $1[t] } }
        lines.append("total \(integers(totals)) \(n)")
        let matches = matchCount(selected)
        lines.append("purity \(matches)/\(n) \(real(Double(matches) / Double(n)))")
        return lines
    }
    func misplacedPart() -> [String] {
        let majority = classTable(selected).map(majorityClass)
        var lines = ["misplaced"], count = 0
        for (i, number) in selected.enumerated() where targets[i] != majority[number - 1] {
            count += 1
            lines.append("\(ids[i]) label \(labels[i]) cluster \(number) majority \(classes[majority[number - 1]])")
        }
        lines.append("count \(count)")
        return lines
    }
    func weakestPart() -> [String] {
        let silhouettes = silhouetteValues(selected, kappa, delta)
        let order = (0..<n).sorted { silhouettes[$0] == silhouettes[$1] ? $0 < $1 : silhouettes[$0] < silhouettes[$1] }
        var lines = ["weakest"]
        for i in order.prefix(settings.listSize) { lines.append("\(ids[i]) label \(labels[i]) cluster \(selected[i]) silhouette \(real(silhouettes[i]))") }
        return lines
    }
    func featurePart() -> [String] {
        let groups = members
        var ratios: [Double] = []
        for f in features.indices {
            let overall = sequentialSum(vectors.map { $0[f] }) / Double(n)
            let clusterMeans = groups.map { group in sequentialSum(group.map { vectors[$0][f] }) / Double(group.count) }
            let between = sequentialSum(zip(groups, clusterMeans).map { group, mean in Double(group.count) * (mean - overall) * (mean - overall) })
            let within = sequentialSum(selected.enumerated().map { i, number in (vectors[i][f] - clusterMeans[number - 1]) * (vectors[i][f] - clusterMeans[number - 1]) })
            ratios.append((between / Double(kappa - 1)) / (within / Double(n - kappa)))
        }
        let ranking = ratios.indices.sorted { fourDigit(ratios[$0]) == fourDigit(ratios[$1]) ? $0 < $1 : fourDigit(ratios[$0]) > fourDigit(ratios[$1]) }
        var lines = ["features"]
        for (rank, f) in ranking.enumerated() { lines.append("\(rank + 1) \(features[f]) f_ratio \(real(ratios[f]))") }
        return lines
    }
    func classCounts(_ tree: Tree, _ node: Int) -> String {
        var counts = Array(repeating: 0, count: classes.count)
        for i in tree.members[node] { counts[targets[i]] += 1 }
        return counts.map(String.init).joined(separator: "/")
    }
    func topMergesPart() -> [String] {
        let tree = chosen.tree
        var lines = ["top_merges"]
        for step in (n - settings.inconsistencyCount - 1)..<(n - 1) {
            let merge = tree.merges[step]
            lines.append("step \(step + 1) height \(real(merge.height)) a \(merge.a) \(tree.members[merge.a].count) \(classCounts(tree, merge.a)) b \(merge.b) \(tree.members[merge.b].count) \(classCounts(tree, merge.b))")
        }
        return lines
    }
    func dropFeaturePart() -> [String] {
        var lines = ["drop_feature"]
        for (f, name) in features.enumerated() {
            let reduced = vectors.map { vector in vector.enumerated().compactMap { j, value in j == f ? nil : value } }
            let distances = distanceMatrix(reduced, settings.distance)
            let partition = Tree(agglomerate(distances, chosen.method), n).cutInto(kappa)
            lines.append("\(name) ari_selected \(ariText(partitionARI(partition, selected))) ari_labels \(ariText(labelARI(partition)))")
        }
        return lines
    }
    func refinementPart() -> [String] {
        let limit = settings.refineIterations
        var centers = centroids(selected), previous = selected, iterations = limit
        for t in 1...limit {
            let assignment = vectors.map { vector -> Int in
                var best = 0, bestValue = squaredDistance(vector, centers[0])
                for g in 1..<centers.count {
                    let value = squaredDistance(vector, centers[g])
                    if value < bestValue { best = g; bestValue = value }
                }
                return best + 1
            }
            if assignment == previous { iterations = t; break }
            for (g, group) in clusterMembers(assignment, kappa).enumerated() where !group.isEmpty { centers[g] = centroid(group.map { vectors[$0] }) }
            previous = assignment
        }
        let changed = zip(selected, previous).filter { before, after in before != after }.count
        let sizes = clusterMembers(previous, kappa).map(\.count)
        return ["refinement max_iterations \(limit)", "iterations \(iterations) changed \(changed) wss \(real(withinSum(selected))) -> \(real(withinSum(previous)))", "sizes \(integers(sizes)) silhouette \(optionalReal(meanSilhouette(previous, delta)))", "ari_selected \(ariText(partitionARI(previous, selected))) ari_labels \(ariText(labelARI(previous)))"]
    }
    func jaccard(_ partition: [Int], _ restricted: [Int]) -> [Double] {
        let table = contingencyTable(restricted.map { $0 - 1 }, partition.map { $0 - 1 }, kappa, partition.max()!)
        let totals = table[0].indices.map { h in table.reduce(0) { $0 + $1[h] } }
        return table.map { row in
            let size = row.reduce(0, +)
            var best = Fraction(numerator: 0, denominator: 1)
            if size > 0 { for (h, common) in row.enumerated() {
                let candidate = Fraction(numerator: common, denominator: size + totals[h] - common)
                if candidate.greater(best) { best = candidate }
            } }
            return best.value
        }
    }
    func stabilityPart() -> [String] {
        var generator = Minstd(state: settings.seed)
        let size = n * settings.percent / 100
        var aris: [Double] = [], jaccards: [[Double]] = []
        var lines = ["stability replicates \(settings.replicates) percent \(settings.percent) seed \(settings.seed)"]
        for b in 1...settings.replicates {
            var array = Array(0..<n)
            for t in 0..<size { let j = t + generator.draw() % (n - t); array.swapAt(t, j) }
            let sample = array.prefix(size).sorted()
            let distances = sample.map { u in sample.map { delta[u][$0] } }
            let partition = Tree(agglomerate(distances, chosen.method), size).cutInto(kappa)
            let restricted = sample.map { selected[$0] }
            let ari = partitionARI(partition, restricted)
            let coefficients = jaccard(partition, restricted)
            lines.append("replicate \(b) size \(size) ari \(ariText(ari)) jaccard \(reals(coefficients))")
            aris.append(ari.value)
            jaccards.append(coefficients)
        }
        lines.append("mean_ari " + real(sequentialSum(aris) / Double(settings.replicates)))
        lines.append("mean_jaccard " + reals((0..<kappa).map { g in sequentialSum(jaccards.map { $0[g] }) / Double(settings.replicates) }))
        return lines
    }
    func distanceMapPart() -> [String] {
        let order = chosen.tree.order, frame = "+" + String(repeating: "-", count: n) + "+"
        let shades = Array("@%#*+=-:. ")
        var lines = ["distance_map \(chosen.method.rawValue)", frame]
        for u in order { lines.append("|" + String(order.map { shades[histogramBin(delta[u][$0], distanceMax)] }) + "|") }
        lines.append(frame)
        return lines
    }
    func profilesReport() -> [String] {
        joinParts([selectionPart(), centroidPart(), profilePart(), contingencyPart(), misplacedPart(), weakestPart(), featurePart(), topMergesPart(), dropFeaturePart(), refinementPart(), stabilityPart(), distanceMapPart()])
    }
}

let (features, observations) = try readObservations()
let settings = try readSettings()
let study = Study(features, observations, settings)
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
try writeLines("linkage.csv", study.linkageTable())
try writeLines("clusters.csv", study.clustersTable())
try writeLines("dendrogram.txt", study.dendrogramReport())
try writeLines("trees.txt", study.treesReport())
try writeLines("validation.txt", study.validationReport())
try writeLines("profiles.txt", study.profilesReport())
