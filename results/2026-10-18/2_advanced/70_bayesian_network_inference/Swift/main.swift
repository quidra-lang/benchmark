import Foundation

func real(_ value: Double) -> String { let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value); return text == "-0.0000" ? "0.0000" : text }
func yes(_ value: Bool) -> String { value ? "yes" : "no" }
func writeBlocks(_ name: String, _ blocks: [[String]]) throws { let text = blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n"); try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try (text.isEmpty ? "" : text + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
func closure(_ initial: Set<Int>, _ links: [[Int]]) -> Set<Int> { var reached = initial, pending = Array(initial); while let variable = pending.popLast() { for neighbor in links[variable] where !reached.contains(neighbor) { reached.insert(neighbor); pending.append(neighbor) } }; return reached }
struct SumResult { let distribution: Factor; let probability: Double; let marginals: [Int: [Double]] }
struct Posterior { let relevant: [Int]; let eliminate: [Int]; let initial: [Factor]; let plans: [Plan]; let sum: SumResult }
struct Enumeration { let count: Int; let status: String }
struct MPEOutcome { let maximum: Double; let assignment: [Int] }
struct BallPosition: Hashable { let variable: Int; let up: Bool }
struct FamilyKey: Hashable { let variable: Int; let parents: [Int] }
final class NetworkAnalysis {
    let network: Network
    let samples: [[Int]]
    let settings: Settings
    let random: Minstd
    var names: [String] { network.names }
    var states: [[String]] { network.states }
    var parents: [[Int]] { network.parents }
    var sizes: [Int] { states.map { $0.count } }
    var variables: [Int] { Array(names.indices) }
    var methodIndex: Int { settings.method == .minfill ? 0 : 1 }
    var children: [[Int]] = []
    var topological: [Int] = []
    var depths: [Int] = []
    var ancestors: [Set<Int>] = []
    var descendants: [Set<Int>] = []
    var spouses: [[Int]] = []
    var blankets: [[Int]] = []
    var counts: [[[Int]]] = []
    var learned: [[[Double]]] = []
    var cpts: [[[Double]]] = []
    var likelihoods: [Double] = []
    var parameters: [Int] = []
    var factors: [Factor] = []
    var familyScores: [FamilyKey: Double] = [:]
    init(_ input: Inputs) {
        network = input.network; samples = input.samples; settings = input.settings; random = Minstd(input.settings.seed)
        children = variables.map { variable in variables.filter { parents[$0].contains(variable) } }
        var selected: Set<Int> = []
        while selected.count < names.count { let variable = variables.first { !selected.contains($0) && parents[$0].allSatisfy { selected.contains($0) } }!; selected.insert(variable); topological.append(variable) }
        depths = Array(repeating: 0, count: names.count)
        for variable in topological { depths[variable] = parents[variable].map { depths[$0] + 1 }.max() ?? 0 }
        ancestors = variables.map { closure(Set(parents[$0]), parents) }; descendants = variables.map { closure(Set(children[$0]), children) }
        for variable in variables { let immediate = Set(parents[variable] + children[variable]), partners = Set(children[variable].flatMap { parents[$0] }).subtracting(immediate.union([variable])); spouses.append(partners.sorted()); blankets.append(immediate.union(partners).sorted()) }
        counts = variables.map { countSamples($0, parents[$0], samples, sizes) }; learned = counts.map { learn($0, settings.alpha) }; cpts = variables.map { settings.sources[$0] == "GIVEN" ? network.expert[$0]! : learned[$0] }; likelihoods = variables.map { logLikelihood(counts[$0], cpts[$0]) }; parameters = counts.map(parameterCount); factors = variables.map { cptFactor($0, parents[$0], cpts[$0], sizes) }
    }
    func sequence(_ variables: [Int]) -> String { variables.isEmpty ? "-" : variables.map { names[$0] }.joined(separator: " ") }
    func assignmentText(_ assignment: [Int], _ variables: [Int]) -> String { variables.isEmpty ? "-" : variables.map { "\(names[$0])=\(states[$0][assignment[$0]])" }.joined(separator: " ") }
    func evidenceText(_ item: Evidence) -> String { "\(names[item.variable])=\(states[item.variable][item.state])" }
    func variable(_ name: String) -> Int { names.firstIndex(of: name)! }
    func evidence(_ fields: [String]) -> [Evidence] { fields.map { field in let parts = field.split(separator: "="), variable = self.variable(String(parts[0])); return Evidence(variable: variable, state: states[variable].firstIndex(of: String(parts[1]))!) } }
    func queryParts(_ fields: [String]) -> (query: [Int], evidence: [Evidence]) { guard let separator = fields.firstIndex(of: "|") else { return (fields.map(variable), []) }; return (fields[..<separator].map(variable), evidence(Array(fields.dropFirst(separator + 1)))) }
    func plans(_ initial: [Factor], _ eliminate: [Int]) -> [Plan] { [EliminationMethod.minfill, .given].map { makePlan(initial, eliminate, $0, settings.order, sizes) } }
    func sumResult(_ initial: [Factor], _ plan: Plan, _ query: [Int]) -> SumResult {
        let factor = execute(initial, plan, sizes).factor, probability = total(factor.values), distribution = Factor(variables: factor.variables, values: factor.values.map { $0 / probability }, sizes: sizes)
        var marginals = Dictionary(uniqueKeysWithValues: query.map { ($0, Array(repeating: 0.0, count: sizes[$0])) })
        for (assignment, probability) in zip(assignments(distribution.variables, sizes), distribution.values) { for variable in query { marginals[variable]![assignment[variable]] += probability } }
        return SumResult(distribution: distribution, probability: probability, marginals: marginals)
    }
    func posterior(_ query: [Int], _ evidence: [Evidence]) -> Posterior { let observed = Set(evidence.map { $0.variable }), relevant = closure(Set(query).union(observed), parents).sorted(), eliminate = relevant.filter { !query.contains($0) && !observed.contains($0) }, initial = relevant.map { factors[$0].reduced(evidence) }, plans = self.plans(initial, eliminate), sum = sumResult(initial, plans[methodIndex], query); return Posterior(relevant: relevant, eliminate: eliminate, initial: initial, plans: plans, sum: sum) }
    func joint(_ assignment: [Int], _ variables: [Int]) -> Double { var probability = 1.0; for variable in variables { probability *= cpts[variable][parentRow(parents[variable], assignment, sizes)][assignment[variable]] }; return probability }
    func queryEnumeration(_ result: Posterior, _ query: [Int], _ evidence: [Evidence]) -> Enumeration {
        let observed = Set(evidence.map { $0.variable }), free = result.relevant.filter { !observed.contains($0) }, count = entryCount(free, sizes)
        if count > settings.limit { return Enumeration(count: count, status: "skipped") }
        let query = query.sorted()
        var values = Array(repeating: 0.0, count: entryCount(query, sizes))
        for candidate in assignments(free, sizes) { let assignment = applying(evidence, candidate); values[parentRow(query, assignment, sizes)] += joint(assignment, result.relevant) }
        let probability = total(values), agreed = abs(log(probability) - log(result.sum.probability)) <= 1e-9 && zip(values, result.sum.distribution.values).allSatisfy { abs($0.0 / probability - $0.1) <= 1e-9 }
        return Enumeration(count: count, status: agreed ? "agree" : "disagree")
    }
    func eliminationLines(_ relevant: [Int], _ eliminate: [Int], _ plans: [Plan], _ agreement: Bool, _ enumeration: Enumeration) -> [String] { var lines = ["relevant " + sequence(relevant), "pruned " + sequence(variables.filter { !relevant.contains($0) }), "eliminate " + sequence(eliminate)]; for (name, plan) in zip(["minfill", "given"], plans) { lines.append("order " + name); for step in plan.steps { lines.append("step \(names[step.variable]) fill \(step.fill) scope \(sequence(step.scope)) entries \(step.size)") }; lines.append("cost max \(plan.maximum) total \(plan.total)") }; lines += ["used " + settings.method.rawValue.lowercased(), "orders_agree " + yes(agreement), "enumeration \(enumeration.count) \(enumeration.status)"]; return lines }
    func marginalLines(_ prefix: String, _ query: [Int], _ marginals: [Int: [Double]]) -> [String] { query.map { variable in prefix + " " + names[variable] + " " + states[variable].indices.map { "\(states[variable][$0]) \(real(marginals[variable]![$0]))" }.joined(separator: " ") } }
    func answerQuery(_ query: [Int], _ evidence: [Evidence]) -> (answer: [String], elimination: [String]) {
        let result = posterior(query, evidence)
        var lines = ["log_evidence " + real(log(result.sum.probability))]
        if !evidence.isEmpty { let conflict = total(evidence.map { log(posterior([], [$0]).sum.probability) }) - log(result.sum.probability); lines.append("conflict " + real(conflict)) }
        if query.count >= 2 { let distribution = result.sum.distribution; for (assignment, probability) in zip(assignments(distribution.variables, sizes), distribution.values) { lines.append("joint " + assignmentText(assignment, distribution.variables) + " " + real(probability)) } }
        lines += marginalLines("marginal", query, result.sum.marginals)
        for item in evidence { let without = posterior(query, evidence.filter { $0.variable != item.variable }).sum.marginals; var shift = 0.0; for variable in query { for state in 0..<sizes[variable] { shift = max(shift, abs(result.sum.marginals[variable]![state] - without[variable]![state])) } }; lines.append("drop \(evidenceText(item)) shift \(real(shift))") }
        let first = sumResult(result.initial, result.plans[0], query), second = sumResult(result.initial, result.plans[1], query), agreement = abs(log(first.probability) - log(second.probability)) <= 1e-9 && zip(first.distribution.values, second.distribution.values).allSatisfy { abs($0.0 - $0.1) <= 1e-9 }, enumeration = queryEnumeration(result, query, evidence)
        return (lines, eliminationLines(result.relevant, result.eliminate, result.plans, agreement, enumeration))
    }
    func mpeEnumeration(_ eliminate: [Int], _ evidence: [Evidence], _ assignment: [Int], _ maximum: Double) -> Enumeration { let count = entryCount(eliminate, sizes); if count > settings.limit { return Enumeration(count: count, status: "skipped") }; var bestProbability = -1.0, bestAssignment: [Int] = []; for candidate in assignments(eliminate, sizes) { let candidate = applying(evidence, candidate), probability = joint(candidate, variables); if probability > bestProbability { bestProbability = probability; bestAssignment = candidate } }; let agreement = bestAssignment == assignment && abs(log(bestProbability) - log(maximum)) <= 1e-9; return Enumeration(count: count, status: agreement ? "agree" : "disagree") }
    func answerMPE(_ evidence: [Evidence]) -> (answer: [String], elimination: [String]) {
        let observed = Set(evidence.map { $0.variable }), initial = factors.map { $0.reduced(evidence) }, eliminate = variables.filter { !observed.contains($0) }, plans = self.plans(initial, eliminate), outcomes = plans.map { plan -> MPEOutcome in let result = execute(initial, plan, sizes, maximize: true); return MPEOutcome(maximum: result.factor.values[0], assignment: applying(evidence, traceback(result.products, sizes))) }, outcome = outcomes[methodIndex], probability = evidence.isEmpty ? 1.0 : posterior([], evidence).sum.probability
        var lines = ["assignment " + assignmentText(outcome.assignment, variables), "log_joint " + real(log(outcome.maximum)), "log_evidence " + real(log(probability)), "posterior " + real(outcome.maximum / probability)]
        for variable in eliminate { let plan = makePlan(initial, eliminate.filter { $0 != variable }, settings.method, settings.order, sizes), factor = execute(initial, plan, sizes, maximize: true).factor, alternative = (0..<sizes[variable]).filter { $0 != outcome.assignment[variable] }.sorted { factor.values[$0] == factor.values[$1] ? $0 < $1 : factor.values[$0] > factor.values[$1] }[0]; lines.append("margin \(names[variable]) \(states[variable][alternative]) \(real(log(outcome.maximum) - log(factor.values[alternative])))") }
        let agreement = outcomes[0].assignment == outcomes[1].assignment && abs(log(outcomes[0].maximum) - log(outcomes[1].maximum)) <= 1e-9, enumeration = mpeEnumeration(eliminate, evidence, outcome.assignment, outcome.maximum)
        return (lines, eliminationLines(variables, eliminate, plans, agreement, enumeration))
    }
    func answerSample(_ number: Int, _ query: [Int], _ evidence: [Evidence], _ counts: [Int]) -> (answer: [String], csv: [String]) {
        let exact = posterior(query, evidence).sum.marginals, checkpoints = Set(counts)
        var lines = marginalLines("exact", query, exact), csv: [String] = [], weight = 0.0, squaredWeight = 0.0, weights = Dictionary(uniqueKeysWithValues: query.map { ($0, Array(repeating: 0.0, count: sizes[$0])) })
        for index in 1...counts.last! { let current = weightedSample(topological, parents, cpts, sizes, evidence, random); weight += current.weight; squaredWeight += current.weight * current.weight; for variable in query { weights[variable]![current.sample[variable]] += current.weight }; if !checkpoints.contains(index) { continue }; var maximumError = 0.0; for variable in query { for state in 0..<sizes[variable] { let estimate = weights[variable]![state] / weight, probability = exact[variable]![state], error = abs(estimate - probability); maximumError = max(maximumError, error); csv.append("\(number),\(index),\(names[variable]),\(states[variable][state]),\(real(estimate)),\(real(probability)),\(real(error))") } }; lines.append("after \(index) weight \(real(weight)) ess \(real(weight * weight / squaredWeight)) max_error \(real(maximumError))") }
        return (lines, csv)
    }
    func answerPredict(_ variable: Int) -> [String] {
        let size = sizes[variable]
        var confusion = Array(repeating: Array(repeating: 0, count: size), count: size), likelihood = 0.0
        for sample in samples { var assignment = sample, values: [Double] = []; for state in 0..<size { assignment[variable] = state; var probability = cpts[variable][parentRow(parents[variable], assignment, sizes)][state]; for child in children[variable] { probability *= cpts[child][parentRow(parents[child], assignment, sizes)][assignment[child]] }; values.append(probability) }; let denominator = total(values), probabilities = values.map { $0 / denominator }, prediction = probabilities.indices.sorted { probabilities[$0] == probabilities[$1] ? $0 < $1 : probabilities[$0] > probabilities[$1] }[0], actual = sample[variable]; confusion[actual][prediction] += 1; likelihood += log(probabilities[actual]) }
        let correct = (0..<size).map { confusion[$0][$0] }.reduce(0, +), count = samples.count
        var lines = ["blanket " + sequence(blankets[variable]), "accuracy \(correct)/\(count) \(real(Double(correct) / Double(count)))", "log_loss " + real(-likelihood / Double(count)), "predicted " + states[variable].joined(separator: " ")]
        for state in 0..<size { lines.append("actual " + states[variable][state] + " " + confusion[state].map(String.init).joined(separator: " ")) }
        return lines
    }
}
extension NetworkAnalysis {
    func reachable(_ initial: [Int], _ observed: [Int]) -> [Int] {
        let x = Set(initial), z = Set(observed), ancestors = closure(z, parents)
        var pending = x.sorted().map { BallPosition(variable: $0, up: true) }, visited = Set(pending), head = 0
        while head < pending.count { let position = pending[head], variable = position.variable; head += 1; var following: [BallPosition] = []; if position.up && !z.contains(variable) { following += parents[variable].map { BallPosition(variable: $0, up: true) }; following += children[variable].map { BallPosition(variable: $0, up: false) } } else if !position.up { if !z.contains(variable) { following += children[variable].map { BallPosition(variable: $0, up: false) } }; if ancestors.contains(variable) { following += parents[variable].map { BallPosition(variable: $0, up: true) } } }; for next in following where !visited.contains(next) { visited.insert(next); pending.append(next) } }
        return Set(visited.map { $0.variable }).subtracting(x.union(z)).sorted()
    }
    func mutualInformation(_ x: [Int], _ y: [Int], _ z: [Int]) -> (information: Double, statistic: Double, degrees: Int) {
        let scope = Set(x + y + z).sorted(), xz = Set(x + z).sorted(), yz = Set(y + z).sorted(), z = z.sorted()
        var counts: [Int: Int] = [:], countXZ: [Int: Int] = [:], countYZ: [Int: Int] = [:], countZ: [Int: Int] = [:]
        for sample in samples { counts[parentRow(scope, sample, sizes), default: 0] += 1; countXZ[parentRow(xz, sample, sizes), default: 0] += 1; countYZ[parentRow(yz, sample, sizes), default: 0] += 1; countZ[parentRow(z, sample, sizes), default: 0] += 1 }
        var information = 0.0
        for key in counts.keys.sorted() { var number = key, assignment = Array(repeating: 0, count: sizes.count); for variable in scope.reversed() { assignment[variable] = number % sizes[variable]; number /= sizes[variable] }; let observed = counts[key]!, nxz = countXZ[parentRow(xz, assignment, sizes)]!, nyz = countYZ[parentRow(yz, assignment, sizes)]!, nz = countZ[parentRow(z, assignment, sizes)]!, argument = Double(observed * nz) / Double(nxz * nyz); information += (Double(observed) / Double(samples.count)) * log(argument) }
        return (information, Double(2 * samples.count) * information, (entryCount(x, sizes) - 1) * (entryCount(y, sizes) - 1) * entryCount(z, sizes))
    }
    func answerDsep(_ groups: [[Int]]) -> [String] { let x = groups[0], y = groups[1], z = groups.count == 3 ? groups[2] : [], reached = reachable(x, z), information = mutualInformation(x, y, z); return ["result " + (Set(reached).isDisjoint(with: y) ? "separated" : "connected"), "reachable " + sequence(reached), "data cmi \(real(information.information)) g2 \(real(information.statistic)) df \(information.degrees)"] }
    func answerBlanket(_ variable: Int) -> [String] { let blanket = blankets[variable], rest = variables.filter { $0 != variable && !blanket.contains($0) }, separated = Set(reachable([variable], blanket)).isDisjoint(with: rest); return ["parents " + sequence(parents[variable]), "children " + sequence(children[variable]), "spouses " + sequence(spouses[variable]), "blanket " + sequence(blanket), "rest " + sequence(rest), "rest_separated " + yes(separated)] }
    func path(_ start: Int, _ finish: Int, _ ignored: (Int, Int)? = nil) -> [Int]? { var previous = [start: -1], pending = [start], head = 0; while head < pending.count { let variable = pending[head]; head += 1; for child in children[variable] { if let ignored, variable == ignored.0 && child == ignored.1 { continue }; if previous[child] != nil { continue }; previous[child] = variable; if child == finish { var result: [Int] = [], current = child; while current != -1 { result.append(current); current = previous[current]! }; return Array(result.reversed()) }; pending.append(child) } }; return nil }
    func score(_ variable: Int, _ parents: [Int]) -> Double { let key = FamilyKey(variable: variable, parents: parents.sorted()); if let value = familyScores[key] { return value }; let value = familyScore(variable, key.parents, samples, sizes, settings.alpha); familyScores[key] = value; return value }
    func answerEdge(_ operation: String, _ x: Int, _ y: Int) -> [String] {
        let exists = parents[y].contains(x)
        if operation == "ADD" && exists { return ["result exists"] }
        if operation != "ADD" && !exists { return ["result missing"] }
        if operation == "ADD", let path = self.path(y, x) { return ["result cycle " + ([x] + path).map { names[$0] }.joined(separator: " -> ")] }
        if operation == "REVERSE", let path = self.path(x, y, (x, y)) { return ["result cycle " + ([y] + path).map { names[$0] }.joined(separator: " -> ")] }
        let beforeY = score(y, parents[y]), parentsY = operation == "ADD" ? Set(parents[y]).union([x]).sorted() : parents[y].filter { $0 != x }, afterY = score(y, parentsY)
        var change = afterY - beforeY, lines = ["result ok", "family \(names[y]) before \(real(beforeY)) after \(real(afterY))"]
        if operation == "REVERSE" { let beforeX = score(x, parents[x]), afterX = score(x, Set(parents[x]).union([y]).sorted()); change = (afterY - beforeY) + (afterX - beforeX); lines.append("family \(names[x]) before \(real(beforeX)) after \(real(afterX))") }
        lines.append("delta \(real(change)) \(change > 0 ? "improves" : "worsens")")
        return lines
    }
    func cptBlocks() -> [[String]] {
        var blocks: [[String]] = []
        let count = samples.count
        for variable in variables { let source = settings.sources[variable], parents = self.parents[variable], cpt = cpts[variable], counts = self.counts[variable]; var lines = ["variable \(names[variable]) source \(source)", "states " + states[variable].joined(separator: " "), "parents " + sequence(parents)]; for (row, assignment) in assignments(parents, sizes).enumerated() { lines.append("row " + assignmentText(assignment, parents) + " counts " + counts[row].map(String.init).joined(separator: " ") + " probs " + cpt[row].map(real).joined(separator: " ")) }; let likelihood = likelihoods[variable], parameters = self.parameters[variable], bic = likelihood - Double(parameters) * log(Double(count)) / 2, marginal = posterior([variable], []).sum.marginals[variable]!, frequencies = (0..<sizes[variable]).map { state in Double(counts.map { $0[state] }.reduce(0, +)) / Double(count) }; lines += ["loglik \(real(likelihood)) parameters \(parameters) bic \(real(bic))", "marginal model " + marginal.map(real).joined(separator: " ") + " data " + frequencies.map(real).joined(separator: " ")]; if source == "LEARNED" { var difference = "-"; if let expert = network.expert[variable] { var maximum = 0.0; for row in learned[variable].indices { for state in learned[variable][row].indices { maximum = max(maximum, abs(learned[variable][row][state] - expert[row][state])) } }; difference = real(maximum) }; lines.append("given_difference " + difference) }; blocks.append(lines) }
        let likelihood = total(likelihoods), parameters = self.parameters.reduce(0, +), bic = likelihood - Double(parameters) * log(Double(count)) / 2
        blocks.append(["network samples \(count) pseudocount \(real(settings.alpha)) loglik \(real(likelihood)) parameters \(parameters) bic \(real(bic))"])
        return blocks
    }
    func structureSummary() -> [String] {
        let plans = self.plans(factors, variables), widths = plans.map { ($0.steps.map { $0.scope.count }.max() ?? 1) - 1 }, graph = interactionGraph(factors), moralEdges = graph.values.map { $0.count }.reduce(0, +) / 2
        var lines = ["variables \(variables.count) edges \(parents.map { $0.count }.reduce(0, +))", "topological_order " + sequence(topological), "roots " + sequence(variables.filter { parents[$0].isEmpty }), "leaves " + sequence(variables.filter { children[$0].isEmpty }), "moral_edges \(moralEdges) width minfill \(widths[0]) given \(widths[1])"]
        for variable in variables { lines.append("variable \(names[variable]) states \(sizes[variable]) parents \(parents[variable].count) children \(children[variable].count) depth \(depths[variable]) ancestors \(ancestors[variable].count) descendants \(descendants[variable].count) blanket \(blankets[variable].count)") }
        return lines
    }
    func processQueries(_ queries: [String]) -> (answers: [[String]], elimination: [[String]], structure: [[String]], sampling: [String]) {
        var answers: [[String]] = [], elimination: [[String]] = [], structure = [structureSummary()], sampling = ["query,samples,variable,state,estimate,exact,abs_error"]
        for (index, line) in queries.enumerated() { let parts = lineFields(line), kind = parts[0], fields = Array(parts.dropFirst()), heading = "query \(index + 1) \(line)"; switch kind { case "QUERY": let query = queryParts(fields), result = answerQuery(query.query, query.evidence); answers.append([heading] + result.answer); elimination.append([heading] + result.elimination); case "MPE": let result = answerMPE(evidence(fields)); answers.append([heading] + result.answer); elimination.append([heading] + result.elimination); case "SAMPLE": let separator = fields.lastIndex(of: "COUNTS")!, query = queryParts(Array(fields[..<separator])), counts = fields.dropFirst(separator + 1).map { Int($0)! }, result = answerSample(index + 1, query.query, query.evidence, counts); answers.append([heading] + result.answer); sampling += result.csv; case "PREDICT": answers.append([heading] + answerPredict(variable(fields[0]))); case "DSEP": var groups: [[Int]] = [[]]; for field in fields { if field == "|" { groups.append([]) } else { groups[groups.count - 1].append(variable(field)) } }; structure.append([heading] + answerDsep(groups)); case "BLANKET": structure.append([heading] + answerBlanket(variable(fields[0]))); default: structure.append([heading] + answerEdge(fields[0], variable(fields[1]), variable(fields[2]))) } }
        return (answers, elimination, structure, sampling)
    }
}
let input = try readInputs(), analysis = NetworkAnalysis(input), cpts = analysis.cptBlocks(), reports = analysis.processQueries(input.queries)
for (name, blocks) in [("cpts.txt", cpts), ("structure.txt", reports.structure), ("answers.txt", reports.answers), ("elimination.txt", reports.elimination), ("sampling.csv", [reports.sampling])] { try writeBlocks(name, blocks) }
