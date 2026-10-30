import java.util.*;
final class Cbs {
    record Conflict(String kind, int time, int a, int b, GridMap.Cell u, GridMap.Cell v) {}
    record Constraint(int agent, int time, String kind, GridMap.Cell u, GridMap.Cell v) {}
    static GridMap.Cell position(List<GridMap.Cell> path, int time) {
        return path.get(Math.min(time, path.size() - 1));
    }
    static List<Conflict> conflicts(List<List<GridMap.Cell>> paths) {
        List<Conflict> result = new ArrayList<>();
        int horizon = paths.stream().mapToInt(path -> path.size() - 1).max().orElse(0);
        for (int time = 1; time <= horizon; time++)
            for (int a = 0; a < paths.size(); a++)
                for (int b = a + 1; b < paths.size(); b++) {
                    GridMap.Cell currentA = position(paths.get(a), time),
                                 currentB = position(paths.get(b), time);
                    if (currentA.equals(currentB))
                        result.add(new Conflict("vertex", time, a, b, currentA, currentA));
                    else if (currentA.equals(position(paths.get(b), time - 1)) &&
                             currentB.equals(position(paths.get(a), time - 1)))
                        result.add(new Conflict("edge", time, a, b,
                                                position(paths.get(a), time - 1), currentA));
                }
        return result;
    }
    static List<Constraint> split(Conflict conflict) {
        return List.of(new Constraint(conflict.a(), conflict.time(), conflict.kind(), conflict.u(),
                                      conflict.v()),
                       new Constraint(conflict.b(), conflict.time(), conflict.kind(), conflict.v(),
                                      conflict.u()));
    }
    static int cost(List<List<GridMap.Cell>> paths, String function) {
        return function.equals("SOC")
            ? paths.stream().mapToInt(path -> path.size() - 1).sum()
            : paths.stream().mapToInt(path -> path.size() - 1).max().orElse(0);
    }
    static final class Node {
        List<List<GridMap.Cell>> paths;
        List<LowLevel.Prohibitions> constraints;
        List<Conflict> conflicts;
        int number, depth, cost;
        Integer parent;
        Node(List<List<GridMap.Cell>> paths, List<LowLevel.Prohibitions> constraints, int number,
             int depth, Integer parent, String function) {
            this.paths = paths;
            this.constraints = constraints;
            this.number = number;
            this.depth = depth;
            this.parent = parent;
            conflicts = conflicts(paths);
            cost = cost(paths, function);
        }
    }
    static final Comparator<Node> ORDER = Comparator.comparingInt((Node node) -> node.cost)
                                              .thenComparingInt(node -> node.conflicts.size())
                                              .thenComparingInt(node -> node.number);
    static List<Constraint> orderedConstraints(Node node) {
        List<Constraint> result = new ArrayList<>();
        for (int i = 0; i < node.constraints.size(); i++) {
            for (LowLevel.State state : node.constraints.get(i).states)
                result.add(new Constraint(i, state.time(), "vertex", state.cell(), state.cell()));
            for (LowLevel.Move move : node.constraints.get(i).moves)
                result.add(
                    new Constraint(i, move.time(), "edge", move.source(), move.destination()));
        }
        result.sort(Comparator.comparingInt(Constraint::agent)
                        .thenComparingInt(Constraint::time)
                        .thenComparingInt(c -> c.kind().equals("vertex") ? 0 : 1)
                        .thenComparingInt(c -> c.u().x())
                        .thenComparingInt(c -> c.u().y())
                        .thenComparingInt(c -> c.v().x())
                        .thenComparingInt(c -> c.v().y()));
        return result;
    }
}
