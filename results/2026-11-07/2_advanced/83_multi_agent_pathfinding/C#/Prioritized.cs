using System;
using System.Collections.Generic;
using System.Linq;
public static class Prioritized {
    public record Attempt(int agent, LowLevel.Search search);
    public record Result(List<List<GridMap.Cell>> paths, List<Attempt> attempts, int? failed,
                         bool aborted);
    public static Result TryOrder(GridMap grid, List<GridMap.Agent> agents,
                                  List<Dictionary<GridMap.Cell, int>> distances, int horizon,
                                  List<int> order, LowLevel.Budget budget) {
        LowLevel.Prohibitions prohibitions = new();
        List<List<GridMap.Cell>> paths =
            Enumerable.Repeat<List<GridMap.Cell>>(null, agents.Count).ToList();
        List<Attempt> attempts = new();
        foreach (int id in order) {
            LowLevel.Search search;
            try {
                search = LowLevel.FindPath(grid, agents[id], distances[id], agents[id].start, 0,
                                           prohibitions, horizon, budget, false);
            } catch (LowLevel.BudgetExceeded) {
                return new(null, attempts, null, true);
            }
            attempts.Add(new(id, search));
            if (search.path == null)
                return new(null, attempts, id, false);
            paths[id] = search.path;
            LowLevel.Reserve(prohibitions, search.path, 0, true);
        }
        return new(paths, attempts, null, false);
    }
}
