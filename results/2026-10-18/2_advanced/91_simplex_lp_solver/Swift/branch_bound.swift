struct BBNode {
    let bounds: Bounds, depth: Int, parent: Int?, branch: String, value: F?
}
struct Outcome {
    let status: String, root: LPResult, solution: [F]?, objective: F?, nodes: Int, phase1: Int, phase2: Int, drives: Int, lines: [String]
    var pivots: Int {
        phase1 + phase2 + drives
    }
}
enum BranchBound {
    static func solve(_ model: Model, _ limit: Int, _ level: Int, _ log: inout [String]) -> Outcome {
        var stack = [BBNode(bounds: model.bounds, depth: 0, parent: nil, branch: "root", value: nil)], root: LPResult?, solution: [F]?, objective: F?
        var nodes = 0, incumbents = 0, pruned = 0, infeasible = 0, p1 = 0, p2 = 0, drives = 0, status = "INFEASIBLE"
        var lines = ["MODEL \(model.name) \(model.maximize ? "maximize" : "minimize") integers \(model.integer.filter { $0 }.count) node_limit \(limit)"]
        func better(_ a: F, _ b: F) -> Bool {
            model.maximize ? a > b : a < b
        }
        while !stack.isEmpty {
            if nodes == limit {
                status = "NODE_LIMIT";
                break
            }
            let node = stack.removeLast();
            nodes += 1
            let result = solveLP(model, node.bounds, nodes, level, &log)
            p1 += result.phase1;
            p2 += result.phase2;
            drives += result.drives
            if nodes == 1 {
                root = result
            }
            let action: String
            if result.status == "INFEASIBLE" {
                infeasible += 1;
                action = "infeasible"
            }
            else if result.status == "UNBOUNDED" {
                status = "UNBOUNDED";
                action = "unbounded"
            }
            else if let best = objective, !better(result.value, best) {
                pruned += 1;
                action = "pruned"
            }
            else if let j = model.names.indices.first(where: {
                model.integer[$0] && result.solution[$0].d != 1
            }) {
                let value = result.solution[j], lower = F(value.floor), upper = F(value.ceil)
                action = "branch \(model.names[j]) \(value)"
                var ceilBounds = node.bounds, floorBounds = node.bounds;
                ceilBounds[j].0 = upper;
                floorBounds[j].1 = lower
                stack.append(BBNode(bounds: ceilBounds, depth: node.depth + 1, parent: nodes, branch: "\(model.names[j])>=\(upper)", value: result.value))
                stack.append(BBNode(bounds: floorBounds, depth: node.depth + 1, parent: nodes, branch: "\(model.names[j])<=\(lower)", value: result.value))
            } else {
                incumbents += 1;
                objective = result.value;
                solution = result.solution;
                action = "incumbent"
            }
            lines.append("NODE \(nodes) depth \(node.depth) parent \(node.parent.map(String.init) ?? "-") branch \(node.branch) lp \(result.status == "OPTIMAL" ? result.value.description : result.status.lowercased()) pivots \(result.pivots) action \(action)")
            if status == "UNBOUNDED" {
                break
            }
        }
        if status != "NODE_LIMIT" && status != "UNBOUNDED" {
            status = objective != nil ? "OPTIMAL" : "INFEASIBLE"
        }
        var bound = objective
        if status == "NODE_LIMIT" {
            for node in stack.reversed() {
                let value = node.value!
                lines.append("OPEN parent \(node.parent!) branch \(node.branch) bound \(value)")
                if bound == nil || better(value, bound!) {
                    bound = value
                }
            }
        }
        lines.append("RESULT \(status) objective \(objective?.description ?? "-") nodes \(nodes) incumbents \(incumbents) pruned \(pruned) infeasible \(infeasible) open \(stack.count) bound \(bound?.description ?? "-")")
        return Outcome(status: status, root: root!, solution: solution, objective: objective, nodes: nodes, phase1: p1, phase2: p2, drives: drives, lines: lines)
    }
}
