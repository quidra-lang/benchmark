import Foundation
struct Params {
    var horizon = 0
    var highBudget = 0
    var lowBudget = 0
    var window = 0
    var step = 0
    var orders: [[Int]]
    var runs: [(String, String)] = []
    var animate = ""
    var frames = 0
    var delays: [(Int, Int, Int)] = []
    init(_ agents: Int) {
        orders = [Array(0..<agents)]
        let text = try! String(contentsOfFile: "input/params.txt", encoding: .ascii)
        for line in text.split(separator: "\n") {
            let a = line.split(separator: " ").map(String.init)
            switch a[0] {
                case "HORIZON": horizon = Int(a[1])!
                case "HL_BUDGET": highBudget = Int(a[1])!
                case "LL_BUDGET": lowBudget = Int(a[1])!
                case "WINDOW": window = Int(a[1])!;
                step = Int(a[2])!
                case "ORDER": orders.append(a.dropFirst().map {
                    Int($0)!
                })
                case "RUN": runs.append((a[1], a[2]))
                case "ANIMATE": animate = a[1];
                frames = Int(a[2])!
                default: delays.append((Int(a[1])!, Int(a[2])!, Int(a[3])!))
            }
        }
    }
}
func mdd(_ grid: Grid, _ agent: Int, _ cost: Int, _ constraints: Constraints) -> [Set<Cell>] {
    var layers = Array(repeating: Set<Cell>(), count: cost + 1)
    layers[0].insert(grid.agents[agent].start)
    if cost > 0 {
        for time in 1...cost {
            for source in layers[time - 1] {
                for destination in grid.destinations(source) {
                    if let d = grid.distances[agent][destination], time + d <= cost,
                    constraints.allowed(source, destination, time) {
                        layers[time].insert(destination)
                    }
                }
            }
        }
    }
    layers[cost] = layers[cost].filter {
        $0 == grid.agents[agent].goal
    }
    for time in (0..<cost).reversed() {
        let next = layers[time + 1]
        layers[time] = layers[time].filter {
            source in
            grid.destinations(source).contains {
                next.contains($0) && constraints.allowed(source, $0, time + 1)
            }
        }
    }
    return layers
}
func classify(_ conflict: Conflict, _ mdds: [[Set<Cell>]]) -> Int {
    func fixed(_ agent: Int) -> Bool {
        func width(_ time: Int) -> Int {
            time < mdds[agent].count ? mdds[agent][time].count : 1
        }
        return width(conflict.time) == 1 && (conflict.vertex || width(conflict.time - 1) == 1)
    }
    return 2 - (fixed(conflict.a) ? 1 : 0) - (fixed(conflict.b) ? 1 : 0)
}
func classText(_ index: Int) -> String {
    ["cardinal", "semi_cardinal", "non_cardinal"][index]
}
final class Run {
    let name: String
    let solver: String
    let function: String
    let counts: SearchCounts
    var paths: [Path]?
    var reason = ""
    var high = 0
    var generated: Int?
    var pruned = 0
    var open = 0
    var classes = [0, 0, 0]
    var notes: [String] = []
    var trace: [String] = []
    init(_ solver: String, _ function: String, _ params: Params) {
        self.solver = solver
        self.function = function
        name = solver + "-" + function
        counts = SearchCounts(params.lowBudget)
        generated = solver == "CBS" || solver == "ICBS" ? 0 : nil
    }
}
func pp(_ grid: Grid, _ params: Params, _ run: Run) {
    for (k, order) in params.orders.enumerated() {
        run.high += 1
        let result = Prioritized.plan(grid, order: order, number: k + 1, horizon: params.horizon, counts: run.counts)
        run.trace += result.trace
        if result.aborted {
            run.reason = "ll_budget";
            break
        }
        let names = order.map(Report.name).joined()
        let resultText = result.failed.map {
            "failed \(Report.name($0))"
        }
        ?? "ok"
        run.notes.append("order \(k + 1) \(names) planned \(result.planned) expansions \(result.expansions) \(resultText)")
        if let paths = result.paths {
            run.paths = paths
            run.trace.append("end OK order \(k + 1)")
            return
        }
    }
    if run.reason.isEmpty {
        run.reason = "orders"
    }
    run.trace.append("end FAIL \(run.reason)")
}
func tree(_ grid: Grid, _ params: Params, _ run: Run) throws -> Node? {
    let n = grid.agents.count
    let constraints = Array(repeating: Constraints(), count: n)
    var paths: [Path] = []
    for i in 0..<n {
        let path = try LowLevel.search(grid, agent: i, start: grid.agents[i].start, time: 0,
        maximum: params.horizon, window: false, constraints: constraints[i], counts: run.counts)
        paths.append(path!)
    }
    var open = [Node(id: 0, parent: nil, depth: 0, constraints: constraints, paths: paths, soc: run.function == "SOC")]
    run.generated = 1
    while !open.isEmpty {
        let index = open.indices.min {
            Node.before(open[$0], open[$1])
        }
        !
        let node = open.remove(at: index)
        run.open = open.count
        if node.conflicts.isEmpty {
            return node
        }
        if run.high == params.highBudget {
            run.reason = "hl_budget";
            return nil
        }
        run.high += 1
        var category = 0, conflictIndex = 0
        if run.solver == "ICBS" {
            let diagrams = (0..<n).map {
                mdd(grid, $0, node.paths[$0].count - 1, node.constraints[$0])
            }
            category = 3
            for (k, conflict) in node.conflicts.enumerated() {
                let c = classify(conflict, diagrams)
                if c < category {
                    category = c;
                    conflictIndex = k
                }
            }
            run.classes[category] += 1
        }
        let conflict = node.conflicts[conflictIndex]
        var children: [String] = []
        for agent in [conflict.a, conflict.b] {
            var restrictions = node.constraints
            conflict.constrain(agent, &restrictions[agent])
            let path: Path?
            do {
                path = try LowLevel.search(grid, agent: agent, start: grid.agents[agent].start, time: 0,
                maximum: params.horizon, window: false, constraints: restrictions[agent], counts: run.counts)
            } catch {
                run.open = open.count
                throw error
            }
            if let path {
                let id = run.generated!
                run.generated = id + 1
                var nextPaths = node.paths
                nextPaths[agent] = path
                open.append(Node(id: id, parent: node.id, depth: node.depth + 1,
                constraints: restrictions, paths: nextPaths, soc: run.function == "SOC"))
                children.append(String(id))
            } else {
                run.pruned += 1
                children.append("-")
            }
        }
        run.open = open.count
        let parent = node.parent.map(String.init) ?? "-"
        let classification = run.solver == "ICBS" ? " class \(classText(category))" : ""
        run.trace.append("expand \(run.high) node \(node.id) parent \(parent) depth \(node.depth) cost \(node.cost) conflicts \(node.conflicts.count) split \(Report.conflict(conflict))\(classification) children \(children[0]) \(children[1])")
    }
    run.reason = "exhausted"
    run.open = 0
    return nil
}
struct ConstraintRow: Comparable {
    let agent: Int, time: Int, kind: Int, source: Cell, destination: Cell
    static func < (a: Self, b: Self) -> Bool {
        if a.agent != b.agent {
            return a.agent < b.agent
        }
        if a.time != b.time {
            return a.time < b.time
        }
        if a.kind != b.kind {
            return a.kind < b.kind
        }
        if a.source != b.source {
            return a.source < b.source
        }
        return a.destination < b.destination
    }
}
func cbsRun(_ grid: Grid, _ params: Params, _ run: Run) {
    let answer: Node?
    do {
        answer = try tree(grid, params, run)
    }
    catch {
        run.reason = "ll_budget";
        answer = nil
    }
    run.notes.append("search expanded \(run.high) generated \(run.generated!) pruned \(run.pruned) open \(run.open)")
    if run.solver == "ICBS" {
        run.notes.append("classes cardinal \(run.classes[0]) semi_cardinal \(run.classes[1]) non_cardinal \(run.classes[2])")
    }
    if let node = answer {
        run.notes.append("solution node \(node.id) depth \(node.depth)")
        var rows: [ConstraintRow] = []
        for (i, constraints) in node.constraints.enumerated() {
            rows += constraints.states.map {
                ConstraintRow(agent: i, time: $0.time, kind: 0, source: $0.cell, destination: $0.cell)
            }
            rows += constraints.moves.map {
                ConstraintRow(agent: i, time: $0.time, kind: 1, source: $0.source, destination: $0.destination)
            }
        }
        for row in rows.sorted() {
            let description = row.kind == 0 ? "vertex \(Report.cell(row.destination))" : "edge \(Report.cell(row.source)) \(Report.cell(row.destination))"
            run.notes.append("constraint \(Report.name(row.agent)) \(description) t \(row.time)")
        }
        run.trace.append("end OK node \(node.id) cost \(node.cost)")
        run.paths = node.paths
    } else {
        run.trace.append("end FAIL \(run.reason)")
    }
}
func whcaSearch(_ grid: Grid, _ params: Params, _ run: Run) throws -> [Path]? {
    let n = grid.agents.count
    var positions = grid.agents.map(\.start)
    var executed = positions.map {
        [$0]
    }
    var time = 0
    while true {
        if (0..<n).allSatisfy({
            positions[$0] == grid.agents[$0].goal
        }) {
            for i in 0..<n {
                while executed[i].count > 1 && executed[i][executed[i].count - 2] == grid.agents[i].goal {
                    executed[i].removeLast()
                }
            }
            return executed
        }
        if time >= params.horizon {
            run.reason = "timeout";
            return nil
        }
        run.high += 1
        let order = (0..<n).sorted {
            let a = positions[$0] == grid.agents[$0].goal, b = positions[$1] == grid.agents[$1].goal
            return a == b ? $0 < $1 : !a
        }
        var constraints = Constraints()
        var windows = Array(repeating: Path(), count: n)
        for i in order {
            let before = run.counts.expansions
            let path = try LowLevel.search(grid, agent: i, start: positions[i], time: time,
            maximum: time + params.window, window: true, constraints: constraints, counts: run.counts)
            if var path {
                path += Array(repeating: path.last!, count: params.window + 1 - path.count)
                constraints.reserve(path, start: time, permanent: false)
                run.trace.append("round \(run.high) time \(time) agent \(Report.name(i)) moves \(Report.actions(path)) expansions \(run.counts.expansions - before)")
                windows[i] = path
            } else {
                run.trace.append("round \(run.high) time \(time) agent \(Report.name(i)) blocked expansions \(run.counts.expansions - before)")
                run.reason = "blocked"
                return nil
            }
        }
        for i in 0..<n {
            executed[i] += windows[i][1...params.step]
            positions[i] = windows[i][params.step]
        }
        time += params.step
    }
}
func whca(_ grid: Grid, _ params: Params, _ run: Run) {
    do {
        run.paths = try whcaSearch(grid, params, run)
    }
    catch {
        run.reason = "ll_budget"
    }
    run.notes.append("window \(params.window) step \(params.step) rounds \(run.high)")
    run.trace.append(run.paths == nil ? "end FAIL \(run.reason)" : "end OK rounds \(run.high)")
}
func validate(_ grid: Grid, _ name: String, _ paths: [Path], _ classes: [Int]? = nil) -> [String] {
    let conflicts = CBS.conflicts(paths)
    let start = paths.indices.filter {
        paths[$0][0] != grid.agents[$0].start
    }.count
    let goal = paths.indices.filter {
        paths[$0].last! != grid.agents[$0].goal
    }.count
    let moves = paths.reduce(0) {
        total, path in
        total + (1..<path.count).filter {
            !grid.destinations(path[$0 - 1]).contains(path[$0])
        }.count
    }
    let vertex = conflicts.filter(\.vertex).count
    let edge = conflicts.count - vertex
    let maximum = paths.map {
        $0.count - 1
    }.max() ?? 0
    var follows = 0
    if maximum > 0 {
        for time in 1...maximum {
            for a in paths.indices {
                for b in paths.indices where a != b {
                    if position(paths[a], time) != position(paths[a], time - 1),
                    position(paths[a], time) == position(paths[b], time - 1),
                    position(paths[b], time) != position(paths[a], time - 1) {
                        follows += 1
                    }
                }
            }
        }
    }
    let verdict = start + goal + moves + vertex + edge == 0 ? "VALID" : "INVALID"
    var lines = ["plan \(name) verdict \(verdict) start \(start) goal \(goal) moves \(moves) vertex \(vertex) edge \(edge) follows \(follows)"]
    for (k, conflict) in conflicts.enumerated() {
        lines.append("  " + Report.conflict(conflict) + (classes.map {
            " " + classText($0[k])
        }
        ?? ""))
    }
    return lines
}
struct Execution {
    var time = 0
    var deadlock = false
    var hold = 0
    var finish: [Int]
}
func execution(_ paths: [Path], _ params: Params) -> Execution {
    let steps: [[(Int, Cell)]] = paths.map {
        path in
        path.enumerated().filter {
            $0.offset == 0 || $0.element != path[$0.offset - 1]
        }.map {
            ($0.offset, $0.element)
        }
    }
    let n = paths.count
    var progress = Array(repeating: 0, count: n)
    var result = Execution(finish: Array(repeating: 0, count: n))
    while (0..<n).contains(where: {
        progress[$0] + 1 < steps[$0].count
    }) {
        var advancing: [Int] = []
        var stopped = false
        for i in 0..<n {
            if progress[i] + 1 == steps[i].count {
                continue
            }
            if params.delays.contains(where: {
                $0.0 == i && $0.1 <= result.time && result.time < $0.1 + $0.2
            }) {
                stopped = true
                continue
            }
            let (time, cell) = steps[i][progress[i] + 1]
            let ready = (0..<n).filter {
                $0 != i
            }.allSatisfy {
                j in
                steps[j].enumerated().allSatisfy {
                    l, step in step.1 != cell || step.0 >= time || progress[j] > l
                }
            }
            if ready {
                advancing.append(i)
            } else {
                result.hold += 1
            }
        }
        if advancing.isEmpty && !stopped {
            result.deadlock = true;
            return result
        }
        for i in advancing {
            progress[i] += 1;
            result.finish[i] = result.time + 1
        }
        result.time += 1
    }
    return result
}
struct Statistics {
    let soc: Int, makespan: Int
    var extras: [Int] = [], waits: [Int] = [], turns: [Int] = []
    var traffic: [Cell: Int] = [:], waiting: [Cell: Int] = [:]
    let execution: Execution
}
func statistics(_ grid: Grid, _ paths: [Path], _ params: Params) -> Statistics {
    var result = Statistics(soc: paths.reduce(0) {
        $0 + $1.count - 1
    },
    makespan: paths.map {
        $0.count - 1
    }.max()!, execution: execution(paths, params))
    for (i, path) in paths.enumerated() {
        result.extras.append(path.count - 1 - grid.distances[i][grid.agents[i].start]!)
        let actions = Array(Report.actions(path))
        let moves = actions.filter {
            $0 != "."
        }
        result.turns.append((1..<max(1, moves.count)).filter {
            moves[$0 - 1] != moves[$0]
        }.count)
        result.waits.append(actions.filter {
            $0 == "."
        }.count)
        for cell in Set(path) {
            result.traffic[cell, default: 0] += 1
        }
        for time in 1..<path.count where path[time - 1] == path[time] {
            result.waiting[path[time], default: 0] += 1
        }
    }
    return result
}
func overview(_ grid: Grid, _ independent: [Path], _ mdds: [[Set<Cell>]], _ classes: [Int]) -> [String] {
    let cells = grid.cells(), n = grid.agents.count
    var degree = [0, 0, 0, 0]
    for cell in cells {
        degree[min(grid.destinations(cell).count - 1, 3)] += 1
    }
    var unseen = Set(cells), components = 0
    while let cell = unseen.min() {
        components += 1
        unseen.subtract(grid.distance(cell).keys)
    }
    var lines = ["instance width \(grid.width) height \(grid.height) free \(cells.count) agents \(n)",
    "map isolated \(degree[0]) dead_ends \(degree[1]) corridors \(degree[2]) junctions \(degree[3]) components \(components)"]
    let distances = grid.agents.enumerated().map {
        grid.distances[$0.offset][$0.element.start]!
    }
    for i in 0..<n {
        lines.append("agent \(Report.name(i)) start \(Report.cell(grid.agents[i].start)) goal \(Report.cell(grid.agents[i].goal)) distance \(distances[i]) mdd \(mdds[i].reduce(0) { $0 + $1.count }) width \(mdds[i].map(\.count).max()!)")
    }
    lines.append("lower_bound soc \(distances.reduce(0, +)) makespan \(distances.max()!)")
    let conflicts = CBS.conflicts(independent)
    let vertex = conflicts.filter(\.vertex).count
    lines.append("independent conflicts \(conflicts.count) vertex \(vertex) edge \(conflicts.count - vertex) cardinal \(classes.filter { $0 == 0 }.count) semi_cardinal \(classes.filter { $0 == 1 }.count) non_cardinal \(classes.filter { $0 == 2 }.count)")
    var adjacent = Array(repeating: Set<Int>(), count: n)
    for conflict in conflicts {
        adjacent[conflict.a].insert(conflict.b);
        adjacent[conflict.b].insert(conflict.a)
    }
    var visited: Set<Int> = [], groups: [String] = []
    for i in 0..<n where !visited.contains(i) {
        var stack = [i], group: Set<Int> = []
        while let j = stack.popLast() {
            if visited.insert(j).inserted {
                group.insert(j);
                stack += adjacent[j]
            }
        }
        if group.count > 1 {
            groups.append(group.sorted().map(Report.name).joined())
        }
    }
    lines.append("groups " + (groups.isEmpty ? "-" : groups.joined(separator: " ")))
    return lines
}
func pictures(_ grid: Grid, _ params: Params, _ run: Run) -> [String] {
    guard let paths = run.paths else {
        return ["run \(run.name) FAIL"]
    }
    var lines = ["run \(run.name) frames \(params.frames)"]
    for time in 0..<params.frames {
        var picture = grid.rows
        for (i, agent) in grid.agents.enumerated() {
            picture[agent.goal.y][agent.goal.x] = Character(Report.name(i).lowercased())
        }
        var done = 0, moving = 0, waiting = 0
        for (i, path) in paths.enumerated() {
            let cell = position(path, time)
            picture[cell.y][cell.x] = Character(Report.name(i))
            if time >= path.count - 1 {
                done += 1
            }
            else if time > 0 && position(path, time) != position(path, time - 1) {
                moving += 1
            }
            else {
                waiting += 1
            }
        }
        lines += ["", "frame \(time) done \(done) moving \(moving) waiting \(waiting)"] + picture.map(String.init)
    }
    let stats = statistics(grid, paths, params)
    for (label, counts) in [("traffic", stats.traffic), ("waits", stats.waiting)] {
        var picture = grid.rows
        for cell in grid.cells() {
            let count = counts[cell] ?? 0
            picture[cell.y][cell.x] = count == 0 ? "." : count < 10 ? Character(String(count)) : "+"
        }
        lines += ["", label] + picture.map(String.init)
    }
    return lines
}
func runProgram() {
    let grid = Grid(), params = Params(grid.agents.count)
    var independent: [Path] = [], diagrams: [[Set<Cell>]] = []
    let counts = SearchCounts(Int.max)
    for i in grid.agents.indices {
        independent.append(try! LowLevel.search(grid, agent: i, start: grid.agents[i].start, time: 0,
        maximum: params.horizon, window: false, constraints: Constraints(), counts: counts)!)
        diagrams.append(mdd(grid, i, grid.distances[i][grid.agents[i].start]!, Constraints()))
    }
    let conflicts = CBS.conflicts(independent), classes = conflicts.map {
        classify($0, diagrams)
    }
    var solutions = overview(grid, independent, diagrams, classes)
    var validation = validate(grid, "INDEPENDENT", independent, classes)
    var csv = ["run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions"]
    var trace: [String] = [], runs: [Run] = [], ranking: [(soc: Int, makespan: Int, index: Int, name: String)] = []
    let distances = grid.agents.enumerated().map {
        grid.distances[$0.offset][$0.element.start]!
    }
    let lowerSOC = distances.reduce(0, +), lowerMax = distances.max()!
    for (solver, function) in params.runs {
        let run = Run(solver, function, params)
        switch solver {
            case "PP": pp(grid, params, run)
            case "CBS", "ICBS": cbsRun(grid, params, run)
            default: whca(grid, params, run)
        }
        solutions.append("")
        var fields = [run.name, solver, function]
        if let paths = run.paths {
            let stats = statistics(grid, paths, params)
            let cost = function == "SOC" ? stats.soc : stats.makespan
            let lower = function == "SOC" ? lowerSOC : lowerMax
            solutions.append("run \(run.name) solver \(solver) cost_function \(function) result OK cost \(cost) soc \(stats.soc) makespan \(stats.makespan) ratio \(Report.ratio(cost, lower))")
            solutions += run.notes
            for (i, path) in paths.enumerated() {
                let goal = grid.agents[i].goal, arrive = path.firstIndex(of: goal)!
                let leave = (1..<path.count).filter {
                    path[$0 - 1] == goal && path[$0] != goal
                }.count
                solutions.append("agent \(Report.name(i)) cost \(path.count - 1) extra \(stats.extras[i]) waits \(stats.waits[i]) turns \(stats.turns[i]) arrive \(arrive) leave \(leave) moves \(Report.actions(path))")
            }
            solutions.append("arrivals " + (0...stats.makespan).map {
                t in String(paths.filter {
                    $0.count - 1 <= t
                }.count)
            }.joined(separator: " "))
            let hotspots = stats.traffic.sorted {
                if $0.value != $1.value {
                    return $0.value > $1.value
                }
                return $0.key.y == $1.key.y ? $0.key.x < $1.key.x : $0.key.y < $1.key.y
            }
            solutions.append("hotspots " + hotspots.prefix(5).map {
                "\(Report.cell($0.key)):\($0.value)"
            }.joined(separator: " "))
            let execution = stats.execution
            let executionSOC = execution.finish.reduce(0, +), executionMax = execution.finish.max()!
            solutions.append(execution.deadlock ? "execution deadlock time \(execution.time)" :
            "execution soc \(executionSOC) makespan \(executionMax) blocked \(execution.hold) finish \(execution.finish.map(String.init).joined(separator: " "))")
            fields += ["OK", "-", String(cost), String(stats.soc), String(stats.makespan), String(stats.extras.reduce(0, +)),
            String(stats.extras.max()!), String(stats.waits.reduce(0, +)), String(stats.turns.reduce(0, +)),
            execution.deadlock ? "-" : String(executionSOC), execution.deadlock ? "-" : String(executionMax)]
            validation += validate(grid, run.name, paths)
            ranking.append((stats.soc, stats.makespan, runs.count, run.name))
        } else {
            solutions.append("run \(run.name) solver \(solver) cost_function \(function) result FAIL reason \(run.reason)")
            solutions += run.notes
            validation.append("plan \(run.name) verdict NONE")
            fields += ["FAIL", run.reason] + Array(repeating: "-", count: 9)
        }
        fields += [String(run.high), run.generated.map(String.init) ?? "-", String(run.counts.searches), String(run.counts.expansions)]
        csv.append(Report.csv(fields))
        if !trace.isEmpty {
            trace.append("")
        }
        trace += ["run \(run.name)"] + run.trace
        runs.append(run)
    }
    solutions += ["", "summary ok \(ranking.count) failed \(runs.count - ranking.count)"]
    if !ranking.isEmpty {
        let soc = ranking.map(\.soc).min()!, makespan = ranking.map(\.makespan).min()!
        solutions.append("best_soc \(soc) " + ranking.filter {
            $0.soc == soc
        }.map(\.name).joined(separator: " "))
        solutions.append("best_makespan \(makespan) " + ranking.filter {
            $0.makespan == makespan
        }.map(\.name).joined(separator: " "))
        ranking.sort {
            ($0.soc, $0.makespan, $0.index) < ($1.soc, $1.makespan, $1.index)
        }
        solutions.append("ranking " + ranking.map(\.name).joined(separator: " "))
    }
    Report.write("solutions.txt", solutions)
    Report.write("stats.csv", csv)
    Report.write("validation.txt", validation)
    Report.write("trace.txt", trace)
    Report.write("frames.txt", pictures(grid, params, runs.first {
        $0.name == params.animate
    }
    !))
}
runProgram()
