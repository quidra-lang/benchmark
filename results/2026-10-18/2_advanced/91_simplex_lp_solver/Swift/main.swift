import Foundation
typealias Bounds = [(F?, F?)]
struct Model {
    let name: String, maximize: Bool, names: [String], c: [F], a: [[F]], rhs: [F], comparisons: [String], rowNames: [String], bounds: Bounds, integer: [Bool]
}
func content(_ name: String, _ parsed: Parsed) throws -> Model {
    var names: [String] = []
    for (name, _) in parsed.objective + parsed.constraints.flatMap(\.terms) where !names.contains(name) {
        names.append(name)
    }
    let index = Dictionary(uniqueKeysWithValues: names.enumerated().map {
        ($0.element, $0.offset)
    })
    func coefficients(_ terms: Terms) -> [F] {
        var values = Array(repeating: F(0), count: names.count)
        for (name, value) in terms {
            let i = index[name]!;
            values[i] = values[i] + value
        }
        return values
    }
    let c = coefficients(parsed.objective), a = parsed.constraints.map {
        coefficients($0.terms)
    }
    var seen: Set<String> = []
    for constraint in parsed.constraints where !seen.insert(constraint.name).inserted {
        throw ModelError(line: constraint.line, message: "duplicate constraint \(constraint.name)")
    }
    var bounds: Bounds = Array(repeating: (F(0), nil), count: names.count), integer = Array(repeating: false, count: names.count)
    for bound in parsed.bounds {
        guard let i = index[bound.name] else {
            throw ModelError(line: bound.line, message: "unknown variable \(bound.name)")
        }
        switch bound.lower {
            case .unchanged: break;
            case .infinite: bounds[i].0 = nil;
            case .finite(let v): bounds[i].0 = v
        }
        switch bound.upper {
            case .unchanged: break;
            case .infinite: bounds[i].1 = nil;
            case .finite(let v): bounds[i].1 = v
        }
        if let lower = bounds[i].0, let upper = bounds[i].1, lower > upper {
            throw ModelError(line: bound.line, message: "inconsistent bounds \(bound.name)")
        }
    }
    for (line, declarations) in parsed.integers {
        for name in declarations {
            guard let i = index[name] else {
                throw ModelError(line: line, message: "unknown variable \(name)")
            }
            integer[i] = true;
            bounds[i].0 = bounds[i].0.map {
                F($0.ceil)
            };
            bounds[i].1 = bounds[i].1.map {
                F($0.floor)
            }
            if let lower = bounds[i].0, let upper = bounds[i].1, lower > upper {
                throw ModelError(line: line, message: "inconsistent bounds \(name)")
            }
        }
    }
    for (line, declarations) in parsed.binaries {
        for name in declarations {
            guard let i = index[name] else {
                throw ModelError(line: line, message: "unknown variable \(name)")
            }
            integer[i] = true;
            bounds[i] = (F(0), F(1))
        }
    }
    return Model(name: name, maximize: parsed.maximize, names: names, c: c, a: a, rhs: parsed.constraints.map(\.rhs), comparisons: parsed.constraints.map(\.comparison), rowNames: parsed.constraints.map(\.name), bounds: bounds, integer: integer)
}
struct Substitution {
    let kind: String, offset: F, columns: [(Int, F)]
}
struct Standard {
    let columns: [String], rows: [String], signs: [F], initial: [Int], slacks: [Int?], artificial: Set<Int>, phase1: [F], phase2: [F], constant: F, sign: F, substitutions: [Substitution], upperRows: [Int?]
}
func standard(_ model: Model, _ bounds: Bounds) -> (Standard, Tableau) {
    var columns: [String] = [], substitutions: [Substitution] = [], costs: [F] = []
    for j in model.names.indices {
        let (lower, upper) = bounds[j]
        let kind: String, offset: F
        var parts: [(Int, F)] = []
        if let lower {
            parts.append((columns.count, F(1)));
            columns.append(model.names[j]);
            costs.append(model.c[j]);
            kind = "shift";
            offset = lower
        } else if let upper {
            parts.append((columns.count, F(-1)));
            columns.append(model.names[j] + "'");
            costs.append(-model.c[j]);
            kind = "reflect";
            offset = upper
        } else {
            parts.append((columns.count, F(1)));
            columns.append(model.names[j] + "+");
            costs.append(model.c[j])
            parts.append((columns.count, F(-1)));
            columns.append(model.names[j] + "-");
            costs.append(-model.c[j]);
            kind = "split";
            offset = F(0)
        }
        substitutions.append(Substitution(kind: kind, offset: offset, columns: parts))
    }
    let variableColumns = columns.count
    var rows = model.rowNames, comparisons = model.comparisons, coefficients: [[F]] = [], beta: [F] = []
    for i in model.a.indices {
        var row = Array(repeating: F(0), count: variableColumns), rhs = model.rhs[i]
        for j in model.names.indices {
            rhs = rhs - model.a[i][j] * substitutions[j].offset
            for (k, direction) in substitutions[j].columns {
                row[k] = direction * model.a[i][j]
            }
        }
        coefficients.append(row);
        beta.append(rhs)
    }
    var upperRows: [Int?] = Array(repeating: nil, count: model.names.count)
    for j in model.names.indices where substitutions[j].kind == "shift" {
        if let upper = bounds[j].1 {
            upperRows[j] = rows.count;
            rows.append(model.names[j] + ".ub");
            comparisons.append("<=")
            var row = Array(repeating: F(0), count: variableColumns);
            row[substitutions[j].columns[0].0] = F(1)
            coefficients.append(row);
            beta.append(upper - substitutions[j].offset)
        }
    }
    var signs = Array(repeating: F(1), count: rows.count)
    for i in rows.indices where beta[i] < F(0) {
        signs[i] = F(-1);
        beta[i] = -beta[i];
        coefficients[i] = coefficients[i].map {
            -$0
        }
        comparisons[i] = comparisons[i] == "<=" ? ">=" : comparisons[i] == ">=" ? "<=" : "="
    }
    var initial = Array(repeating: -1, count: rows.count), slacks: [Int?] = Array(repeating: nil, count: rows.count)
    for i in rows.indices where comparisons[i] != "=" {
        let k = columns.count;
        columns.append("s:" + rows[i]);
        costs.append(F(0))
        for j in coefficients.indices {
            coefficients[j].append(F(0))
        }
        coefficients[i][k] = F(comparisons[i] == "<=" ? 1 : -1);
        slacks[i] = k
        if comparisons[i] == "<=" {
            initial[i] = k
        }
    }
    var artificial: Set<Int> = []
    for i in rows.indices where comparisons[i] != "<=" {
        let k = columns.count;
        columns.append("a:" + rows[i]);
        costs.append(F(0))
        for j in coefficients.indices {
            coefficients[j].append(F(0))
        }
        coefficients[i][k] = F(1);
        initial[i] = k;
        artificial.insert(k)
    }
    let sign = F(model.maximize ? -1 : 1), constant = model.names.indices.reduce(F(0)) {
        $0 + model.c[$1] * substitutions[$1].offset
    }
    let phase1 = columns.indices.map {
        F(artificial.contains($0) ? 1 : 0)
    }, phase2 = costs.map {
        sign * $0
    }
    return (Standard(columns: columns, rows: rows, signs: signs, initial: initial, slacks: slacks, artificial: artificial, phase1: phase1, phase2: phase2, constant: constant, sign: sign, substitutions: substitutions, upperRows: upperRows), Tableau(t: coefficients, beta: beta, basis: initial))
}
struct LPResult {
    let standard: Standard, tableau: Tableau, status: String, value: F, solution: [F], phase1: Int, phase2: Int, drives: Int, infeasibility: F, multipliers: [F], ray: [F], rate: F
    var pivots: Int {
        phase1 + phase2 + drives
    }
}
func recover(_ standard: Standard, _ columns: [F], _ offset: Bool) -> [F] {
    standard.substitutions.map {
        value in value.columns.reduce(offset ? value.offset : F(0)) {
            $0 + $1.1 * columns[$1.0]
        }
    }
}
func solveLP(_ model: Model, _ bounds: Bounds, _ node: Int, _ level: Int, _ log: inout [String]) -> LPResult {
    let (s, initialTableau) = standard(model, bounds)
    var t = initialTableau
    log.append("SOLVE node \(node) rows \(s.rows.count) columns \(s.columns.count) artificials \(s.artificial.count)")
    if level >= 1 {
        for (j, value) in s.substitutions.enumerated() {
            var line = "MAP \(model.names[j]) \(value.kind)"
            if value.kind != "split" {
                line += " \(value.offset)";
                if value.kind == "shift", let upper = bounds[j].1 {
                    line += " upper \(upper)"
                }
            }
            log.append(line)
        }
        for i in s.signs.indices where s.signs[i] < F(0) {
            log.append("FLIP \(s.rows[i])")
        }
    }
    var phase1 = 0, phase2 = 0, drives = 0, redundant = 0, status = "OPTIMAL", infeasibility = F(0), unbounded: Int?
    if !s.artificial.isEmpty {
        if level >= 1 {
            log.append("PHASE 1")
        }
        if level >= 2 {
            log += t.display("phase 1 start", s.columns, s.rows, s.phase1, F(0), F(1))
        }
        phase1 = Simplex.phase(&t, s.phase1, Array(s.columns.indices), s.columns, s.rows, F(0), F(1), level, &log).0
        infeasibility = t.value(s.phase1)
        if level >= 1 {
            log.append("PHASE 1 END objective \(infeasibility) iterations \(phase1)")
        }
        if infeasibility > F(0) {
            status = "INFEASIBLE"
            if level >= 2 {
                log += t.display("final", s.columns, s.rows, s.phase1, F(0), F(1))
            }
        } else {
            for i in s.rows.indices where s.artificial.contains(t.basis[i]) {
                if let k = s.columns.indices.first(where: {
                    !s.artificial.contains($0) && t.t[i][$0] != F(0)
                }) {
                    if level >= 1 {
                        log.append("DRIVE row \(s.rows[i]) enter \(s.columns[k]) leave \(s.columns[t.basis[i]])")
                    }
                    t.pivot(i, k);
                    drives += 1
                } else {
                    redundant += 1;
                    if level >= 1 {
                        log.append("REDUNDANT row \(s.rows[i])")
                    }
                }
            }
        }
    }
    if status != "INFEASIBLE" {
        if level >= 1 {
            log.append("PHASE 2")
        }
        if level >= 2 {
            log += t.display("phase 2 start", s.columns, s.rows, s.phase2, s.constant, s.sign)
        }
        let candidates = s.columns.indices.filter {
            !s.artificial.contains($0)
        }
        (phase2, unbounded) = Simplex.phase(&t, s.phase2, candidates, s.columns, s.rows, s.constant, s.sign, level, &log)
        if let k = unbounded {
            status = "UNBOUNDED";
            if level >= 1 {
                log.append("UNBOUNDED enter \(s.columns[k])")
            }
        }
        if level >= 1 {
            log.append("PHASE 2 END objective \(s.constant + s.sign * t.value(s.phase2)) iterations \(phase2)")
        }
        if level >= 2 {
            log += t.display("final", s.columns, s.rows, s.phase2, s.constant, s.sign)
        }
    }
    let value = s.constant + s.sign * t.value(s.phase2)
    var columnValues = Array(repeating: F(0), count: s.columns.count)
    for i in s.rows.indices {
        columnValues[t.basis[i]] = t.beta[i]
    }
    let solution = recover(s, columnValues, true), reduced = t.reduced(s.phase1)
    let multipliers = status == "INFEASIBLE" ? s.initial.enumerated().map {
        s.signs[$0.offset] * (s.phase1[$0.element] - reduced[$0.element])
    } : []
    var ray: [F] = [], rate = F(0)
    if let q = unbounded {
        var direction = Array(repeating: F(0), count: s.columns.count);
        direction[q] = F(1)
        for i in s.rows.indices {
            direction[t.basis[i]] = -t.t[i][q]
        }
        ray = recover(s, direction, false);
        rate = model.c.indices.reduce(F(0)) {
            $0 + model.c[$1] * ray[$1]
        }
    }
    log.append("RESULT \(status) objective \(status == "OPTIMAL" ? value.description : "-") phase1 \(phase1) phase2 \(phase2) drives \(drives) redundant \(redundant)")
    return LPResult(standard: s, tableau: t, status: status, value: value, solution: solution, phase1: phase1, phase2: phase2, drives: drives, infeasibility: infeasibility, multipliers: multipliers, ray: ray, rate: rate)
}
func interval(_ value: F, _ lower: F?, _ upper: F?) -> (String, String) {
    (lower.map {
        (value + $0).description
    } ?? "-inf", upper.map {
        (value + $0).description
    } ?? "inf")
}
func sensitivity(_ model: Model, _ result: LPResult) -> [String] {
    let s = result.standard, t = result.tableau, reducedColumns = t.reduced(s.phase2), basic = Set(t.basis)
    let nonbasic = s.columns.indices.filter {
        !basic.contains($0) && !s.artificial.contains($0)
    }
    let prices = model.a.indices.map {
        -s.sign * s.signs[$0] * reducedColumns[s.initial[$0]]
    }
    let reduced = model.names.indices.map {
        j in model.c[j] - model.a.indices.reduce(F(0)) {
            $0 + prices[$1] * model.a[$1][j]
        }
    }
    let objective = model.a.indices.reduce(F(0)) {
        $0 + prices[$1] * model.rhs[$1]
    } + model.names.indices.reduce(F(0)) {
        $0 + reduced[$1] * result.solution[$1]
    }
    var lines = ["MODEL \(model.name) \(model.integer.contains(true) ? "relaxation" : "lp") objective \(result.value)", "BASIS " + t.basis.map {
        s.columns[$0]
    }.joined(separator: " "), "DEGENERACY primal \(s.rows.indices.filter { !s.artificial.contains(t.basis[$0]) && t.beta[$0] == F(0) }.count) dual \(nonbasic.filter { reducedColumns[$0] == F(0) }.count)", "DUAL objective \(objective)"]
    for i in model.a.indices {
        let column = s.initial[i], rho = s.rows.indices.map {
            s.signs[i] * t.t[$0][column]
        }
        var lower: F?, upper: F?
        let fixed = s.rows.indices.contains {
            rho[$0] != F(0) && s.artificial.contains(t.basis[$0])
        }
        let ends: (String, String)
        if fixed {
            ends = (model.rhs[i].description, model.rhs[i].description)
        }
        else {
            for j in s.rows.indices {
                if rho[j] > F(0) {
                    let value = -t.beta[j] / rho[j];
                    lower = max(lower ?? value, value)
                }
                else if rho[j] < F(0) {
                    let value = -t.beta[j] / rho[j];
                    upper = min(upper ?? value, value)
                }
            }
            ends = interval(model.rhs[i], lower, upper)
        }
        lines.append("CONSTRAINT \(model.rowNames[i]) price \(prices[i]) rhs \(model.rhs[i]) range \(ends.0) \(ends.1)")
    }
    for j in model.names.indices {
        let variable = s.substitutions[j], status: String
        if variable.kind == "split" {
            status = variable.columns.allSatisfy {
                !basic.contains($0.0)
            } ? "zero" : "basic"
        }
        else if !basic.contains(variable.columns[0].0) {
            status = variable.kind == "shift" ? "lower" : "upper"
        }
        else if variable.kind == "shift", let i = s.upperRows[j], !basic.contains(s.slacks[i]!) {
            status = "upper"
        }
        else {
            status = "basic"
        }
        var h = Array(repeating: F(0), count: s.columns.count)
        for (k, direction) in variable.columns {
            h[k] = s.sign * direction
        }
        let eta = t.reduced(h)
        var lower: F?, upper: F?
        for k in nonbasic {
            if eta[k] > F(0) {
                let value = -reducedColumns[k] / eta[k];
                lower = max(lower ?? value, value)
            }
            else if eta[k] < F(0) {
                let value = -reducedColumns[k] / eta[k];
                upper = min(upper ?? value, value)
            }
        }
        let ends = interval(model.c[j], lower, upper)
        lines.append("VARIABLE \(model.names[j]) \(status) value \(result.solution[j]) reduced \(reduced[j]) cost \(model.c[j]) range \(ends.0) \(ends.1)")
    }
    return lines
}
func statistics(_ model: Model) -> String {
    let matrix = model.a.flatMap {
        $0
    }.filter {
        $0 != F(0)
    }.map(\.absolute), objective = model.c.filter {
        $0 != F(0)
    }.map(\.absolute), rhs = model.rhs.filter {
        $0 != F(0)
    }.map(\.absolute)
    let bounds = model.bounds.flatMap {
        [$0.0, $0.1].compactMap {
            $0
        }
    }.filter {
        $0 != F(0)
    }.map(\.absolute)
    func range(_ values: [F]) -> String {
        values.isEmpty ? "- -" : "\(values.min()!) \(values.max()!)"
    }
    return "STATS nonzeros \(matrix.count) matrix \(range(matrix)) objective \(range(objective)) rhs \(range(rhs)) bounds \(range(bounds))"
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
let blocks = LPParser.read(), params = LPParser.params()
var iterations: [String] = [], solutions: [String] = [], sensitivityLines: [String] = [], tree: [String] = [], csv = ["model,status,objective,approx,relaxation,nodes,pivots"]
var statuses = Array(repeating: 0, count: 5), totals = Array(repeating: 0, count: 4), analyzed = 0, integerModels = 0, integerNodes = 0, limits = 0
for block in blocks {
    let model: Model
    do {
        if let error = block.error {
            throw error
        };
        model = try content(block.name, block.parsed!)
    }
    catch let error as ModelError {
        statuses[4] += 1;
        iterations.append("MODEL \(block.name) error");
        solutions += ["MODEL \(block.name)", "STATUS ERROR line \(error.line) \(error.message)"]
        sensitivityLines.append("MODEL \(block.name) skipped ERROR");
        csv.append("\(block.name),ERROR,-,-,-,0,0");
        continue
    } catch {
        fatalError("invalid model")
    }
    let integer = model.integer.contains(true), level = params.levels[model.name] ?? params.level, limit = params.limits[model.name] ?? params.limit
    iterations.append("MODEL \(model.name) level \(level)")
    let outcome: Outcome
    if integer {
        outcome = BranchBound.solve(model, limit, level, &iterations)
    }
    else {
        let root = solveLP(model, model.bounds, 1, level, &iterations)
        outcome = Outcome(status: root.status, root: root, solution: root.status == "OPTIMAL" ? root.solution : nil, objective: root.status == "OPTIMAL" ? root.value : nil, nodes: 1, phase1: root.phase1, phase2: root.phase2, drives: root.drives, lines: [])
    }
    let root = outcome.root, status = outcome.status
    statuses[["OPTIMAL", "INFEASIBLE", "UNBOUNDED", "NODE_LIMIT"].firstIndex(of: status)!] += 1
    totals[0] += outcome.nodes;
    totals[1] += outcome.phase1;
    totals[2] += outcome.phase2;
    totals[3] += outcome.drives
    if integer {
        integerModels += 1;
        integerNodes += outcome.nodes;
        limits += status == "NODE_LIMIT" ? 1 : 0;
        tree += outcome.lines
    }
    solutions += ["MODEL \(model.name) \(model.maximize ? "maximize" : "minimize") variables \(model.names.count) constraints \(model.a.count) integers \(model.integer.filter { $0 }.count)", statistics(model), "STATUS \(status)"]
    if let value = outcome.objective {
        solutions.append("OBJECTIVE \(value) approx \(value.approximate)")
    }
    if integer && root.status == "OPTIMAL" {
        solutions.append("RELAXATION \(root.value) approx \(root.value.approximate)")
    }
    if root.status == "INFEASIBLE" {
        solutions.append("INFEASIBILITY \(root.infeasibility)")
        for (i, multiplier) in root.multipliers.enumerated() {
            solutions.append("FARKAS \(root.standard.rows[i]) \(multiplier)")
        }
    }
    if outcome.solution != nil || status == "UNBOUNDED" {
        for (j, value) in (outcome.solution ?? root.solution).enumerated() {
            solutions.append("VALUE \(model.names[j]) \(value)")
        }
    }
    if status == "UNBOUNDED" {
        for (j, value) in root.ray.enumerated() {
            solutions.append("RAY \(model.names[j]) \(value)")
        };
        solutions.append("RATE \(root.rate)")
    }
    if let values = outcome.solution {
        for i in model.a.indices {
            let value = model.names.indices.reduce(F(0)) {
                $0 + model.a[i][$1] * values[$1]
            }, margin = model.comparisons[i] == "<=" ? model.rhs[i] - value : value - model.rhs[i]
            solutions.append("ROW \(model.rowNames[i]) \(value) \(margin)")
        }
    }
    if integer {
        solutions.append("NODES \(outcome.nodes)")
    };
    solutions.append("PIVOTS \(outcome.pivots)")
    if root.status == "OPTIMAL" {
        analyzed += 1;
        sensitivityLines += sensitivity(model, root)
    } else {
        sensitivityLines.append("MODEL \(model.name) skipped \(root.status)")
    }
    csv.append("\(model.name),\(status),\(outcome.objective?.description ?? "-"),\(outcome.objective?.approximate ?? "-"),\(root.status == "OPTIMAL" ? root.value.description : "-"),\(outcome.nodes),\(outcome.pivots)")
}
iterations.append("TOTAL solves \(totals[0]) phase1 \(totals[1]) phase2 \(totals[2]) drives \(totals[3]) pivots \(totals[1] + totals[2] + totals[3])")
solutions.append("SUMMARY models \(blocks.count) optimal \(statuses[0]) infeasible \(statuses[1]) unbounded \(statuses[2]) node_limit \(statuses[3]) error \(statuses[4])")
sensitivityLines.append("SUMMARY analyzed \(analyzed) skipped \(blocks.count - analyzed)");
tree.append("SUMMARY models \(integerModels) nodes \(integerNodes) node_limit \(limits)")
write("iterations.txt", iterations);
write("solutions.txt", solutions);
write("sensitivity.txt", sensitivityLines);
write("bnb_tree.txt", tree);
write("summary.csv", csv)
