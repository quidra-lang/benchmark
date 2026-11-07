import java.util.*;
final class Prioritized {
    record Attempt(int agent, LowLevel.Search search) {}
    record Result(List<List<GridMap.Cell>> paths, List<Attempt> attempts, Integer failed,
                  boolean aborted) {}
    static Result tryOrder(GridMap grid, List<GridMap.Agent> agents,
                           List<Map<GridMap.Cell, Integer>> distances, int horizon,
                           List<Integer> order, LowLevel.Budget budget) {
        LowLevel.Prohibitions prohibitions = new LowLevel.Prohibitions();
        List<List<GridMap.Cell>> paths = new ArrayList<>(Collections.nCopies(agents.size(), null));
        List<Attempt> attempts = new ArrayList<>();
        for (int id : order) {
            LowLevel.Search search;
            try {
                search =
                    LowLevel.search(grid, agents.get(id), distances.get(id), agents.get(id).start(),
                                    0, prohibitions, horizon, budget, false);
            } catch (LowLevel.BudgetExceeded exception) {
                return new Result(null, attempts, null, true);
            }
            attempts.add(new Attempt(id, search));
            if (search.path() == null)
                return new Result(null, attempts, id, false);
            paths.set(id, search.path());
            LowLevel.reserve(prohibitions, search.path(), 0, true);
        }
        return new Result(paths, attempts, null, false);
    }
}
