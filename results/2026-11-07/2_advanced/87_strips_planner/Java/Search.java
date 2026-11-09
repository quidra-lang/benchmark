import java.util.*;
final class Search {
    record Result(String status, int expanded, int generated, List<Integer> plan) {
        Result { plan = List.copyOf(plan); }
        boolean solved() { return status.equals("solved"); }
    }
    record Node(BitSet state, int g, int depth, Node parent, int action) {}
    record Entry(int f, int h, int serial, Node node) {}
    record Local(BitSet state, List<Integer> path) {}
    static Result failure(String status, int expanded, int generated) {
        return new Result(status, expanded, generated, List.of());
    }
    static boolean applicable(Grounding.Action action, BitSet state) {
        return Grounding.contains(state, action.pre()) && !state.intersects(action.neg());
    }
    static BitSet apply(Grounding.Action action, BitSet state) {
        BitSet result = (BitSet)state.clone();
        result.andNot(action.delete());
        result.or(action.add());
        return result;
    }
    static List<Integer> reconstruct(Node node) {
        List<Integer> plan = new ArrayList<>();
        for (Node current = node; current.parent() != null; current = current.parent())
            plan.add(current.action());
        Collections.reverse(plan);
        return plan;
    }
    static int priority(String algorithm, Node node, int h, int weight) {
        return switch (algorithm) {
            case "bfs" -> node.depth();
            case "ucs" -> node.g();
            case "gbfs" -> h;
            default -> node.g() + h *(algorithm.equals("wastar") ? weight : 1);
        };
    }
    static Result bestFirst(Grounding.Problem problem, BitSet start, String algorithm,
                            String heuristic, int budget, int weight, Heuristics evaluator) {
        int initialH = evaluator.value(heuristic, start);
        if (initialH == Heuristics.INF)
            return failure("dead end", 0, 0);
        Node first = new Node(start, 0, 0, null, -1);
        PriorityQueue<Entry> open = new PriorityQueue<>(
            Comparator.comparingInt(Entry::f).thenComparingInt(Entry::h).thenComparingInt(
                Entry::serial));
        open.add(new Entry(priority(algorithm, first, initialH, weight), initialH, 0, first));
        Map<BitSet, Integer> best = new HashMap<>();
        best.put(start, 0);
        int serial = 1, expanded = 0, generated = 0;
        boolean reopen = Set.of("ucs", "astar", "wastar").contains(algorithm);
        while (!open.isEmpty()) {
            Node node = open.remove().node();
            if (reopen && node.g() > best.get(node.state()))
                continue;
            if (Grounding.contains(node.state(), problem.goal))
                return new Result("solved", expanded, generated, reconstruct(node));
            if (expanded == budget)
                return failure("budget", expanded, generated);
            expanded++;
            for (Grounding.Action action : problem.actions)
                if (applicable(action, node.state())) {
                    BitSet state = apply(action, node.state());
                    generated++;
                    int cost = node.g() + action.cost();
                    Integer previous = best.get(state);
                    if (previous != null && (!reopen || previous <= cost))
                        continue;
                    best.put(state, cost);
                    int h = evaluator.value(heuristic, state);
                    if (h == Heuristics.INF)
                        continue;
                    Node child = new Node(state, cost, node.depth() + 1, node, action.number());
                    open.add(new Entry(priority(algorithm, child, h, weight), h, serial++, child));
                }
        }
        return failure("exhausted", expanded, generated);
    }
    static Result hillClimbing(Grounding.Problem problem, BitSet start, String heuristic,
                               int budget, Heuristics evaluator) {
        BitSet current = start;
        List<Integer> plan = new ArrayList<>();
        int currentH = evaluator.value(heuristic, current), expanded = 0, generated = 0;
        if (currentH == Heuristics.INF)
            return failure("dead end", 0, 0);
        while (!Grounding.contains(current, problem.goal)) {
            Deque<Local> queue = new ArrayDeque<>();
            queue.add(new Local(current, List.of()));
            Set<BitSet> visited = new HashSet<>();
            visited.add(current);
            boolean improved = false;
            while (!queue.isEmpty() && !improved) {
                Local local = queue.remove();
                if (expanded == budget)
                    return failure("budget", expanded, generated);
                expanded++;
                for (int number : evaluator.helpful(local.state())) {
                    BitSet successor = apply(problem.actions.get(number), local.state());
                    generated++;
                    if (!visited.add(successor))
                        continue;
                    int h = evaluator.value(heuristic, successor);
                    if (h == Heuristics.INF)
                        continue;
                    List<Integer> path = new ArrayList<>(local.path());
                    path.add(number);
                    if (h < currentH) {
                        plan.addAll(path);
                        current = successor;
                        currentH = h;
                        improved = true;
                        break;
                    }
                    queue.add(new Local(successor, path));
                }
            }
            if (!improved)
                return failure("stuck", expanded, generated);
        }
        return new Result("solved", expanded, generated, plan);
    }
    static Result run(Grounding.Problem problem, BitSet start, String algorithm, String heuristic,
                      int budget, int weight, Heuristics evaluator) {
        return algorithm.equals("ehc")
            ? hillClimbing(problem, start, heuristic, budget, evaluator)
            : bestFirst(problem, start, algorithm, heuristic, budget, weight, evaluator);
    }
}
