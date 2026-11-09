import java.util.*;
final class Heuristics {
    static final int INF = -1;
    static final List<String> NAMES = List.of("goalcount", "hmax", "hadd", "ff", "lmcount");
    record Levels(int[] facts, int[] actions) {}
    Grounding.Problem problem;
    List<List<Integer>> achievers = new ArrayList<>();
    Map<BitSet, int[]> maxCosts = new HashMap<>(), addCosts = new HashMap<>();
    Map<BitSet, List<Integer>> relaxedCache = new HashMap<>();
    Map<BitSet, Levels> levelsCache = new HashMap<>();
    Map<BitSet, BitSet> landmarkCache = new HashMap<>();
    Heuristics(Grounding.Problem problem) {
        this.problem = problem;
        for (PddlParser.Atom fact : problem.facts)
            achievers.add(new ArrayList<>());
        for (Grounding.Action action : problem.actions)
            for (int fact : Grounding.numbers(action.add()))
                achievers.get(fact).add(action.number());
    }
    int[] relaxedCosts(BitSet state, boolean maximum) {
        Map<BitSet, int[]> cache = maximum ? maxCosts : addCosts;
        int[] cached = cache.get(state);
        if (cached != null)
            return cached;
        int[] costs = new int[problem.facts.size()];
        Arrays.fill(costs, INF);
        for (int fact : Grounding.numbers(state))
            costs[fact] = 0;
        boolean changed = true;
        while (changed) {
            changed = false;
            for (Grounding.Action action : problem.actions) {
                int aggregate = 0;
                boolean finite = true;
                for (int fact : Grounding.numbers(action.pre())) {
                    if (costs[fact] == INF) {
                        finite = false;
                        break;
                    }
                    aggregate =
                        maximum ? Math.max(aggregate, costs[fact]) : aggregate + costs[fact];
                }
                if (!finite)
                    continue;
                int value = action.cost() + aggregate;
                for (int fact : Grounding.numbers(action.add()))
                    if (costs[fact] == INF || value < costs[fact]) {
                        costs[fact] = value;
                        changed = true;
                    }
            }
        }
        cache.put(state, costs);
        return costs;
    }
    List<Integer> relaxedPlan(BitSet state) {
        if (relaxedCache.containsKey(state))
            return relaxedCache.get(state);
        int[] costs = relaxedCosts(state, false);
        for (int goal : Grounding.numbers(problem.goal))
            if (costs[goal] == INF) {
                relaxedCache.put(state, null);
                return null;
            }
        Set<Integer> chosen = new TreeSet<>();
        Deque<Integer> pending = new ArrayDeque<>();
        for (int goal : Grounding.numbers(problem.goal))
            if (!state.get(goal))
                pending.add(goal);
        while (!pending.isEmpty()) {
            int fact = pending.removeLast(), winner = -1, lowest = INF;
            for (int number : achievers.get(fact)) {
                Grounding.Action action = problem.actions.get(number);
                int cost = action.cost();
                boolean finite = true;
                for (int pre : Grounding.numbers(action.pre())) {
                    if (costs[pre] == INF) {
                        finite = false;
                        break;
                    }
                    cost += costs[pre];
                }
                if (finite && (lowest == INF || cost < lowest)) {
                    lowest = cost;
                    winner = number;
                }
            }
            if (chosen.add(winner))
                for (int pre : Grounding.numbers(problem.actions.get(winner).pre()))
                    if (!state.get(pre))
                        pending.add(pre);
        }
        List<Integer> result = List.copyOf(chosen);
        relaxedCache.put(state, result);
        return result;
    }
    List<Integer> helpful(BitSet state) {
        List<Integer> result = new ArrayList<>(), plan = relaxedPlan(state);
        if (plan != null)
            for (int number : plan)
                if (Search.applicable(problem.actions.get(number), state))
                    result.add(number);
        return result;
    }
    Levels levels(BitSet state) {
        Levels cached = levelsCache.get(state);
        if (cached != null)
            return cached;
        int[] facts = new int[problem.facts.size()], actions = new int[problem.actions.size()];
        Arrays.fill(facts, INF);
        Arrays.fill(actions, INF);
        for (int fact : Grounding.numbers(state))
            facts[fact] = 0;
        int level = 0;
        while (true) {
            boolean changed = false;
            for (Grounding.Action action : problem.actions) {
                if (actions[action.number()] != INF)
                    continue;
                boolean available = true;
                for (int pre : Grounding.numbers(action.pre()))
                    if (facts[pre] == INF || facts[pre] > level)
                        available = false;
                if (!available)
                    continue;
                actions[action.number()] = level;
                for (int fact : Grounding.numbers(action.add()))
                    if (facts[fact] == INF) {
                        facts[fact] = level + 1;
                        changed = true;
                    }
            }
            if (!changed)
                break;
            level++;
        }
        Levels result = new Levels(facts, actions);
        levelsCache.put(state, result);
        return result;
    }
    boolean verified(BitSet state, int excluded) {
        BitSet reachable = (BitSet)state.clone();
        boolean changed = true;
        while (changed) {
            changed = false;
            for (Grounding.Action action : problem.actions)
                if (!action.add().get(excluded) && Grounding.contains(reachable, action.pre())) {
                    int before = reachable.cardinality();
                    reachable.or(action.add());
                    if (reachable.cardinality() != before)
                        changed = true;
                }
        }
        return !Grounding.contains(reachable, problem.goal);
    }
    BitSet landmarks(BitSet state) {
        if (landmarkCache.containsKey(state))
            return landmarkCache.get(state);
        Levels levels = levels(state);
        for (int goal : Grounding.numbers(problem.goal))
            if (levels.facts()[goal] == INF) {
                landmarkCache.put(state, null);
                return null;
            }
        BitSet landmarks = (BitSet)problem.goal.clone();
        landmarks.andNot(state);
        Deque<Integer> pending = new ArrayDeque<>(Grounding.numbers(landmarks));
        Map<Integer, Boolean> verification = new HashMap<>();
        while (!pending.isEmpty()) {
            int fact = pending.remove();
            BitSet candidates = null;
            for (int number : achievers.get(fact))
                if (levels.actions()[number] == levels.facts()[fact] - 1) {
                    if (candidates == null)
                        candidates = (BitSet)problem.actions.get(number).pre().clone();
                    else
                        candidates.and(problem.actions.get(number).pre());
                }
            candidates.andNot(state);
            candidates.andNot(landmarks);
            for (int candidate : Grounding.numbers(candidates))
                if (verification.computeIfAbsent(candidate, key -> verified(state, key))) {
                    landmarks.set(candidate);
                    pending.add(candidate);
                }
        }
        landmarkCache.put(state, landmarks);
        return landmarks;
    }
    int value(String name, BitSet state) {
        if (name.equals("none"))
            return 0;
        if (name.equals("goalcount")) {
            BitSet remaining = (BitSet)problem.goal.clone();
            remaining.andNot(state);
            return remaining.cardinality();
        }
        if (name.equals("hmax") || name.equals("hadd")) {
            boolean maximum = name.equals("hmax");
            int[] costs = relaxedCosts(state, maximum);
            int result = 0;
            for (int goal : Grounding.numbers(problem.goal)) {
                if (costs[goal] == INF)
                    return INF;
                result = maximum ? Math.max(result, costs[goal]) : result + costs[goal];
            }
            return result;
        }
        if (name.equals("ff")) {
            List<Integer> plan = relaxedPlan(state);
            if (plan == null)
                return INF;
            int total = 0;
            for (int number : plan)
                total += problem.actions.get(number).cost();
            return total;
        }
        BitSet landmarks = landmarks(state);
        return landmarks == null ? INF : landmarks.cardinality();
    }
    int[] values(BitSet state) {
        int[] result = new int[NAMES.size()];
        for (int i = 0; i < result.length; i++)
            result[i] = value(NAMES.get(i), state);
        return result;
    }
}
