import Foundation

let njMethods = ["NJ_P", "NJ_JC", "NJ_K2P"]
let methods = njMethods + ["ME", "MP", "CONSENSUS"]
struct Settings { var model = DistanceModel.p; var outgroup = ""; var replicates = 0; var seed = 0; var maximumMissing = 0; var saturation = 0.0; var exhaustiveTaxa: [String] = []; var lowSites = 0 }
struct Rejection { let line: Int; let name: String; let reason: String }
struct CheckedAlignment { let names: [String]; let sequences: [[UInt8]]; let rejected: [Rejection]; let length: Int }
func readTextLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init) }
func readParameters() throws -> Settings { var settings = Settings(); for line in try readTextLines("params.txt") { let fields = line.split(separator: " ").map(String.init); switch fields[0] { case "model": settings.model = DistanceModel(rawValue: fields[1])!; case "outgroup": settings.outgroup = fields[1]; case "replicates": settings.replicates = Int(fields[1])!; case "seed": settings.seed = Int(fields[1])!; case "max_missing_percent": settings.maximumMissing = Int(fields[1])!; case "saturation_distance": settings.saturation = Double(fields[1])!; case "exhaustive_taxa": settings.exhaustiveTaxa = Array(fields.dropFirst()); default: settings.lowSites = Int(fields[1])! } }; return settings }
func checkRecords(_ records: [FastaRecord], _ maximumMissing: Int) -> CheckedAlignment {
    let length = records[0].sequence.count
    var seen: Set<String> = [], names: [String] = [], sequences: [[UInt8]] = [], rejected: [Rejection] = []
    for record in records { var reason: String?; if seen.contains(record.name) { reason = "duplicate name" }; seen.insert(record.name); if reason == nil, let index = record.sequence.firstIndex(where: { baseSets[$0] == nil }) { reason = "invalid character \(String(UnicodeScalar(record.sequence[index]))) at column \(index + 1)" }; if reason == nil && record.sequence.count != length { reason = "length mismatch \(record.sequence.count)" }; if reason == nil { let missing = record.sequence.filter { $0 == 45 || $0 == 78 }.count; if 100 * missing > maximumMissing * length { reason = "too many missing \(missing)" } }; if let reason { rejected.append(Rejection(line: record.headerLine, name: record.name, reason: reason)) } else { names.append(record.name); sequences.append(record.sequence) } }
    return CheckedAlignment(names: names, sequences: sequences, rejected: rejected, length: length)
}
func orderedSum<S: Sequence>(_ values: S) -> Double where S.Element == Double { var result = 0.0; for value in values { result += value }; return result }
func summaryLines(_ records: [FastaRecord], _ alignment: CheckedAlignment, _ patterns: Patterns) -> [String] {
    let names = alignment.names, sequences = alignment.sequences, columns = (0..<alignment.length).map { column -> [UInt8: Int] in var counts: [UInt8: Int] = [:]; for sequence in sequences where baseSymbols.contains(sequence[column]) { counts[sequence[column], default: 0] += 1 }; return counts }
    var lines = ["INPUT records \(records.count) accepted \(names.count) rejected \(alignment.rejected.count) columns \(alignment.length)"] + alignment.rejected.map { "REJECT line \($0.line) \($0.name) \($0.reason)" }, composition = [0, 0, 0, 0]
    for (index, sequence) in sequences.enumerated() { var counts: [UInt8: Int] = [:]; for value in sequence { counts[value, default: 0] += 1 }; let bases = baseSymbols.reduce(0) { $0 + counts[$1, default: 0] }, ambiguous = ambiguitySymbols.reduce(0) { $0 + counts[$1, default: 0] }, missing = counts[45, default: 0] + counts[78, default: 0], unique = sequence.indices.filter { baseSymbols.contains(sequence[$0]) && columns[$0][sequence[$0], default: 0] == 1 && columns[$0].values.reduce(0, +) > 1 }.count, gc = Double(counts[67, default: 0] + counts[71, default: 0]) / Double(bases); lines.append("TAXON \(names[index]) bases \(bases) ambiguous \(ambiguous) missing \(missing) unique \(unique) gc \(real(gc, 4))"); for (i, base) in baseSymbols.enumerated() { composition[i] += counts[base, default: 0] } }
    let classes = classifyColumns(sequences), total = composition.reduce(0, +)
    lines += ["COLUMNS constant \(classes.constant) variable \(classes.variable) informative \(classes.informative) gapped \(classes.gapped) empty \(classes.empty)", "PATTERNS \(patterns.patterns.count)", "COMPOSITION " + baseSymbols.indices.map { "\(String(UnicodeScalar(baseSymbols[$0]))) \(real(Double(composition[$0]) / Double(total), 4))" }.joined(separator: " ")]
    return lines
}
func matrixLines(_ names: [String], _ matrix: [[Double]]) -> [String] { let width = names.map { $0.count }.max()!; return names.indices.map { names[$0] + String(repeating: " ", count: width - names[$0].count) + " " + matrix[$0].map { real($0, 5) }.joined(separator: " ") } }
struct ParsimonyBounds { let minimum: Int; let maximum: Int; let minima: [Int] }
func parsimonyBounds(_ patterns: Patterns) -> ParsimonyBounds { var minima: [Int] = [], maximum = 0; for (index, pattern) in patterns.encoded.enumerated() { let minimum = (1..<16).filter { mask in pattern.allSatisfy { mask & $0 != 0 } }.map { $0.nonzeroBitCount }.min()! - 1, greatest = [1, 2, 4, 8].map { base in pattern.filter { $0 & base == 0 }.count }.min()!; minima.append(minimum); maximum += greatest * patterns.weights[index] }; let columns = patterns.columns.map { minima[$0] }; return ParsimonyBounds(minimum: columns.reduce(0, +), maximum: maximum, minima: columns) }
func bmeLength(_ tree: Tree, _ matrix: [[Double]]) -> Double { let taxa = tree.taxa; var total = 0.0; for (index, first) in taxa.enumerated() { let steps = pathSteps(tree, first); for second in taxa.dropFirst(index + 1) { total += matrix[first][second] / Double(1 << (steps[second]! - 1)) } }; return total }
struct Addition { let taxon: Int; let mask: Int; let score: Int; let ties: Int }
struct StepwiseResult { let tree: Tree; let initial: Int; let score: Int; let additions: [Addition]; let evaluated: Int; let taxa: [Int] }
func stepwise(_ taxa: [Int], _ size: Int, _ patterns: Patterns, _ outgroup: Int) -> StepwiseResult {
    var tree = star(size, Array(taxa.prefix(3)))
    let initial = parsimonyScore(tree, patterns, outgroup)
    var current = initial, additions: [Addition] = [], evaluated = 0
    for taxon in taxa.dropFirst(3) { var best: Int?, chosen: Tree?, mask = 0, ties = 0; for branch in branches(tree, outgroup) { let candidate = insert(tree, branch.parent, branch.child, taxon), value = parsimonyScore(candidate, patterns, outgroup); evaluated += 1; if best == nil || value < best! { best = value; chosen = candidate; mask = branch.mask; ties = 1 } else if value == best! { ties += 1 } }; tree = chosen!; current = best!; additions.append(Addition(taxon: taxon, mask: mask, score: current, ties: ties)) }
    return StepwiseResult(tree: tree, initial: initial, score: current, additions: additions, evaluated: evaluated, taxa: taxa)
}
struct Move<Value> { let mask: Int; let swap: Int; let value: Value }
struct HillResult<Value> { var tree: Tree; let value: Value; let moves: [Move<Value>]; let evaluated: Int }
func hillClimb<Value: Comparable>(_ initial: Tree, _ objective: (Tree) -> Value, _ outgroup: Int, _ initialValue: Value) -> HillResult<Value> {
    var tree = initial, value = initialValue, evaluated = 0, moves: [Move<Value>] = []
    while true { var improved = false; for candidate in nniCandidates(tree, outgroup) { let next = objective(candidate.tree); evaluated += 1; if next < value { tree = candidate.tree; value = next; moves.append(Move(mask: candidate.mask, swap: candidate.swap, value: next)); improved = true; break } }; if !improved { break } }
    return HillResult(tree: tree, value: value, moves: moves, evaluated: evaluated)
}
func consensusTree(_ size: Int, _ taxa: [Int], _ clades: Set<Int>) -> Tree {
    var tree = Tree(size, taxa)
    let root = tree.internalNode()
    var nodes: [Int: Int] = [:]
    for mask in clades.sorted() { nodes[mask] = tree.internalNode() }
    for mask in clades.sorted() { let containers = clades.filter { $0 != mask && $0 & mask == mask }, parent = containers.min { $0.nonzeroBitCount == $1.nonzeroBitCount ? $0 < $1 : $0.nonzeroBitCount < $1.nonzeroBitCount }.map { nodes[$0]! } ?? root; tree.connect(parent, nodes[mask]!) }
    for taxon in taxa { let containers = clades.filter { $0 & (1 << taxon) != 0 }, parent = containers.min { $0.nonzeroBitCount == $1.nonzeroBitCount ? $0 < $1 : $0.nonzeroBitCount < $1.nonzeroBitCount }.map { nodes[$0]! } ?? root; tree.connect(parent, taxon) }
    return tree
}
struct ExhaustiveRecord { let tree: Tree; let score: Int; let bme: Double; let newick: String; let splits: Set<Int> }
struct ExhaustiveResult { let taxa: [Int]; let records: [ExhaustiveRecord]; let histogram: [Int: Int]; let bestScore: Int; let optimal: [ExhaustiveRecord]; let strict: Tree; let bestBME: ExhaustiveRecord; let secondBME: Double; let heuristic: Int }
func exhaustiveSearch(_ taxa: [Int], _ names: [String], _ patterns: Patterns, _ outgroup: Int, _ matrix: [[Double]]) -> ExhaustiveResult {
    var trees = [star(names.count, Array(taxa.prefix(3)))]
    for taxon in taxa.dropFirst(3) { var expanded: [Tree] = []; for tree in trees { for branch in branches(tree, outgroup) { expanded.append(insert(tree, branch.parent, branch.child, taxon)) } }; trees = expanded }
    var records: [ExhaustiveRecord] = [], histogram: [Int: Int] = [:]
    for tree in trees { let score = parsimonyScore(tree, patterns, outgroup); histogram[score, default: 0] += 1; records.append(ExhaustiveRecord(tree: tree, score: score, bme: bmeLength(tree, matrix), newick: newick(tree, names, outgroup), splits: tree.rooted(outgroup).splits())) }
    let bestScore = histogram.keys.min()!, optimal = records.filter { $0.score == bestScore }.sorted { $0.newick < $1.newick }
    var common = optimal[0].splits
    for record in optimal.dropFirst() { common.formIntersection(record.splits) }
    let strict = consensusTree(names.count, taxa, common), order = records.indices.sorted { records[$0].bme == records[$1].bme ? records[$0].newick < records[$1].newick : records[$0].bme < records[$1].bme }, bestBME = records[order[0]], second = order.dropFirst().map { records[$0].bme }.min()!, initial = stepwise(taxa, names.count, patterns, outgroup), heuristic = hillClimb(initial.tree, { parsimonyScore($0, patterns, outgroup) }, outgroup, initial.score)
    return ExhaustiveResult(taxa: taxa, records: records, histogram: histogram, bestScore: bestScore, optimal: optimal, strict: strict, bestBME: bestBME, secondBME: second, heuristic: heuristic.value)
}
func likelihoodSites(_ tree: Tree, _ names: [String], _ patterns: Patterns, _ outgroup: Int) -> [Double] {
    let rooted = tree.rooted(outgroup), children = childOrder(rooted, names)
    var transition: [Int: [[Double]]] = [:], values: [Double] = []
    for node in rooted.order.dropFirst() { let length = tree.adjacent[node]![rooted.parents[node]!]!, exponential = exp(-(4 * length) / 3), same = 1.0 / 4 + (3.0 / 4) * exponential, different = 1.0 / 4 - (1.0 / 4) * exponential; transition[node] = (0..<4).map { first in (0..<4).map { first == $0 ? same : different } } }
    for pattern in patterns.encoded { var partial: [Int: [Double]] = [:], upward: [Int: [Double]] = [:]; for node in rooted.order.reversed() { if node < tree.size { partial[node] = (0..<4).map { pattern[node] & (1 << $0) != 0 ? 1 : 0 } } else { var row = [1.0, 1, 1, 1]; for child in children[node]! { for base in 0..<4 { row[base] *= upward[child]![base] } }; partial[node] = row }; if node != rooted.root { upward[node] = (0..<4).map { first in orderedSum((0..<4).map { transition[node]![first][$0] * partial[node]![$0] }) } } }; values.append(log(orderedSum(partial[rooted.root]!.map { (1.0 / 4) * $0 }))) }
    return patterns.columns.map { values[$0] }
}
func likelihoodLines(_ names: [String], _ patterns: Patterns, _ trees: [Tree], _ outgroup: Int, _ mainIndex: Int, _ lowCount: Int, _ siteLogs: [[Double]]) -> [String] {
    let length = patterns.columns.count
    var lines = ["LIKELIHOOD columns \(length) patterns \(patterns.patterns.count)"]
    for index in 0..<3 { let total = orderedSum(siteLogs[index]); lines.append("TREE \(njMethods[index]) loglik \(real(total, 4)) per_site \(real(total / Double(length), 4))") }
    for first in 0..<3 { for second in (first + 1)..<3 { let deltas = (0..<length).map { siteLogs[first][$0] - siteLogs[second][$0] }, difference = orderedSum(deltas), mean = difference / Double(length), standardError = sqrt((Double(length) / Double(length - 1)) * orderedSum(deltas.map { let value = $0 - mean; return value * value })); lines.append("KH \(njMethods[first]) \(njMethods[second]) difference \(real(difference, 4)) se \(real(standardError, 4)) z \(real(difference / standardError, 4))") } }
    let rounded = siteLogs[mainIndex].map { Double(real($0, 4))! }, lowest = (0..<length).sorted { rounded[$0] == rounded[$1] ? $0 < $1 : rounded[$0] < rounded[$1] }, changes = patternScores(trees[mainIndex], patterns, outgroup)
    lines.append("LOWEST \(njMethods[mainIndex]) sites \(lowCount)")
    for column in lowest.prefix(lowCount) { let index = patterns.columns[column]; lines.append("SITE \(column + 1) loglik \(real(siteLogs[mainIndex][column], 4)) changes \(changes[index]) pattern \(patterns.patterns[index])") }
    return lines
}
struct BootstrapResult { let consensus: Tree; let support: [Int: Int]; let lines: [String] }
func bootstrap(_ names: [String], _ sequences: [[UInt8]], _ settings: Settings, _ mainTree: Tree, _ mainMatrix: [[Double]], _ outgroup: Int) -> BootstrapResult {
    let count = names.count, length = sequences[0].count, mainSplits = mainTree.rooted(outgroup).splits()
    var state = Int64(settings.seed), support: [Int: Int] = [:], lines = ["BOOTSTRAP model \(settings.model.rawValue) replicates \(settings.replicates) seed \(settings.seed)"], identical = 0
    for replicate in 1...settings.replicates { var weights = Array(repeating: 0, count: length); for _ in 0..<length { state = 48271 * state % 2147483647; weights[Int(state % Int64(length))] += 1 }; let pairs = allPairs(sequences, weights), matrix = buildMatrix(pairs, count, settings.model, settings.saturation).matrix, tree = neighborJoining(matrix, Array(0..<count)), splits = tree.rooted(outgroup).splits(), difference = splits.symmetricDifference(mainSplits).count; for mask in splits { support[mask, default: 0] += 1 }; if difference == 0 { identical += 1 }; lines.append("REPLICATE \(replicate) distinct \(weights.filter { $0 > 0 }.count) rf \(difference)") }
    lines.append("IDENTICAL \(identical)")
    for mask in mainSplits.sorted(by: { symbols($0, count) < symbols($1, count) }) { lines.append("SUPPORT \(symbols(mask, count)) \(support[mask, default: 0])") }
    for mask in support.keys.sorted(by: { support[$0]! == support[$1]! ? symbols($0, count) < symbols($1, count) : support[$0]! > support[$1]! }) { lines.append("SPLIT \(symbols(mask, count)) \(support[mask]!)") }
    let majority = Set(support.keys.filter { 2 * support[$0]! > settings.replicates }), consensus = consensusTree(count, Array(0..<count), majority)
    lines.append("CONSENSUS " + newick(consensus, names, outgroup, support: support))
    for taxon in 0..<count where taxon != outgroup { let taxa = (0..<count).filter { $0 != taxon }, tree = neighborJoining(mainMatrix, taxa), reduced = Set(mainSplits.map { $0 & ~(1 << taxon) }.filter { $0.nonzeroBitCount >= 2 && $0.nonzeroBitCount <= count - 3 }); lines.append("JACKKNIFE \(names[taxon]) rf \(tree.rooted(outgroup).splits().symmetricDifference(reduced).count)") }
    return BootstrapResult(consensus: consensus, support: support, lines: lines)
}
func clockLines(_ names: [String], _ sequences: [[UInt8]], _ outgroup: Int, _ mainIndex: Int, _ mainTree: Tree) -> [String] {
    let ingroup = names.indices.filter { $0 != outgroup }
    var pairs: [String] = [], rejected = 0
    for (index, first) in ingroup.enumerated() { for second in ingroup.dropFirst(index + 1) { var m1 = 0, m2 = 0; for column in sequences[0].indices { let a = sequences[first][column], b = sequences[second][column], o = sequences[outgroup][column]; if baseSymbols.contains(a) && baseSymbols.contains(b) && baseSymbols.contains(o) && a != b { if b == o { m1 += 1 }; if a == o { m2 += 1 } } }; let difference = m1 - m2, reject = 1000 * difference * difference > 3841 * (m1 + m2), chi = m1 + m2 == 0 ? "-" : real(Double(difference * difference) / Double(m1 + m2), 4); if reject { rejected += 1 }; pairs.append("RRT \(names[first]) \(names[second]) m1 \(m1) m2 \(m2) chi2 \(chi) \(reject ? "reject" : "ok")") } }
    let paths = pathDistances(mainTree, mainTree.rooted(outgroup).root), mean = orderedSum(ingroup.map { paths[$0]! }) / Double(ingroup.count), deviation = sqrt(orderedSum(ingroup.map { let value = paths[$0]! - mean; return value * value }) / Double(ingroup.count - 1))
    return ["RELATIVE_RATE outgroup \(names[outgroup]) pairs \(pairs.count) rejected \(rejected)"] + pairs + ["ROOT_TO_TIP \(njMethods[mainIndex]) mean \(real(mean, 5)) sd \(real(deviation, 5)) cv \(real(deviation / mean, 4))"] + ingroup.map { "TIP \(names[$0]) \(real(paths[$0]!, 5))" }
}
func quartetTopologies(_ splits: Set<Int>, _ count: Int) -> [Int] {
    var topologies: [Int] = []
    for a in 0..<count { for b in (a + 1)..<count { for c in (b + 1)..<count { for d in (c + 1)..<count { let quartet = (1 << a) | (1 << b) | (1 << c) | (1 << d); var topology = 0; for (index, other) in [b, c, d].enumerated() { let side = (1 << a) | (1 << other); if splits.contains(where: { let intersection = $0 & quartet; return intersection == side || intersection == (quartet ^ side) }) { topology = index + 1; break } }; topologies.append(topology) } } } }
    return topologies
}
func comparisonLines(_ names: [String], _ patterns: Patterns, _ trees: [Tree], _ matrices: [MatrixResult], _ mainMatrix: [[Double]], _ mainIndex: Int, _ outgroup: Int, _ support: [Int: Int], _ replicates: Int, _ njScores: [Int], _ mpScore: Int, _ mpChanges: [NodePair: Int], _ siteLogs: [[Double]], _ patristic: [[[Double]]]) -> [String] {
    let count = names.count, splits = trees.map { $0.rooted(outgroup).splits() }
    var lines: [String] = []
    for index in methods.indices {
        let tree = trees[index], supported = splits[index].filter { 2 * support[$0, default: 0] > replicates }.count
        var score = "-", bme = "-", length = "-", negative = "-", residual = "-", likelihood = "-"
        if index != 5 { let value = index < 3 ? njScores[index] : index == 4 ? mpScore : parsimonyScore(tree, patterns, outgroup); score = String(value); bme = real(bmeLength(tree, mainMatrix), 5) }
        if index < 3 { length = real(orderedSum(branches(tree, outgroup).map { tree.adjacent[$0.parent]![$0.child]! }), 5); negative = String(tree.negative); var errors: [Double] = []; for first in 0..<count { for second in (first + 1)..<count { let difference = matrices[index].matrix[first][second] - patristic[index][first][second]; errors.append(difference * difference) } }; residual = real(orderedSum(errors), 6); likelihood = real(orderedSum(siteLogs[index]), 4) }
        else if index == 4 { length = real(Double(mpScore) / Double(patterns.columns.count), 5) }
        lines.append("TREE \(methods[index]) splits \(splits[index].count) supported \(supported) parsimony \(score) bme \(bme) length \(length) negative \(negative) sse \(residual) loglik \(likelihood)")
    }
    lines.append("RF " + methods.joined(separator: " "))
    for first in methods.indices { lines.append(methods[first] + " " + methods.indices.map { String(splits[first].symmetricDifference(splits[$0]).count) }.joined(separator: " ")) }
    let quartets = splits.map { quartetTopologies($0, count) }
    lines.append("QUARTET " + methods.joined(separator: " "))
    for first in methods.indices { let values = methods.indices.map { second in quartets[first].indices.filter { quartets[first][$0] != quartets[second][$0] }.count }; lines.append(methods[first] + " " + values.map(String.init).joined(separator: " ")) }
    let allClades = Set(splits.flatMap { $0 }), lengths = trees[mainIndex].rooted(outgroup).branchLengths(), changes = Dictionary(uniqueKeysWithValues: branches(trees[4], outgroup).map { ($0.mask, mpChanges[NodePair($0.parent, $0.child)]!) })
    for mask in allClades.sorted(by: { symbols($0, count) < symbols($1, count) }) { let marks = splits.map { $0.contains(mask) ? "+" : "-" }.joined(), length = lengths[mask].map { real($0, 5) } ?? "-", change = changes[mask].map(String.init) ?? "-"; lines.append("CLADE \(symbols(mask, count)) support \(support[mask, default: 0]) trees \(marks) length \(length) changes \(change)") }
    return lines
}
func hypothesisLines(_ names: [String], _ trees: [Tree], _ outgroup: Int, _ support: [Int: Int], _ exhaustive: ExhaustiveResult) throws -> [String] {
    let numbers = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) }), ingroup = ((1 << names.count) - 1) ^ (1 << outgroup), exhaustiveIngroup = exhaustive.taxa.filter { $0 != outgroup }.reduce(0) { $0 | (1 << $1) }, splits = trees.map { $0.rooted(outgroup).splits() }
    var lines: [String] = []
    for line in try readTextLines("clades.txt") { let fields = line.split(separator: " ").map(String.init), hypothesis = fields[0], members = Array(fields.dropFirst()); if let unknown = members.first(where: { numbers[$0] == nil }) { lines.append("INVALID \(hypothesis) unknown taxon \(unknown)"); continue }; if members.contains(names[outgroup]) { lines.append("INVALID \(hypothesis) contains outgroup"); continue }; let mask = members.reduce(0) { $0 | (1 << numbers[$1]!) }; lines.append("CLADE \(hypothesis) taxa \(mask.nonzeroBitCount) support \(support[mask, default: 0])")
        for index in methods.indices { let containers = splits[index].union([ingroup]).filter { $0 & mask == mask }, common = containers.min { $0.nonzeroBitCount < $1.nonzeroBitCount }!, intruders = names.indices.filter { common & ~mask & (1 << $0) != 0 }.map { names[$0] }, joined = intruders.isEmpty ? "-" : intruders.joined(separator: ","); lines.append("TEST \(hypothesis) \(methods[index]) monophyletic \(common == mask ? "yes" : "no") mrca \(common.nonzeroBitCount) intruders \(joined)") }
        let subset = mask & exhaustiveIngroup
        if subset.nonzeroBitCount < 2 || subset.nonzeroBitCount >= exhaustiveIngroup.nonzeroBitCount { lines.append("SUBSET \(hypothesis) untestable"); continue }
        let included = exhaustive.records.filter { $0.splits.contains(subset) }, excluded = exhaustive.records.filter { !$0.splits.contains(subset) }, withScore = included.map { $0.score }.min()!, withoutScore = excluded.map { $0.score }.min()!, withBME = included.map { $0.bme }.min()!, withoutBME = excluded.map { $0.bme }.min()!
        lines.append("SUBSET \(hypothesis) taxa \(subset.nonzeroBitCount) with \(withScore) without \(withoutScore) bme_with \(real(withBME, 5)) bme_without \(real(withoutBME, 5))")
    }
    return lines
}
func distanceLines(_ names: [String], _ pairs: [PairCounts], _ matrices: [MatrixResult], _ mainIndex: Int, _ patristic: [[[Double]]], _ meStart: Double, _ me: HillResult<Double>, _ exhaustive: ExhaustiveResult) -> [String] {
    var totals = [0, 0, 0], pairBlock: [String] = []
    for pair in pairs { pairBlock.append("PAIR \(names[pair.first]) \(names[pair.second]) sites \(pair.sites) transitions \(pair.transitions) transversions \(pair.transversions)"); totals[0] += pair.sites; totals[1] += pair.transitions; totals[2] += pair.transversions }
    pairBlock.append("TOTAL sites \(totals[0]) transitions \(totals[1]) transversions \(totals[2])")
    var blocks = [pairBlock]
    for index in 0..<3 { var block = ["MODEL \(distanceModels[index].rawValue)"] + matrixLines(names, matrices[index].matrix); block += matrices[index].saturated.map { "SATURATED \(names[$0.first]) \(names[$0.second]) sites \($0.sites)" }; blocks.append(block) }
    blocks.append(["PATRISTIC \(njMethods[mainIndex])"] + matrixLines(names, patristic[mainIndex]))
    var evolution = ["ME start \(njMethods[mainIndex]) length \(real(meStart, 5))"]
    for move in me.moves { evolution.append("NNI edge \(symbols(move.mask, names.count)) swap \(move.swap) length \(real(move.value, 5))") }
    evolution += ["ME moves \(me.moves.count) evaluated \(me.evaluated) length \(real(me.value, 5))", "EXHAUSTIVE taxa \(exhaustive.taxa.count) trees \(exhaustive.records.count) best \(real(exhaustive.bestBME.bme, 5)) second \(real(exhaustive.secondBME, 5))", "BEST \(exhaustive.bestBME.newick) parsimony \(exhaustive.bestBME.score)"]
    blocks.append(evolution)
    var lines: [String] = []
    for block in blocks { if !lines.isEmpty { lines.append("") }; lines += block }
    return lines
}
func scoreLine(_ method: String, _ score: Int, _ bounds: ParsimonyBounds) -> String { "TREE \(method) score \(score) ci \(real(Double(bounds.minimum) / Double(score), 4)) ri \(real(Double(bounds.maximum - score) / Double(bounds.maximum - bounds.minimum), 4))" }
func parsimonyLines(_ names: [String], _ outgroup: Int, _ bounds: ParsimonyBounds, _ njScores: [Int], _ initial: StepwiseResult, _ search: HillResult<Int>, _ reconstruction: Reconstruction, _ exhaustive: ExhaustiveResult) -> [String] {
    var lines = ["BOUNDS minimum \(bounds.minimum) maximum \(bounds.maximum)"]
    for index in 0..<3 { lines.append(scoreLine(njMethods[index], njScores[index], bounds)) }
    lines.append("START " + initial.taxa.prefix(3).map { names[$0] }.joined(separator: " ") + " score \(initial.initial)")
    for addition in initial.additions { lines.append("ADD \(names[addition.taxon]) edge \(symbols(addition.mask, names.count)) score \(addition.score) ties \(addition.ties)") }
    lines.append("STEPWISE score \(initial.score) evaluated \(initial.evaluated)")
    for move in search.moves { lines.append("NNI edge \(symbols(move.mask, names.count)) swap \(move.swap) score \(move.value)") }
    lines += ["SEARCH moves \(search.moves.count) evaluated \(search.evaluated) score \(search.value)", scoreLine("MP", search.value, bounds), "MP " + newick(search.tree, names, outgroup, lengths: true)]
    var histogram: [Int: Int] = [:]
    for value in reconstruction.siteChanges { histogram[value, default: 0] += 1 }
    for value in 0...reconstruction.siteChanges.max()! { lines.append("CHANGES \(value) columns \(histogram[value, default: 0])") }
    let homoplasy = reconstruction.siteChanges.indices.filter { reconstruction.siteChanges[$0] > bounds.minima[$0] }.count, rooted = search.tree.rooted(outgroup), ancestors = reconstruction.ancestors.map { node, sequence in (symbols(node == rooted.root ? rooted.ingroup : rooted.masks[node]!, names.count), sequence) }.sorted { $0.0 < $1.0 }
    lines.append("HOMOPLASY columns \(homoplasy) extra \(search.value - bounds.minimum)")
    for (symbol, sequence) in ancestors { lines.append("ANCESTOR \(symbol) \(sequence)") }
    lines += ["", "EXHAUSTIVE taxa \(exhaustive.taxa.count) trees \(exhaustive.records.count) best \(exhaustive.bestScore) optimal \(exhaustive.optimal.count)"]
    for value in exhaustive.histogram.keys.sorted() { lines.append("SCORE \(value) trees \(exhaustive.histogram[value]!)") }
    for record in exhaustive.optimal { lines.append("OPTIMAL \(record.newick) bme \(real(record.bme, 5))") }
    lines += ["STRICT " + newick(exhaustive.strict, names, outgroup), "HEURISTIC score \(exhaustive.heuristic) optimal \(exhaustive.heuristic == exhaustive.bestScore ? "yes" : "no")"]
    return lines
}
func treeOutputs(_ names: [String], _ trees: [Tree], _ outgroup: Int, _ support: [Int: Int]) -> (newicks: [String], diagrams: [String]) {
    var newicks: [String] = [], diagrams: [String] = []
    for index in methods.indices { newicks.append(methods[index] + " " + newick(trees[index], names, outgroup, lengths: index < 3 || index == 4, support: index == 5 ? support : nil)); if !diagrams.isEmpty { diagrams.append("") }; diagrams.append("TREE \(methods[index])"); diagrams += cladogram(trees[index], names, outgroup, support) }
    return (newicks, diagrams)
}
let settings = try readParameters(), records = try readFASTA(), alignment = checkRecords(records, settings.maximumMissing), names = alignment.names, sequences = alignment.sequences, count = names.count, outgroup = names.firstIndex(of: settings.outgroup)!, patterns = Patterns(sequences), pairs = allPairs(sequences, Array(repeating: 1, count: alignment.length))
let matrices = distanceModels.map { buildMatrix(pairs, count, $0, settings.saturation) }, njTrees = matrices.map { neighborJoining($0.matrix, Array(0..<count)) }, mainIndex = distanceModels.firstIndex(of: settings.model)!, mainTree = njTrees[mainIndex], mainMatrix = matrices[mainIndex].matrix, meStart = bmeLength(mainTree, mainMatrix), me = hillClimb(mainTree, { bmeLength($0, mainMatrix) }, outgroup, meStart)
let additionOrder = [outgroup] + (0..<count).filter { $0 != outgroup }, initial = stepwise(additionOrder, count, patterns, outgroup)
var mp = hillClimb(initial.tree, { parsimonyScore($0, patterns, outgroup) }, outgroup, initial.score)
let reconstruction = reconstruct(mp.tree, patterns, outgroup)
for (edge, changes) in reconstruction.branchChanges { mp.tree.connect(edge.first, edge.second, Double(changes) / Double(alignment.length)) }
let bounds = parsimonyBounds(patterns), njScores = njTrees.map { parsimonyScore($0, patterns, outgroup) }, exhaustiveNames = Set(settings.exhaustiveTaxa), exhaustiveTaxa = [outgroup] + names.indices.filter { $0 != outgroup && exhaustiveNames.contains(names[$0]) }, exhaustive = exhaustiveSearch(exhaustiveTaxa, names, patterns, outgroup, mainMatrix), siteLogs = njTrees.map { likelihoodSites($0, names, patterns, outgroup) }, bootstrapResult = bootstrap(names, sequences, settings, mainTree, mainMatrix, outgroup)
let trees = njTrees + [me.tree, mp.tree, bootstrapResult.consensus], patristic = njTrees.map { patristicMatrix($0) }, rendered = treeOutputs(names, trees, outgroup, bootstrapResult.support)
let outputs = [("summary.txt", summaryLines(records, alignment, patterns)), ("distances.txt", distanceLines(names, pairs, matrices, mainIndex, patristic, meStart, me, exhaustive)), ("trees.nwk", rendered.newicks), ("cladograms.txt", rendered.diagrams), ("parsimony.txt", parsimonyLines(names, outgroup, bounds, njScores, initial, mp, reconstruction, exhaustive)), ("likelihood.txt", likelihoodLines(names, patterns, njTrees, outgroup, mainIndex, settings.lowSites, siteLogs)), ("bootstrap.txt", bootstrapResult.lines), ("clock.txt", clockLines(names, sequences, outgroup, mainIndex, mainTree)), ("comparison.txt", comparisonLines(names, patterns, trees, matrices, mainMatrix, mainIndex, outgroup, bootstrapResult.support, settings.replicates, njScores, mp.value, reconstruction.branchChanges, siteLogs, patristic)), ("hypotheses.txt", try hypothesisLines(names, trees, outgroup, bootstrapResult.support, exhaustive))]
for (name, lines) in outputs { try writeLines(name, lines) }
