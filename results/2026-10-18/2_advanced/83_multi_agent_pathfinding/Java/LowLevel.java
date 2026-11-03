import java.util.*;
final class LowLevel {
    record State(GridMap.Cell cell, int time) {}
    record Move(GridMap.Cell source, GridMap.Cell destination, int time) {}
    static final class BudgetExceeded extends RuntimeException {}
    static final class Budget {
        Integer limit;
        int searches, expansions;
        Budget(Integer limit) { this.limit = limit; }
        void expand() {
            expansions++;
            if (limit != null && expansions > limit)
                throw new BudgetExceeded();
        }
    }
    static final class Prohibitions {
        Set<State> states = new HashSet<>(), permanent = new HashSet<>();
        Set<Move> moves = new HashSet<>();
        Prohibitions copy() {
            Prohibitions p = new Prohibitions();
            p.states.addAll(states);
            p.permanent.addAll(permanent);
            p.moves.addAll(moves);
            return p;
        }
        boolean stateAllowed(GridMap.Cell cell, int time) {
            if (states.contains(new State(cell, time)))
                return false;
            for (State state : permanent)
                if (state.cell().equals(cell) && state.time() <= time)
                    return false;
            return true;
        }
        boolean actionAllowed(GridMap.Cell source, GridMap.Cell destination, int time) {
            return stateAllowed(destination, time) &&
                (source.equals(destination) ||
                 !moves.contains(new Move(source, destination, time)));
        }
        int arrivalAllowed(GridMap.Cell goal) {
            int arrival = 0;
            for (State state : states)
                if (state.cell().equals(goal))
                    arrival = Math.max(arrival, state.time() + 1);
            return arrival;
        }
    }
    static void reserve(Prohibitions prohibitions, List<GridMap.Cell> path, int startTime,
                        boolean permanent) {
        for (int k = 0; k < path.size(); k++) {
            GridMap.Cell cell = path.get(k);
            int time = startTime + k;
            prohibitions.states.add(new State(cell, time));
            if (k > 0 && !cell.equals(path.get(k - 1)))
                prohibitions.moves.add(new Move(cell, path.get(k - 1), time));
        }
        if (permanent)
            prohibitions.permanent.add(new State(path.getLast(), startTime + path.size() - 1));
    }
    record Entry(int f, int g, int insertion, State state) {}
    record Search(List<GridMap.Cell> path, int expansions) {}
    static Search search(GridMap grid, GridMap.Agent agent, Map<GridMap.Cell, Integer> distances,
                         GridMap.Cell start, int t0, Prohibitions prohibitions, int tmax,
                         Budget budget, boolean window) {
        budget.searches++;
        int beginning = budget.expansions, arrival = prohibitions.arrivalAllowed(agent.goal()),
            insertion = 0;
        PriorityQueue<Entry> open =
            new PriorityQueue<>(Comparator.comparingInt(Entry::f)
                                    .thenComparing(Comparator.comparingInt(Entry::g).reversed())
                                    .thenComparingInt(Entry::insertion));
        State startState = new State(start, t0);
        Map<State, State> parents = new HashMap<>();
        parents.put(startState, null);
        open.add(new Entry(distances.get(start), 0, 0, startState));
        while (!open.isEmpty()) {
            State state = open.remove().state();
            budget.expand();
            GridMap.Cell cell = state.cell();
            int time = state.time();
            if (cell.equals(agent.goal()) && time >= arrival || window && time == tmax) {
                List<GridMap.Cell> path = new ArrayList<>();
                for (State current = state; current != null; current = parents.get(current))
                    path.add(current.cell());
                Collections.reverse(path);
                return new Search(path, budget.expansions - beginning);
            }
            if (time == tmax)
                continue;
            for (GridMap.Cell destination : grid.destinations(cell)) {
                State next = new State(destination, time + 1);
                if (!distances.containsKey(destination) || parents.containsKey(next) ||
                    !prohibitions.actionAllowed(cell, destination, time + 1))
                    continue;
                parents.put(next, state);
                int g = time + 1 - t0;
                open.add(new Entry(g + distances.get(destination), g, ++insertion, next));
            }
        }
        return new Search(null, budget.expansions - beginning);
    }
}
