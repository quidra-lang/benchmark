import Foundation

let commands = ["SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC"]
let argumentTypes = ["SOLVE": ["file"], "ENUM": ["file", "limit"], "CORE": ["file"],
                     "QUEENS": ["small", "limit"], "PIGEON": ["small", "small", "limit"],
                     "COLOR": ["graph", "color", "limit"], "CHROMATIC": ["graph", "color"]]

struct Edge: Hashable {
    let first: Int
    let second: Int
}

final class Graph {
    let name: String
    let vertices: Int
    var edges: [Edge] = []
    var invalid: String?

    init(_ name: String, _ vertices: Int) { self.name = name; self.vertices = vertices }
}

struct Solution {
    let formula: Formula
    let preparation: Preprocessing
    let models: [[Bool]]
    let rounds: Int
    let stop: String
    let trace: [String]
    let statistics: SearchStatistics
    var status: String { models.isEmpty ? "UNSAT" : "SAT" }
}

struct ModelAnalysis {
    let failure: (model: Int, clause: Int)?
    let trueDistribution: [Int]
    let safe: [Int]
    let distances: [Int]
    let backbone: [Int]
}

struct UnsatisfiableCore {
    let clauses: [Int]
    let decisions: Int
    let conflicts: Int
}

struct ColorAttempt {
    let colors: Int
    let solution: Solution
}

final class Job {
    let number: Int
    let text: String
    let command: String
    let arguments: [String]
    var error: String?
    var graph: Graph?
    var colors = 0
    var solution: Solution?
    var statistics = SearchStatistics()
    var rounds = 0
    var removed = 0
    var attempts: [ColorAttempt] = []
    var chromatic: Int?
    var core: UnsatisfiableCore?
    var analysis: ModelAnalysis?
    var heading: String { "JOB \(number) \(text)" }

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
        let tokens = text.split(separator: " ").map(String.init)
        command = tokens[0]
        arguments = Array(tokens.dropFirst())
    }
}

func loadGraphs() throws -> [String: Graph] {
    var graphs: [String: Graph] = [:]
    var current: Graph?
    for (index, line) in try readInputLines("input/graphs.txt").enumerated() {
        if current == nil {
            if line.isEmpty || line.hasPrefix("#") { continue }
            let words = line.split(separator: " ").map(String.init)
            current = Graph(words[1], Int(words[2])!)
            continue
        }
        let graph = current!
        if line == "END" {
            graph.edges.sort { $0.first == $1.first ? $0.second < $1.second : $0.first < $1.first }
            graphs[graph.name] = graph
            current = nil
            continue
        }
        if graph.invalid != nil { continue }
        let tokens = line.components(separatedBy: " ")
        var reason: String?
        if tokens.count != 2 || !tokens.allSatisfy(validNumber) { reason = "bad edge line" }
        else {
            let first = Int(tokens[0])!
            let second = Int(tokens[1])!
            let edge = Edge(first: min(first, second), second: max(first, second))
            if !(1...graph.vertices).contains(first) || !(1...graph.vertices).contains(second) { reason = "vertex out of range" }
            else if first == second { reason = "self loop" }
            else if graph.edges.contains(edge) { reason = "duplicate edge" }
            else { graph.edges.append(edge) }
        }
        if let reason { graph.invalid = "\(reason) at line \(index + 1)" }
    }
    return graphs
}

func loadJobs() throws -> [Job] {
    var jobs: [Job] = []
    for line in try readInputLines("input/jobs.txt") where !line.isEmpty && !line.hasPrefix("#") {
        jobs.append(Job(jobs.count + 1, line))
    }
    return jobs
}

func validName(_ name: String) -> Bool {
    (1...20).contains(name.count) && name.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "_" }
}

func validateJob(_ job: Job, _ graphs: [String: Graph]) -> String? {
    guard let types = argumentTypes[job.command] else { return "unknown command \(job.command)" }
    if types.count != job.arguments.count { return "wrong argument count" }
    for (argument, kind) in zip(job.arguments, types) {
        if kind == "file" {
            if !argument.hasSuffix(".cnf") || !validName(String(argument.dropLast(4))) { return "bad file name \(argument)" }
        } else if kind == "graph" {
            guard let graph = graphs[argument] else { return "unknown graph \(argument)" }
            if let reason = graph.invalid { return "invalid graph \(argument): \(reason)" }
        } else {
            if !validNumber(argument) { return "bad number \(argument)" }
            let maximum = kind == "small" ? 8 : kind == "color" ? 6 : 200
            if !(1...maximum).contains(Int(argument)!) { return "out of range \(argument)" }
        }
    }
    return nil
}

