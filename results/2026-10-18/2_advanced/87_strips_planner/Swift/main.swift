import Foundation
func arguments(_ domain: Domain, _ args: [String], _ expected: [String], _ table: [String: String], _ noun: String) -> String? {
    if args.count != expected.count {
        return "expected \(expected.count) arguments, got \(args.count)"
    }
    for (i, pair) in zip(args, expected).enumerated() {
        let (name, type) = pair
        guard let actual = table[name] else {
            return "unknown \(noun) \(name)"
        }
        if !Grounder.subtype(domain, actual, type) {
            return "argument \(i + 1) (\(name)) is not of type \(type)"
        }
    }
    return nil
}
func atomError(_ domain: Domain, _ atom: Atom, _ table: [String: String], _ noun: String, _ equality: Bool) -> String? {
    let types: [String]
    if equality && atom.predicate == "=" {
        types = ["object", "object"]
    }
    else if let predicate = domain.predicates.first(where: {
        $0.name == atom.predicate
    }) {
        types = predicate.types
    }
    else {
        return "unknown predicate \(atom.predicate)"
    }
    return arguments(domain, atom.terms, types, table, noun)
}
func validateDomain(_ domain: Domain) {
    var actions: [Schema] = []
    for action in domain.actions {
        let table = Dictionary(uniqueKeysWithValues: action.parameters)
        var error = action.parameters.first {
            !domain.typeOrder.contains($0.1)
        }.map {
            "unknown type \($0.1)"
        }
        if error == nil {
            for literal in action.pre + action.effects {
                if let reason = atomError(domain, literal.atom, table, "variable", true) {
                    error = "\(literal.atom.text): \(reason)";
                    break
                }
            }
        }
        if let error {
            domain.diagnostics.append("error: action \(action.name): \(error)")
        } else {
            actions.append(action)
        }
    }
    domain.actions = actions
    for predicate in domain.predicates where !domain.actions.contains(where: {
        ($0.pre + $0.effects).contains {
            $0.atom.predicate == predicate.name
        }
    }) {
        domain.diagnostics.append("warning: predicate \(predicate.name) is not used by any action")
    }
}
func validateProblem(_ domain: Domain, _ problem: Problem) {
    let table = Dictionary(uniqueKeysWithValues: problem.objects)
    for side in 0..<2 {
        let original = side == 0 ? problem.initial : problem.goals
        var seen: Set<Atom> = [], kept: [Atom] = []
        for atom in original {
            let error = atomError(domain, atom, table, "object", false) ?? (seen.contains(atom) ? "duplicate" : nil)
            if let error {
                problem.diagnostics.append("warning: \(side == 0 ? "init" : "goal") \(atom.text): \(error)")
            }
            else {
                seen.insert(atom);
                kept.append(atom)
            }
        }
        if side == 0 {
            problem.initial = kept
        } else {
            problem.goals = kept
        }
    }
}
func list(_ heading: String, _ values: [String]) -> String {
    heading + " " + (values.isEmpty ? "-" : values.joined(separator: " "))
}
func numbers(_ values: State) -> String {
    values.isEmpty ? "-" : values.sorted().map(String.init).joined(separator: ",")
}
func hText(_ value: Int) -> String {
    value >= Heuristics.infinity ? "inf" : String(value)
}
func hValues(_ values: [Int]) -> String {
    zip(["goalcount", "hmax", "hadd", "ff", "lmcount"], values).map {
        "\($0.0)=\(hText($0.1))"
    }.joined(separator: " ")
}
func cost(_ grounding: Grounding, _ plan: [Int]) -> Int {
    plan.reduce(0) {
        $0 + grounding.actions[$1].cost
    }
}
func domainReport(_ domain: Domain) -> [String] {
    var lines = ["== domain \(domain.name) =="] + domain.diagnostics
    for type in domain.typeOrder {
        var chain = [type], current = type
        while let parent = domain.parents[current] {
            chain.append(parent);
            current = parent
        }
        lines.append("type " + chain.joined(separator: " < "))
    }
    let fluent = Grounder.fluents(domain)
    for predicate in domain.predicates {
        lines.append("predicate \(predicate.name)/\(predicate.types.count) \(fluent.contains(predicate.name) ? "fluent" : "static")")
    }
    for action in domain.actions {
        lines.append("action \(action.name)/\(action.parameters.count) cost=\(action.cost) pre=\(action.pre.count) add=\(action.effects.filter { !$0.negative }.count) del=\(action.effects.filter(\.negative).count)")
    }
    return lines
}
func groundingReport(_ domain: Domain, _ problem: Problem, _ g: Grounding) -> [String] {
    var lines = ["", "== problem \(problem.name) =="] + problem.diagnostics + ["objects: \(problem.objects.count)"]
    for type in domain.typeOrder {
        lines.append(list("  \(type):", problem.objects.filter {
            Grounder.subtype(domain, $0.1, type)
        }.map {
            $0.0
        }))
    }
    lines.append("static facts: \(g.staticCount)")
    for (i, action) in domain.actions.enumerated() {
        let s = g.stats[i];
        lines.append("schema \(action.name): assignments=\(s[0]) candidates=\(s[1]) reachable=\(s[2])")
    }
    lines += ["candidates: \(g.stats.reduce(0) { $0 + $1[1] }) reachable: \(g.actions.count)", "facts: \(g.facts.count) init: \(g.initial.count) goals: \(g.goals.count)"]
    for atom in g.unreachable {
        lines.append("unreachable goal: \(atom.text)")
    }
    lines.append(list("facts by predicate:", domain.predicates.filter {
        g.fluent.contains($0.name)
    }.map {
        p in "\(p.name)=\(g.facts.filter { $0.predicate == p.name }.count)"
    }))
    lines.append("facts:")
    for (i, atom) in g.facts.enumerated() {
        lines.append("  \(i) \(atom.text)")
    }
    lines.append("actions:")
    for (i, action) in g.actions.enumerated() {
        lines.append("  \(i) \(action.text) cost=\(action.cost) pre=\(numbers(action.pre)) neg=\(numbers(action.neg)) add=\(numbers(action.add)) del=\(numbers(action.del))")
    }
    return lines
}
struct Validation {
    let status: String, messages: [String], correct: Int
    var verdict: String {
        status == "valid" ? "valid \(messages[0])" : "\(status): \(messages[0])"
    }
}
func validateSteps(_ domain: Domain, _ problem: Problem, _ steps: [Atom]) -> Validation {
    var world = Set(problem.initial), cost = 0
    let table = Dictionary(uniqueKeysWithValues: problem.objects)
    for (k, step) in steps.enumerated() {
        guard let action = domain.actions.first(where: {
            $0.name == step.predicate
        }) else {
            return Validation(status: "invalid", messages: ["step \(k + 1) \(step.text): unknown action \(step.predicate)"], correct: k)
        }
        if let error = arguments(domain, step.terms, action.parameters.map {
            $0.1
        }, table, "object") {
            return Validation(status: "invalid", messages: ["step \(k + 1) \(step.text): \(error)"], correct: k)
        }
        let values = Dictionary(uniqueKeysWithValues: zip(action.parameters.map {
            $0.0
        }, step.terms))
        for literal in action.pre {
            let literal = literal.replace(values), atom = literal.atom
            let truth = atom.predicate == "=" ? atom.terms[0] == atom.terms[1] : world.contains(atom)
            if truth == literal.negative {
                return Validation(status: "invalid", messages: ["step \(k + 1) \(step.text): precondition \(literal.text) is false"], correct: k)
            }
        }
        for literal in action.effects where literal.negative {
            world.remove(literal.atom.replace(values))
        }
        for literal in action.effects where !literal.negative {
            world.insert(literal.atom.replace(values))
        }
        cost += action.cost
    }
    let missing = problem.goals.filter {
        !world.contains($0)
    }.map {
        "unsatisfied goal \($0.text)"
    }
    return missing.isEmpty ? Validation(status: "valid", messages: ["length=\(steps.count) cost=\(cost)"], correct: steps.count) : Validation(status: "goal not reached", messages: missing, correct: steps.count)
}
func steps(_ g: Grounding, _ plan: [Int]) -> [Atom] {
    plan.map {
        Atom(g.actions[$0].name, g.actions[$0].args)
    }
}
func mapSteps(_ g: Grounding, _ steps: [Atom]) -> [Int] {
    steps.map {
        step in g.actions.firstIndex {
            $0.name == step.predicate && $0.args == step.terms
        }!
    }
}
func interfere(_ a: Action, _ b: Action) -> Bool {
    !a.del.isDisjoint(with: b.pre) || !a.del.isDisjoint(with: b.add) || !b.del.isDisjoint(with: a.pre) || !b.del.isDisjoint(with: a.add) || !a.add.isDisjoint(with: b.neg) || !b.add.isDisjoint(with: a.neg)
}
func parallel(_ g: Grounding, _ plan: [Int]) -> [[Int]] {
    var levels: [Int] = []
    for (j, action) in plan.enumerated() {
        var level = 0
        for i in 0..<j {
            let a = g.actions[plan[i]], b = g.actions[action]
            if !a.add.isDisjoint(with: b.pre) || !a.del.isDisjoint(with: b.neg) || interfere(a, b) {
                level = max(level, levels[i])
            }
        }
        levels.append(level + 1)
    }
    var layers = Array(repeating: [Int](), count: levels.max() ?? 0)
    for (i, action) in plan.enumerated() {
        layers[levels[i] - 1].append(action)
    }
    return layers
}
func parallelVerdict(_ g: Grounding, _ layers: [[Int]]) -> String {
    var state = g.initial
    for (k, layer) in layers.enumerated() {
        let bad = layer.enumerated().contains {
            i, a in layer.dropFirst(i + 1).contains {
                interfere(g.actions[a], g.actions[$0])
            }
        }
        if layer.contains(where: {
            !Search.applicable(g.actions[$0], state)
        }) || bad {
            return "invalid at layer \(k + 1)"
        }
        state.subtract(Set(layer.flatMap {
            g.actions[$0].del
        }))
        for action in layer {
            state.formUnion(g.actions[action].add)
        }
    }
    return g.goals.isSubset(of: state) ? "valid" : "goal not reached"
}
func improve(_ g: Grounding, _ input: [Int]) -> [Int] {
    var plan = input, i = 0
    while i < plan.count {
        var state = g.initial
        for action in plan.prefix(i) {
            state = Search.apply(g.actions[action], state)
        }
        var next = Array(plan.prefix(i))
        for action in plan.dropFirst(i + 1) where Search.applicable(g.actions[action], state) {
            state = Search.apply(g.actions[action], state);
            next.append(action)
        }
        if g.goals.isSubset(of: state) {
            plan = next
        } else {
            i += 1
        }
    }
    return plan
}
func transformed(_ g: Grounding) -> ([Action], State, Int) {
    let negatives = Set(g.actions.flatMap(\.neg)).sorted(), complements = Dictionary(uniqueKeysWithValues: negatives.enumerated().map {
        ($0.element, g.facts.count + $0.offset)
    })
    var initial = g.initial, actions = g.actions
    for (fact, complement) in complements where !initial.contains(fact) {
        initial.insert(complement)
    }
    for i in actions.indices {
        let original = g.actions[i]
        actions[i].pre.formUnion(original.neg.map {
            complements[$0]!
        })
        actions[i].add.formUnion(original.del.compactMap {
            complements[$0]
        })
        actions[i].del.formUnion(original.add.compactMap {
            complements[$0]
        })
    }
    return (actions, initial, negatives.count)
}
struct Params {
    var budget = 0, weight = 0, limit = 0, runs: [(String, String)] = [], repair = ("", "")
    static func read() -> Self {
        var p = Self()
        for line in (try! String(contentsOfFile: "input/params.txt", encoding: .ascii)).split(separator: "\n") where line.first != "#" {
            let a = line.split(separator: " ").map(String.init)
            switch a[0] {
                case "budget": p.budget = Int(a[1])!
                case "weight": p.weight = Int(a[1])!
                case "graphplan": p.limit = Int(a[1])!
                case "run": p.runs.append((a[1], a[2]))
                default: p.repair = (a[1], a[2])
            }
        }
        return p
    }
}
struct Candidate {
    let problem: String, label: String;
    var steps: [Atom] = []
}
func readCandidates() -> [Candidate] {
    var result: [Candidate] = []
    for line in (try! String(contentsOfFile: "input/candidates.txt", encoding: .ascii)).split(separator: "\n") where line.first != "#" {
        if line.hasPrefix("plan ") {
            let a = line.split(separator: " ").map(String.init);
            result.append(Candidate(problem: a[1], label: a[2]))
        }
        else if line != "end" {
            let a = line.dropFirst().dropLast().split(separator: " ").map(String.init);
            result[result.count - 1].steps.append(Atom(a[0], Array(a.dropFirst())))
        }
    }
    return result
}
func planBlock(_ domain: Domain, _ problem: Problem, _ g: Grounding, _ plan: [Int], _ tag: String, _ landmarks: State, _ seen: inout [([Int], String)]) -> ([String], [String], Bool) {
    let same = seen.first {
        $0.0 == plan
    }.map {
        " (same as \($0.1))"
    } ?? ""
    if same.isEmpty {
        seen.append((plan, tag))
    }
    var lines = ["plan: length=\(plan.count) cost=\(cost(g, plan))\(same)"]
    for (k, action) in plan.enumerated() {
        lines.append("  \(k + 1) \(g.actions[action].text)")
    }
    lines.append(list("schemas:", domain.actions.enumerated().compactMap {
        i, action in let count = plan.filter {
            g.actions[$0].source == i
        }.count;
        return count == 0 ? nil : "\(action.name)=\(count)"
    }))
    let layers = parallel(g, plan)
    lines.append("parallel: layers=\(layers.count)")
    for (k, layer) in layers.enumerated() {
        lines.append(list("  \(k + 1):", layer.map {
            g.actions[$0].text
        }))
    }
    let improved = improve(g, plan)
    lines.append("improved: length=\(improved.count) cost=\(cost(g, improved)) removed=\(plan.count - improved.count)")
    if improved.count < plan.count {
        for (k, action) in improved.enumerated() {
            lines.append("  \(k + 1) \(g.actions[action].text)")
        }
    }
    var state = g.initial, reached: State = []
    for action in plan {
        state = Search.apply(g.actions[action], state);
        reached.formUnion(state.intersection(landmarks))
    }
    lines.append("landmarks reached: \(reached.count)/\(landmarks.count)")
    for fact in landmarks.subtracting(reached).sorted() {
        lines.append("  missed \(g.facts[fact].text)")
    }
    let original = validateSteps(domain, problem, steps(g, plan)), checkedImproved = validateSteps(domain, problem, steps(g, improved))
    return (lines, ["\(tag): \(original.verdict)", "  parallel: \(parallelVerdict(g, layers))", "  improved: \(checkedImproved.verdict)"], original.status == "valid")
}
func profile(_ g: Grounding, _ plan: [Int], _ tag: String) -> [String] {
    var lines = ["-- profile (\(tag)) --"], state = g.initial, remaining = cost(g, plan), over = [0, 0, 0, 0, 0]
    for k in 0...plan.count {
        let values = Heuristics.values(g, state)
        for i in 0..<5 where values[i] > remaining {
            over[i] += 1
        }
        lines.append("  \(k): h*=\(remaining) \(hValues(values))")
        if k < plan.count {
            state = Search.apply(g.actions[plan[k]], state);
            remaining -= g.actions[plan[k]].cost
        }
    }
    lines += ["overestimates: \(hValues(over))", "-- causal links (\(tag)) --"]
    var suppliers = Array(repeating: 0, count: g.facts.count)
    for (k, action) in plan.enumerated() {
        lines.append(list("  \(k + 1) \(g.actions[action].text):", g.actions[action].pre.sorted().map {
            "\(g.facts[$0].text)<-\(suppliers[$0])"
        }))
        for fact in g.actions[action].add {
            suppliers[fact] = k + 1
        }
    }
    lines.append(list("  goal:", g.goals.sorted().map {
        "\(g.facts[$0].text)<-\(suppliers[$0])"
    }))
    return lines
}
func resultLine(_ result: SearchResult, _ unreachable: Bool) -> String {
    if unreachable {
        return "result: FAIL (unreachable goal)"
    }
    return result.status == "solved" ? "result: solved expanded=\(result.expanded) generated=\(result.generated)" : "result: FAIL (\(result.status)) expanded=\(result.expanded) generated=\(result.generated)"
}
func write(_ file: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + file, atomically: false, encoding: .ascii)
}
func runProgram() {
    let domain = PDDLParser.domain()
    validateDomain(domain)
    let problems = PDDLParser.problems()
    for problem in problems {
        validateProblem(domain, problem)
    }
    let params = Params.read(), grounds = problems.map {
        Grounder.ground(domain, $0)
    }, tags = params.runs.map {
        $0.0 + " " + $0.1
    } + ["graphplan"]
    var groundingLines = domainReport(domain), plans: [String] = [], graphLines: [String] = [], validation: [String] = [], comparison = ["problem,algorithm,heuristic,length,cost,expanded,generated"], problemSummary: [String] = []
    var tagStats = Array(repeating: [0, 0, 0, 0], count: tags.count), bests: [Int?] = [], analyzed = 0, validPlans = 0
    for (index, problem) in problems.enumerated() {
        let g = grounds[index], unreachable = !g.unreachable.isEmpty
        groundingLines += groundingReport(domain, problem, g)
        plans.append("== problem \(problem.name) ==");
        validation.append("== problem \(problem.name) ==");
        graphLines.append("== problem \(problem.name) ==")
        var landmarks: State = []
        if unreachable {
            plans.append("initial h: unreachable goal")
        }
        else {
            plans.append("initial h: \(hValues(Heuristics.values(g, g.initial)))")
            landmarks = Heuristics.landmarks(g, g.initial) ?? []
            plans.append("landmarks: \(landmarks.count)")
            for fact in landmarks.sorted() {
                plans.append("  \(g.facts[fact].text)")
            }
            let (ff, relaxed, helpful) = Heuristics.relaxed(g, g.initial)
            plans.append("relaxed plan: length=\(relaxed.count) cost=\(hText(ff))")
            for action in relaxed {
                plans.append("  \(g.actions[action].text)")
            }
            plans.append(list("helpful:", helpful.map {
                g.actions[$0].text
            }))
        }
        var results = params.runs.map {
            algorithm, heuristic in unreachable ? SearchResult.failure("unreachable goal") : Search.run(g, g.initial, algorithm, heuristic, params.budget, params.weight)
        }
        if unreachable {
            graphLines.append("result: FAIL (unreachable goal)");
            results.append(.failure("unreachable goal"))
        }
        else {
            let (actions, initial, complements) = transformed(g), graph = GraphPlan.run(actions, initial, g.goals, params.limit)
            graphLines.append("complementary facts: \(complements)");
            graphLines += graph.records
            if graph.search.status == "solved" {
                graphLines.append("result: solved levels=\(graph.layers.count) length=\(graph.search.plan.count) cost=\(cost(g, graph.search.plan)) searched=\(graph.search.expanded) memo_hits=\(graph.hits) tried=\(graph.search.generated)")
                for (k, layer) in graph.layers.enumerated() {
                    graphLines.append(list("layer \(k + 1):", layer.map {
                        g.actions[$0].text
                    }))
                }
            } else {
                graphLines.append("result: FAIL (\(graph.search.status)) searched=\(graph.search.expanded) memo_hits=\(graph.hits) tried=\(graph.search.generated)")
            }
            results.append(graph.search)
        }
        graphLines.append("")
        let best = results.filter {
            $0.status == "solved"
        }.map {
            cost(g, $0.plan)
        }.min()
        bests.append(best)
        let proof = params.runs.indices.first {
            i in let pair = params.runs[i];
            return (pair.0 == "ucs" && pair.1 == "none" || pair.0 == "astar" && pair.1 == "hmax") && results[i].status == "solved"
        }
        let optimal = proof.map {
            String(cost(g, results[$0].plan))
        } ?? (results.contains {
            ["unreachable goal", "dead end", "exhausted", "unreachable"].contains($0.status)
        } ? "none" : "unknown")
        problemSummary.append("\(problem.name): solved=\(results.filter { $0.status == "solved" }.count)/\(results.count) best=\(best.map(String.init) ?? "-") optimal=\(optimal)")
        var seen: [([Int], String)] = []
        for (i, result) in results.enumerated() {
            plans += ["-- \(tags[i]) --", resultLine(result, unreachable)]
            tagStats[i][2] += result.expanded;
            tagStats[i][3] += result.generated
            let (algorithm, heuristic) = i < params.runs.count ? params.runs[i] : ("graphplan", "none")
            let length: String, costText: String
            if result.status == "solved" {
                tagStats[i][0] += 1
                if cost(g, result.plan) == best {
                    tagStats[i][1] += 1
                }
                let (block, checked, valid) = planBlock(domain, problem, g, result.plan, tags[i], landmarks, &seen)
                plans += block;
                validation += checked;
                analyzed += 1;
                validPlans += valid ? 1 : 0
                length = String(result.plan.count);
                costText = String(cost(g, result.plan))
            } else {
                length = "-";
                costText = "-"
            }
            comparison.append("\(problem.name),\(algorithm),\(heuristic),\(length),\(costText),\(result.expanded),\(result.generated)")
        }
        if let proof {
            plans += profile(g, results[proof].plan, tags[proof])
        }
        plans.append("");
        validation.append("")
    }
    plans.append("== summary ==");
    plans += problemSummary
    for (i, tag) in tags.enumerated() {
        let s = tagStats[i];
        plans.append("\(tag): solved=\(s[0]) best=\(s[1]) expanded=\(s[2]) generated=\(s[3])")
    }
    validation.append("== candidates ==")
    let candidates = readCandidates()
    var validCandidates = 0
    for (k, candidate) in candidates.enumerated() {
        let index = problems.firstIndex {
            $0.name == candidate.problem
        }!, problem = problems[index], g = grounds[index], checked = validateSteps(domain, problem, candidate.steps)
        if checked.status == "valid" {
            validCandidates += 1
            validation.append("candidate \(k + 1) \(problem.name) \(candidate.label): \(checked.verdict)")
            let mapped = mapSteps(g, candidate.steps), improved = improve(g, mapped)
            validation.append("  improved: length=\(improved.count) cost=\(cost(g, improved)) removed=\(mapped.count - improved.count) best known=\(bests[index].map(String.init) ?? "-")")
        } else {
            validation.append("candidate \(k + 1) \(problem.name) \(candidate.label): \(checked.status)")
            validation += checked.messages.map {
                "  " + $0
            }
            if !g.unreachable.isEmpty {
                validation.append("  repair: FAIL (unreachable goal)");
                continue
            }
            var mapped = mapSteps(g, Array(candidate.steps.prefix(checked.correct))), state = g.initial
            for action in mapped {
                state = Search.apply(g.actions[action], state)
            }
            let repair = Search.run(g, state, params.repair.0, params.repair.1, params.budget, params.weight)
            if repair.status != "solved" {
                validation.append("  repair: FAIL (\(repair.status))")
            }
            else {
                mapped += repair.plan
                let repaired = validateSteps(domain, problem, steps(g, mapped))
                validation.append("  repair: kept=\(checked.correct) added=\(repair.plan.count) \(repaired.verdict)")
                for (j, action) in mapped.enumerated() {
                    validation.append("    \(j + 1) \(g.actions[action].text)")
                }
            }
        }
    }
    validation += ["", "== summary ==", "plans: \(analyzed) valid: \(validPlans)", "candidates: \(candidates.count) valid: \(validCandidates)"]
    write("grounding.txt", groundingLines);
    write("plans.txt", plans);
    write("graphplan.txt", graphLines);
    write("validation.txt", validation);
    write("comparison.csv", comparison)
}
runProgram()
