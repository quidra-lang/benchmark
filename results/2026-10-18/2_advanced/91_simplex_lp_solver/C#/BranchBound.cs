using System;
using System.Collections.Generic;
using System.Linq;
sealed record SearchNode(List<Bound> Bounds, int Depth, int? Parent, string Branch, F? ParentValue);
sealed record Outcome(string Status, LPResult Root, List<F>? Solution, F? Objective, int Nodes, int Phase1, int Phase2, int Drives, List<string> Lines) {
    public int Pivots => Phase1 + Phase2 + Drives;
}
static class BranchBound {
    public static Outcome Solve(Model model, int limit, int level, List<string> log) {
        List<SearchNode> stack = new() {
            new(model.Bounds, 0, null, "root", null)
        };
        List<string> lines = new() {
            $"MODEL {model.Name} {(model.Maximize ? "maximize" : "minimize")} integers {model.Integer.Count(v => v)} node_limit {limit}"
        };
        LPResult? root = null;
        List<F>? solution = null;
        F? objective = null;
        int nodes = 0, phase1 = 0, phase2 = 0, drives = 0, incumbents = 0, pruned = 0, infeasible = 0;
        string? status = null;
        while (stack.Count > 0) {
            if (nodes == limit) {
                status = "NODE_LIMIT";
                break;
            } SearchNode node = stack[^1];
            stack.RemoveAt(stack.Count - 1);
            nodes++;
            LPResult result = Program.SolveLP(model, node.Bounds, nodes, level, log);
            root ??= result;
            phase1 += result.Phase1;
            phase2 += result.Phase2;
            drives += result.Drives;
            string action;
            if (result.Status == "INFEASIBLE") {
                infeasible++;
                action = "infeasible";
            }
            else if (result.Status == "UNBOUNDED") {
                status = "UNBOUNDED";
                action = "unbounded";
            }
            else if (objective.HasValue && (model.Maximize ? result.Value <= objective.Value : result.Value >= objective.Value)) {
                pruned++;
                action = "pruned";
            }
            else {
                int? fractional = Enumerable.Range(0, model.Names.Count).Where(j => model.Integer[j] && result.Solution[j].D != 1).Select(j => (int?)j).FirstOrDefault();
                if (!fractional.HasValue) {
                    solution = new(result.Solution);
                    objective = result.Value;
                    incumbents++;
                    action = "incumbent";
                }
                else {
                    int j = fractional.Value;
                    F v = result.Solution[j], down = v.Floor(), up = v.Ceil();
                    List<Bound> high = new(node.Bounds), low = new(node.Bounds);
                    high[j] = high[j] with {
                        Lower = up
                    };
                    low[j] = low[j] with {
                        Upper = down
                    };
                    stack.Add(new(high, node.Depth + 1, nodes, $"{model.Names[j]}>={up}", result.Value));
                    stack.Add(new(low, node.Depth + 1, nodes, $"{model.Names[j]}<={down}", result.Value));
                    action = $"branch {model.Names[j]} {v}";
                }
            }
            lines.Add($"NODE {nodes} depth {node.Depth} parent {node.Parent?.ToString() ?? "-"} branch {node.Branch} lp {(result.Status == "OPTIMAL" ? result.Value.ToString() : result.Status.ToLowerInvariant())} pivots {result.Pivots} action {action}");
            if (status == "UNBOUNDED") break;
        }
        status ??= solution != null ? "OPTIMAL" : "INFEASIBLE";
        F? bound = objective;
        if (status == "NODE_LIMIT") {
            foreach (SearchNode node in stack.AsEnumerable().Reverse()) lines.Add($"OPEN parent {node.Parent} branch {node.Branch} bound {node.ParentValue}");
            List<F> values = stack.Select(node => node.ParentValue!.Value).ToList();
            if (objective.HasValue) values.Add(objective.Value);
            bound = model.Maximize ? values.Max() : values.Min();
        }
        lines.Add($"RESULT {status} objective {objective?.ToString() ?? "-"} nodes {nodes} incumbents {incumbents} pruned {pruned} infeasible {infeasible} open {stack.Count} bound {bound?.ToString() ?? "-"}");
        return new(status, root!, solution, objective, nodes, phase1, phase2, drives, lines);
    }
}