func greedyColoring(_ graph: Graph) -> [Int] {
    var neighbors = Array(repeating: Set<Int>(), count: graph.vertices + 1)
    for edge in graph.edges {
        neighbors[edge.first].insert(edge.second)
        neighbors[edge.second].insert(edge.first)
    }
    let order = (1...graph.vertices).sorted {
        neighbors[$0].count == neighbors[$1].count ? $0 < $1 : neighbors[$0].count > neighbors[$1].count
    }
    var colors = Array(repeating: 0, count: graph.vertices + 1)
    for vertex in order {
        let used = Set(neighbors[vertex].map { colors[$0] }.filter { $0 > 0 })
        var candidate = 1
        while used.contains(candidate) { candidate += 1 }
        colors[vertex] = candidate
    }
    return Array(colors.dropFirst())
}

func solveFormula(_ formula: Formula, limit: Int) -> Solution {
    let preparation = preprocess(formula, usePure: limit == 1)
    var models: [[Bool]] = []
    var statistics = SearchStatistics()
    var rounds = 0
    var trace: [String] = []
    var blocking: [[Int]] = []
    var stop = preparation.emptyClause == nil ? "limit" : "preprocess"
    if preparation.emptyClause == nil {
        while models.count < limit {
            rounds += 1
            let round = runRound(formula.variables, preparation.clauses + blocking)
            if rounds == 1 { trace = round.trace }
            statistics.accumulate(round.statistics)
            guard var model = round.model else {
                stop = "all"
                break
            }
            for (variable, value) in preparation.fixed { model[variable] = value }
            models.append(model)
            blocking.append(preparation.active.map { model[$0] ? -$0 : $0 })
        }
    }
    return Solution(formula: formula, preparation: preparation, models: models, rounds: rounds,
                     stop: stop, trace: trace, statistics: statistics)
}

func literalTrue(_ model: [Bool], _ literal: Int) -> Bool { literal > 0 ? model[literal] : !model[-literal] }

func satisfies(_ model: [Bool], _ clauses: [[Int]]) -> Bool {
    clauses.allSatisfy { clause in clause.contains { literalTrue(model, $0) } }
}

func analyzeModels(_ solution: Solution) -> ModelAnalysis? {
    guard let first = solution.models.first else { return nil }
    let models = solution.models
    let clauses = solution.formula.clauses
    let variables = 1..<(solution.formula.variables + 1)
    var failure: (model: Int, clause: Int)?
    for (modelIndex, model) in models.enumerated() {
        for (clauseIndex, clause) in clauses.enumerated() {
            if !clause.contains(where: { literalTrue(model, $0) }) {
                failure = (modelIndex + 1, clauseIndex + 1)
                break
            }
        }
        if failure != nil { break }
    }
    let trueDistribution = clauses.map { clause in clause.filter { literalTrue(first, $0) }.count }
    var safe: [Int] = []
    for variable in variables {
        var inverted = first
        inverted[variable].toggle()
        if satisfies(inverted, clauses) { safe.append(variable) }
    }
    var distances: [Int] = []
    for firstIndex in models.indices {
        for secondIndex in (firstIndex + 1)..<models.count {
            distances.append(variables.filter { models[firstIndex][$0] != models[secondIndex][$0] }.count)
        }
    }
    let backbone = variables.filter { variable in models.allSatisfy { $0[variable] == first[variable] } }
        .map { first[$0] ? $0 : -$0 }
    return ModelAnalysis(failure: failure, trueDistribution: trueDistribution, safe: safe, distances: distances, backbone: backbone)
}

func unsatisfiableCore(_ formula: Formula) -> UnsatisfiableCore {
    var remaining = Set(1..<(formula.clauses.count + 1))
    var decisions = 0
    var conflicts = 0
    for removed in 1..<(formula.clauses.count + 1) {
        let candidates = formula.clauses.enumerated().filter { remaining.contains($0.offset + 1) && $0.offset + 1 != removed }
            .map { $0.element }
        let trial = solveFormula(Formula(variables: formula.variables, clauses: candidates), limit: 1)
        decisions += trial.statistics.decisions
        conflicts += trial.statistics.conflicts
        if trial.status == "UNSAT" { remaining.remove(removed) }
    }
    return UnsatisfiableCore(clauses: remaining.sorted(), decisions: decisions, conflicts: conflicts)
}

