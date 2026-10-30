using System;
using System.Collections.Generic;
using System.Linq;
public static class LowLevel {
    public record State(GridMap.Cell cell, int time);
    public record Move(GridMap.Cell source, GridMap.Cell destination, int time);
    public sealed class BudgetExceeded : Exception {}
    public sealed class Budget {
        public int? limit;
        public int searches, expansions;
        public Budget(int? limit) { this.limit = limit; }
        public void Expand() {
            expansions++;
            if (limit != null && expansions > limit.Value)
                throw new BudgetExceeded();
        }
    }
    public sealed class Prohibitions {
        public HashSet<State> states = new(), permanent = new();
        public HashSet<Move> moves = new();
        public Prohibitions Copy() => new() { states = new(states), permanent = new(permanent),
                                              moves = new(moves) };
        public bool StateAllowed(GridMap.Cell cell,
                                 int time) => !states.Contains(new(cell, time)) &&
                                              !permanent.Any(state => state.cell == cell &&
                                                                      state.time <= time);
        public bool ActionAllowed(GridMap.Cell source, GridMap.Cell destination,
                                  int time) => StateAllowed(destination, time) &&
                                               (source == destination ||
                                                !moves.Contains(new(source, destination, time)));
        public int ArrivalAllowed(GridMap.Cell goal) => states.Where(state => state.cell == goal)
                                                            .Select(state => state.time + 1)
                                                            .DefaultIfEmpty(0)
                                                            .Max();
    }
    public static void Reserve(Prohibitions prohibitions, List<GridMap.Cell> path, int startTime,
                               bool permanent) {
        for (int k = 0; k < path.Count; k++) {
            GridMap.Cell cell = path[k];
            int time = startTime + k;
            prohibitions.states.Add(new(cell, time));
            if (k > 0 && cell != path[k - 1])
                prohibitions.moves.Add(new(cell, path[k - 1], time));
        }
        if (permanent)
            prohibitions.permanent.Add(new(path[^1], startTime + path.Count - 1));
    }
    public record Search(List<GridMap.Cell> path, int expansions);
    public static Search FindPath(GridMap grid, GridMap.Agent agent,
                                  Dictionary<GridMap.Cell, int> distances, GridMap.Cell start,
                                  int t0, Prohibitions prohibitions, int tmax, Budget budget,
                                  bool window) {
        budget.searches++;
        int beginning = budget.expansions, arrival = prohibitions.ArrivalAllowed(agent.goal),
            insertion = 0;
        PriorityQueue<State, (int f, int negativeG, int insertion)> open = new();
        State startState = new(start, t0);
        Dictionary<State, State> parents = new() { { startState, null } };
        open.Enqueue(startState, (distances[start], 0, 0));
        while (open.Count > 0) {
            State state = open.Dequeue();
            budget.Expand();
            GridMap.Cell cell = state.cell;
            int time = state.time;
            if (cell == agent.goal && time >= arrival || window && time == tmax) {
                List<GridMap.Cell> path = new();
                for (State current = state; current != null; current = parents[current])
                    path.Add(current.cell);
                path.Reverse();
                return new(path, budget.expansions - beginning);
            }
            if (time == tmax)
                continue;
            foreach (GridMap.Cell destination in grid.Destinations(cell)) {
                State next = new(destination, time + 1);
                if (!distances.ContainsKey(destination) || parents.ContainsKey(next) ||
                    !prohibitions.ActionAllowed(cell, destination, time + 1))
                    continue;
                parents[next] = state;
                int g = time + 1 - t0;
                open.Enqueue(next, (g + distances[destination], -g, ++insertion));
            }
        }
        return new(null, budget.expansions - beginning);
    }
}
