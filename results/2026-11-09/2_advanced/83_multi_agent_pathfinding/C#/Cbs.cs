using System;
using System.Collections.Generic;
using System.Linq;
public static class Cbs {
    public record Conflict(string kind, int time, int a, int b, GridMap.Cell u, GridMap.Cell v);
    public record Constraint(int agent, int time, string kind, GridMap.Cell u, GridMap.Cell v);
    public static GridMap.Cell Position(List<GridMap.Cell> path,
                                        int time) => path[Math.Min(time, path.Count - 1)];
    public static List<Conflict> Conflicts(List<List<GridMap.Cell>> paths) {
        List<Conflict> result = new();
        int horizon = paths.Max(path => path.Count - 1);
        for (int time = 1; time <= horizon; time++)
            for (int a = 0; a < paths.Count; a++)
                for (int b = a + 1; b < paths.Count; b++) {
                    GridMap.Cell currentA = Position(paths[a], time),
                                 currentB = Position(paths[b], time);
                    if (currentA == currentB)
                        result.Add(new("vertex", time, a, b, currentA, currentA));
                    else if (currentA == Position(paths[b], time - 1) &&
                             currentB == Position(paths[a], time - 1))
                        result.Add(new("edge", time, a, b, Position(paths[a], time - 1), currentA));
                }
        return result;
    }
    public static List<Constraint> Split(Conflict conflict) => new() {
        new(conflict.a, conflict.time, conflict.kind, conflict.u, conflict.v),
        new(conflict.b, conflict.time, conflict.kind, conflict.v, conflict.u)
    };
    public static int Cost(List<List<GridMap.Cell>> paths,
                           string function) => function == "SOC"
                                                   ? paths.Sum(path => path.Count - 1)
                                                   : paths.Max(path => path.Count - 1);
    public sealed class Node {
        public List<List<GridMap.Cell>> paths;
        public List<LowLevel.Prohibitions> constraints;
        public List<Conflict> conflicts;
        public int number, depth, cost;
        public int? parent;
        public Node(List<List<GridMap.Cell>> paths, List<LowLevel.Prohibitions> constraints,
                    int number, int depth, int? parent, string function) {
            this.paths = paths;
            this.constraints = constraints;
            this.number = number;
            this.depth = depth;
            this.parent = parent;
            conflicts = Conflicts(paths);
            cost = Cost(paths, function);
        }
    }
    public static readonly IComparer<Node> Order = Comparer<Node>.Create((a, b) => {
        int c = a.cost.CompareTo(b.cost);
        if (c == 0)
            c = a.conflicts.Count.CompareTo(b.conflicts.Count);
        return c != 0 ? c : a.number.CompareTo(b.number);
    });
    public static List<Constraint> OrderedConstraints(Node node) {
        List<Constraint> result = new();
        for (int i = 0; i < node.constraints.Count; i++) {
            foreach (LowLevel.State state in node.constraints[i].states)
                result.Add(new(i, state.time, "vertex", state.cell, state.cell));
            foreach (LowLevel.Move move in node.constraints[i].moves)
                result.Add(new(i, move.time, "edge", move.source, move.destination));
        }
        return result.OrderBy(c => c.agent)
            .ThenBy(c => c.time)
            .ThenBy(c => c.kind == "vertex" ? 0 : 1)
            .ThenBy(c => c.u.x)
            .ThenBy(c => c.u.y)
            .ThenBy(c => c.v.x)
            .ThenBy(c => c.v.y)
            .ToList();
    }
}