func executeChromatic(_ job: Job, _ graphs: [String: Graph]) {
    let graph = graphs[job.arguments[0]]!
    job.graph = graph
    for colors in 1...Int(job.arguments[1])! {
        let solution = solveFormula(coloring(graph, colors), limit: 1)
        job.attempts.append(ColorAttempt(colors: colors, solution: solution))
        job.statistics.accumulate(solution.statistics)
        job.rounds += solution.rounds
        job.removed += solution.preparation.removed
        job.solution = solution
        job.colors = colors
        if solution.status == "SAT" {
            job.chromatic = colors
            break
        }
    }
}

func executeStandard(_ job: Job, _ graphs: [String: Graph]) throws {
    let arguments = job.arguments
    let formula: Formula
    let limit: Int
    switch job.command {
    case "SOLVE", "ENUM", "CORE":
        formula = try readDIMACS(arguments[0])
        limit = job.command == "ENUM" ? Int(arguments[1])! : 1
    case "QUEENS":
        formula = queens(Int(arguments[0])!)
        limit = Int(arguments[1])!
    case "PIGEON":
        formula = pigeon(Int(arguments[0])!, Int(arguments[1])!)
        limit = Int(arguments[2])!
    default:
        let graph = graphs[arguments[0]]!
        job.graph = graph
        job.colors = Int(arguments[1])!
        formula = coloring(graph, job.colors)
        limit = Int(arguments[2])!
    }
    let solution = solveFormula(formula, limit: limit)
    job.solution = solution
    job.statistics = solution.statistics
    job.rounds = solution.rounds
    job.removed = solution.preparation.removed
    if job.command == "CORE" && solution.status == "UNSAT" { job.core = unsatisfiableCore(formula) }
}

func executeJobs(_ jobs: [Job], _ graphs: [String: Graph]) throws {
    for job in jobs {
        job.error = validateJob(job, graphs)
        if job.error != nil { continue }
        do {
            if job.command == "CHROMATIC" { executeChromatic(job, graphs) }
            else { try executeStandard(job, graphs) }
        } catch InputError.invalid(let reason) {
            job.error = reason
            continue
        }
        job.analysis = analyzeModels(job.solution!)
    }
}

func graphSummary(_ graph: Graph) -> String {
    var degrees = Array(repeating: 0, count: graph.vertices)
    for edge in graph.edges { degrees[edge.first - 1] += 1; degrees[edge.second - 1] += 1 }
    return named([("vertices", String(graph.vertices)), ("edges", String(graph.edges.count)),
                  ("max_degree", String(degrees.max()!)), ("greedy", String(greedyColoring(graph).max()!))])
}

func formulaSummary(_ formula: Formula) -> String {
    let lengths = formula.clauses.map { $0.count }
    return named([("variables", String(formula.variables)), ("clauses", String(lengths.count)),
                  ("literals", String(lengths.reduce(0, +))), ("lengths", frequency(lengths))])
}

func preprocessingReport(_ preparation: Preprocessing) -> [String] {
    let pure = preparation.pure ? "on" : "off"
    var lines = ["preprocess pure=\(pure) tautologies=\(preparation.tautologies) "
        + "duplicate_literals=\(preparation.duplicateLiterals) unit_fixed=\(preparation.unitFixed) "
        + "unit_removed=\(preparation.unitRemoved) subsumed=\(preparation.subsumed) "
        + "pure_fixed=\(preparation.pureFixed) pure_removed=\(preparation.pureRemoved) removed=\(preparation.removed)",
        "removed_clauses tautology=\(numberList(preparation.tautologyRecords)) unit=\(numberList(preparation.unitRecords)) "
        + "subsumed=\(numberList(preparation.subsumedRecords)) pure=\(numberList(preparation.pureRecords))"]
    if let empty = preparation.emptyClause { lines.append("simplified empty_clause=\(empty)") }
    else {
        let lengths = preparation.clauses.map { $0.count }
        lines.append("simplified clauses=\(lengths.count) literals=\(lengths.reduce(0, +)) lengths=\(frequency(lengths)) "
            + "fixed=\(preparation.fixed.count) active=\(preparation.active.count)")
        let fixed = preparation.fixed.keys.sorted().map { preparation.fixed[$0]! ? $0 : -$0 }
        lines.append("fixed literals=\(numberList(fixed))")
    }
    return lines
}

func searchReport(_ statistics: SearchStatistics) -> String {
    "search decisions=\(statistics.decisions) propagations=\(statistics.propagations) "
        + "conflicts=\(statistics.conflicts) max_depth=\(statistics.maxDepth)"
}

func verificationReport(_ solution: Solution, _ analysis: ModelAnalysis?) -> [String] {
    guard let analysis else { return [] }
    if let failure = analysis.failure { return ["verify failed model=\(failure.model) clause=\(failure.clause)"] }
    return ["verify ok models=\(solution.models.count) clauses=\(solution.formula.clauses.count) "
            + "true_literals=\(frequency(analysis.trueDistribution))"]
}

func analysisReport(_ solution: Solution, _ analysis: ModelAnalysis?) -> [String] {
    guard let analysis else { return [] }
    var lines = ["flips safe=\(analysis.safe.count) variables=\(numberList(analysis.safe))"]
    if !analysis.distances.isEmpty {
        lines.append("diversity pairs=\(analysis.distances.count) min_distance=\(analysis.distances.min()!) "
            + "max_distance=\(analysis.distances.max()!)")
    }
    if solution.stop == "all" { lines.append("backbone size=\(analysis.backbone.count) literals=\(numberList(analysis.backbone))") }
    return lines
}

func traceReport(_ events: [String]) -> String {
    if events.isEmpty { return "trace -" }
    let remaining = events.count - min(events.count, 12)
    return "trace " + events.prefix(12).joined(separator: " ") + (remaining > 0 ? " +\(remaining)" : "")
}

func standardResult(_ job: Job) -> [String] {
    let solution = job.solution!
    var lines = [job.heading]
    if job.command == "COLOR" { lines.append("graph " + graphSummary(job.graph!)) }
    lines.append("formula " + formulaSummary(solution.formula))
    lines += preprocessingReport(solution.preparation)
    lines.append("result \(solution.status) models=\(solution.models.count) rounds=\(solution.rounds) stop=\(solution.stop)")
    lines.append(searchReport(solution.statistics))
    if solution.rounds > 0 { lines.append(traceReport(solution.trace)) }
    lines += verificationReport(solution, job.analysis)
    lines += analysisReport(solution, job.analysis)
    if let core = job.core {
        lines.append("core size=\(core.clauses.count) decisions=\(core.decisions) conflicts=\(core.conflicts) "
            + "clauses=\(numberList(core.clauses))")
    }
    return lines
}

func chromaticResult(_ job: Job) -> [String] {
    let solution = job.solution!
    var lines = [job.heading, "graph " + graphSummary(job.graph!)]
    for attempt in job.attempts {
        let result = attempt.solution
        let statistics = result.statistics
        lines.append("attempt k=\(attempt.colors) clauses=\(result.formula.clauses.count) removed=\(result.preparation.removed) "
            + "result=\(result.status) stop=\(result.stop) decisions=\(statistics.decisions) "
            + "propagations=\(statistics.propagations) conflicts=\(statistics.conflicts) max_depth=\(statistics.maxDepth)")
    }
    lines.append("result \(solution.status) chromatic=\(job.chromatic.map(String.init) ?? "-") attempts=\(job.attempts.count)")
    lines.append(searchReport(job.statistics))
    if let analysis = job.analysis {
        lines += verificationReport(solution, analysis)
        lines.append("flips safe=\(analysis.safe.count) variables=\(numberList(analysis.safe))")
    }
    return lines
}

func resultsSummary(_ jobs: [Job]) -> [String] {
    let valid = jobs.filter { $0.error == nil }
    let sat = valid.filter { $0.solution!.status == "SAT" }.count
    var totals = SearchStatistics()
    var models = 0
    var rounds = 0
    var removed = 0
    for job in valid {
        totals.accumulate(job.statistics)
        models += job.solution!.models.count
        rounds += job.rounds
        removed += job.removed
    }
    var lines = ["SUMMARY jobs=\(jobs.count) sat=\(sat) unsat=\(valid.count - sat) error=\(jobs.count - valid.count)",
                 "totals models=\(models) rounds=\(rounds) decisions=\(totals.decisions) propagations=\(totals.propagations) "
                    + "conflicts=\(totals.conflicts) removed_clauses=\(removed)"]
    for command in commands {
        let members = valid.filter { $0.command == command }
        if members.isEmpty { continue }
        let satCount = members.filter { $0.solution!.status == "SAT" }.count
        var statistics = SearchStatistics()
        for member in members { statistics.accumulate(member.statistics) }
        lines.append("command \(command) jobs=\(members.count) sat=\(satCount) unsat=\(members.count - satCount) "
            + "decisions=\(statistics.decisions) propagations=\(statistics.propagations) conflicts=\(statistics.conflicts)")
    }
    let criteria: [(String, String, KeyPath<SearchStatistics, Int>)] = [
        ("hardest", "conflicts", \.conflicts), ("deepest", "max_depth", \.maxDepth), ("busiest", "propagations", \.propagations)]
    for (label, field, key) in criteria {
        if let job = valid.sorted(by: { first, second in
            let a = first.statistics[keyPath: key]
            let b = second.statistics[keyPath: key]
            return a == b ? first.number < second.number : a > b
        }).first {
            lines.append("\(label) job=\(job.number) \(field)=\(job.statistics[keyPath: key])")
        }
    }
    return lines
}

func resultParagraphs(_ jobs: [Job]) -> [[String]] {
    var paragraphs = jobs.map { job -> [String] in
        if let error = job.error { return [job.heading, "error " + error] }
        return job.command == "CHROMATIC" ? chromaticResult(job) : standardResult(job)
    }
    paragraphs.append(resultsSummary(jobs))
    return paragraphs
}

func modelParagraphs(_ jobs: [Job]) -> [[String]] {
    var paragraphs: [[String]] = []
    for job in jobs where job.error == nil {
        let models = job.solution!.models
        if models.isEmpty { continue }
        var lines = [job.heading]
        for (index, model) in models.enumerated() {
            lines.append("model \(index + 1)")
            lines += modelLines(model)
        }
        paragraphs.append(lines)
    }
    return paragraphs
}

func queensSymmetries(_ columns: [Int]) -> [[Int]] {
    let n = columns.count
    var variants: [[Int]] = []
    for transform in 0..<8 {
        var current = Array(repeating: 0, count: n)
        for (index, column) in columns.enumerated() {
            let row = index + 1
            let target: (Int, Int)
            switch transform {
            case 0: target = (row, column)
            case 1: target = (column, n + 1 - row)
            case 2: target = (n + 1 - row, n + 1 - column)
            case 3: target = (n + 1 - column, row)
            case 4: target = (row, n + 1 - column)
            case 5: target = (n + 1 - row, column)
            case 6: target = (column, row)
            default: target = (n + 1 - column, n + 1 - row)
            }
            current[target.0 - 1] = target.1
        }
        variants.append(current)
    }
    return variants
}

func canonicalColoring(_ colors: [Int]) -> [Int] {
    var numbers: [Int: Int] = [:]
    return colors.map { color in
        if numbers[color] == nil { numbers[color] = numbers.count + 1 }
        return numbers[color]!
    }
}

struct SymmetryClass {
    let canonical: [Int]
    let orbit: Int
    let first: Int
    var found: Int
}

func classify(_ decoded: [[Int]], _ canonicalize: ([Int]) -> (canonical: [Int], orbit: Int))
    -> (assignments: [Int], classes: [SymmetryClass]) {
    var indexes: [[Int]: Int] = [:]
    var classes: [SymmetryClass] = []
    var assignments: [Int] = []
    for (index, value) in decoded.enumerated() {
        let canonical = canonicalize(value)
        let number: Int
        if let existing = indexes[canonical.canonical] { number = existing }
        else {
            number = classes.count
            indexes[canonical.canonical] = number
            classes.append(SymmetryClass(canonical: canonical.canonical, orbit: canonical.orbit, first: index + 1, found: 0))
        }
        classes[number].found += 1
        assignments.append(number + 1)
    }
    return (assignments, classes)
}

func queensBoards(_ job: Job) -> [String] {
    let n = Int(job.arguments[0])!
    let solution = job.solution!
    let decoded = solution.models.map { positions($0, n, n) }
    let classification = classify(decoded) { columns in
        let variants = queensSymmetries(columns)
        let canonical = variants.min { $0.lexicographicallyPrecedes($1) }!
        return (canonical, Set(variants).count)
    }
    var lines = ["QUEENS job=\(job.number) n=\(n)"]
    for (index, columns) in decoded.enumerated() {
        let group = classification.assignments[index]
        lines.append("solution \(index + 1) columns=\(numberList(columns)) class=\(group)")
        if classification.classes[group - 1].first == index + 1 { lines += queensBoard(columns) }
    }
    for (index, group) in classification.classes.enumerated() {
        lines.append("class \(index + 1) orbit=\(group.orbit) found=\(group.found) first=\(group.first) "
            + "canonical=\(numberList(group.canonical))")
    }
    lines.append("summary solutions=\(solution.models.count) stop=\(solution.stop) classes=\(classification.classes.count)")
    return lines
}

func pigeonBoards(_ job: Job) -> [String] {
    let p = Int(job.arguments[0])!
    let h = Int(job.arguments[1])!
    let solution = job.solution!
    var lines = ["PIGEON job=\(job.number) pigeons=\(p) holes=\(h)"]
    for (index, model) in solution.models.enumerated() {
        let places = positions(model, p, h)
        let empty = (1...h).filter { !places.contains($0) }
        lines.append("assignment \(index + 1) holes=\(numberList(places)) empty=\(numberList(empty))")
    }
    let expected = p > h ? 0 : (0..<p).reduce(1) { $0 * (h - $1) }
    lines.append("summary assignments=\(solution.models.count) stop=\(solution.stop) expected=\(expected)")
    return lines
}

func coloringBoards(_ job: Job) -> [String] {
    let graph = job.graph!
    let solution = job.solution!
    let decoded = solution.models.map { positions($0, graph.vertices, job.colors) }
    let classification = classify(decoded) { (canonicalColoring($0), 0) }
    var lines = ["\(job.command) job=\(job.number) graph=\(graph.name) vertices=\(graph.vertices) "
                    + "edges=\(graph.edges.count) colors=\(job.colors)"]
    let greedy = greedyColoring(graph)
    lines.append("greedy used=\(greedy.max()!) colors=\(numberList(greedy))")
    for (index, colors) in decoded.enumerated() {
        let sizes = (1...job.colors).map { color in colors.filter { $0 == color }.count }
        lines.append("coloring \(index + 1) colors=\(numberList(colors)) used=\(Set(colors).count) "
            + "sizes=\(numberList(sizes)) class=\(classification.assignments[index])")
    }
    for (index, group) in classification.classes.enumerated() {
        lines.append("class \(index + 1) found=\(group.found) first=\(group.first) canonical=\(numberList(group.canonical))")
    }
    lines.append("summary colorings=\(solution.models.count) stop=\(solution.stop) classes=\(classification.classes.count)")
    return lines
}

func boardParagraphs(_ jobs: [Job]) -> [[String]] {
    var paragraphs: [[String]] = []
    for job in jobs where job.error == nil {
        switch job.command {
        case "QUEENS": paragraphs.append(queensBoards(job))
        case "PIGEON": paragraphs.append(pigeonBoards(job))
        case "COLOR", "CHROMATIC": paragraphs.append(coloringBoards(job))
        default: break
        }
    }
    return paragraphs
}

func statisticsLines(_ jobs: [Job]) -> [String] {
    var lines = ["job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds"]
    for job in jobs where job.error == nil {
        let solution = job.solution!
        let statistics = job.statistics
        let values = [String(job.number), job.command, solution.status, String(solution.formula.variables),
                      String(solution.formula.clauses.count), String(job.removed), String(statistics.decisions),
                      String(statistics.propagations), String(statistics.conflicts), String(statistics.maxDepth),
                      String(solution.models.count), String(job.rounds)]
        lines.append(values.joined(separator: ","))
    }
    return lines
}

let graphs = try loadGraphs()
let jobs = try loadJobs()
try executeJobs(jobs, graphs)
try saveParagraphs("results.txt", resultParagraphs(jobs))
try saveParagraphs("models.txt", modelParagraphs(jobs))
try saveParagraphs("boards.txt", boardParagraphs(jobs))
try saveLines("stats.csv", statisticsLines(jobs))
