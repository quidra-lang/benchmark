import java.util.*;
final class GraphPlan {
    record Pair(int first, int second) {
        Pair {
            if (first > second) {
                int t = first;
                first = second;
                second = t;
            }
        }
    }
    record Action(int number, BitSet pre, BitSet add, BitSet delete) {}
    record Element(Integer number, BitSet pre, BitSet add, BitSet delete) {}
    record MemoKey(int level, List<Integer> goals) {
        MemoKey { goals = List.copyOf(goals); }
    }
    record
        Result(Search.Result search, List<List<Integer>> layers, List<String> lines, int memoHits) {
    }
    interface Frame {}
    static final class ExtractFrame implements Frame {
        int level, stage;
        List<Integer> goals;
        ExtractFrame(int level, List<Integer> goals) {
            this.level = level;
            this.goals = goals;
        }
    }
    static final class AssignFrame implements Frame {
        int level, position, stage, producerIndex;
        List<Integer> goals, chosen, producers;
        AssignFrame(int level, List<Integer> goals, int position, List<Integer> chosen) {
            this.level = level;
            this.goals = goals;
            this.position = position;
            this.chosen = chosen;
        }
    }
    List<Action> actions;
    BitSet goal;
    int limit, searched, memoHits, tried;
    List<BitSet> facts = new ArrayList<>();
    List<Set<Pair>> factMutexes = new ArrayList<>();
    List<List<Element>> elements = new ArrayList<>();
    List<Set<Pair>> elementMutexes = new ArrayList<>();
    List<Map<Integer, List<Integer>>> achievers = new ArrayList<>();
    Set<MemoKey> memo = new HashSet<>();
    List<String> lines = new ArrayList<>();
    GraphPlan(List<Action> actions, BitSet initial, BitSet goal, int limit) {
        this.actions = actions;
        this.goal = goal;
        this.limit = limit;
        facts.add(initial);
        factMutexes.add(new HashSet<>());
    }
    static boolean compatible(BitSet facts, Set<Pair> mutexes) {
        List<Integer> numbers = Grounding.numbers(facts);
        for (int i = 0; i < numbers.size(); i++)
            for (int j = i + 1; j < numbers.size(); j++)
                if (mutexes.contains(new Pair(numbers.get(i), numbers.get(j))))
                    return false;
        return true;
    }
    static boolean conflict(Element first, Element second, Set<Pair> mutexes) {
        if (first.delete().intersects(second.pre()) || first.delete().intersects(second.add()) ||
            second.delete().intersects(first.pre()) || second.delete().intersects(first.add()))
            return true;
        for (int p : Grounding.numbers(first.pre()))
            for (int q : Grounding.numbers(second.pre()))
                if (mutexes.contains(new Pair(p, q)))
                    return true;
        return false;
    }
    void expand(int level) {
        BitSet present = facts.get(level);
        Set<Pair> mutexes = factMutexes.get(level);
        List<Element> available = new ArrayList<>();
        for (Action action : actions)
            if (Grounding.contains(present, action.pre()) && compatible(action.pre(), mutexes))
                available.add(
                    new Element(action.number(), action.pre(), action.add(), action.delete()));
        int actionCount = available.size();
        for (int fact : Grounding.numbers(present)) {
            BitSet singleton = new BitSet();
            singleton.set(fact);
            available.add(new Element(null, singleton, singleton, new BitSet()));
        }
        Set<Pair> exclusive = new HashSet<>();
        for (int first = 0; first < available.size(); first++)
            for (int second = first + 1; second < available.size(); second++)
                if (conflict(available.get(first), available.get(second), mutexes))
                    exclusive.add(new Pair(first, second));
        lines.add("action level " + level + ": actions=" + actionCount +
                  " noops=" + present.cardinality() + " mutexes=" + exclusive.size());
        Map<Integer, List<Integer>> producers = new HashMap<>();
        for (int i = 0; i < available.size(); i++)
            for (int fact : Grounding.numbers(available.get(i).add()))
                producers.computeIfAbsent(fact, k -> new ArrayList<>()).add(i);
        for (List<Integer> list : producers.values())
            list.sort(Comparator.comparingInt(
                i -> available.get(i).number() == null ? -1 : available.get(i).number()));
        BitSet following = new BitSet();
        for (int fact : producers.keySet())
            following.set(fact);
        Set<Pair> followingMutexes = new HashSet<>();
        List<Integer> followingNumbers = Grounding.numbers(following);
        for (int i = 0; i < followingNumbers.size(); i++)
            for (int j = i + 1; j < followingNumbers.size(); j++) {
                int p = followingNumbers.get(i), q = followingNumbers.get(j);
                boolean allExclusive = true;
                for (int x : producers.get(p)) {
                    for (int y : producers.get(q))
                        if (x == y || !exclusive.contains(new Pair(x, y))) {
                            allExclusive = false;
                            break;
                        }
                    if (!allExclusive)
                        break;
                }
                if (allExclusive)
                    followingMutexes.add(new Pair(p, q));
            }
        elements.add(available);
        elementMutexes.add(exclusive);
        achievers.add(producers);
        facts.add(following);
        factMutexes.add(followingMutexes);
    }
    List<List<Integer>> extract(int level, List<Integer> goals) {
        Deque<Frame> stack = new ArrayDeque<>();
        stack.push(new ExtractFrame(level, goals));
        List<List<Integer>> result = null;
        while (!stack.isEmpty()) {
            Frame top = stack.peek();
            if (top instanceof ExtractFrame frame) {
                MemoKey key = new MemoKey(frame.level, frame.goals);
                if (frame.stage == 0) {
                    if (frame.level == 0) {
                        stack.pop();
                        result = List.of();
                        continue;
                    }
                    if (memo.contains(key)) {
                        memoHits++;
                        stack.pop();
                        result = null;
                        continue;
                    }
                    searched++;
                    frame.stage = 1;
                    stack.push(new AssignFrame(frame.level, frame.goals, 0, List.of()));
                } else {
                    if (result == null)
                        memo.add(key);
                    stack.pop();
                }
                continue;
            }
            AssignFrame frame = (AssignFrame)top;
            List<Element> available = elements.get(frame.level - 1);
            if (frame.stage == 0) {
                while (frame.position < frame.goals.size()) {
                    boolean covered = false;
                    for (int chosen : frame.chosen)
                        if (available.get(chosen).add().get(frame.goals.get(frame.position)))
                            covered = true;
                    if (!covered)
                        break;
                    frame.position++;
                }
                if (frame.position == frame.goals.size()) {
                    BitSet previous = new BitSet();
                    for (int chosen : frame.chosen)
                        previous.or(available.get(chosen).pre());
                    frame.stage = 1;
                    stack.push(new ExtractFrame(frame.level - 1, Grounding.numbers(previous)));
                    continue;
                }
                frame.producers =
                    achievers.get(frame.level - 1).get(frame.goals.get(frame.position));
                frame.stage = 2;
            }
            if (frame.stage == 1) {
                if (result != null) {
                    List<Integer> layer = new ArrayList<>();
                    for (int chosen : frame.chosen) {
                        Integer number = available.get(chosen).number();
                        if (number != null)
                            layer.add(number);
                    }
                    layer.sort(Integer::compare);
                    List<List<Integer>> layers = new ArrayList<>(result);
                    layers.add(List.copyOf(layer));
                    result = layers;
                }
                stack.pop();
                continue;
            }
            if (frame.stage == 3) {
                if (result != null) {
                    stack.pop();
                    continue;
                }
                frame.stage = 2;
            }
            boolean pushed = false;
            while (frame.producerIndex < frame.producers.size()) {
                int candidate = frame.producers.get(frame.producerIndex++);
                boolean allowed = true;
                for (int chosen : frame.chosen)
                    if (elementMutexes.get(frame.level - 1).contains(new Pair(candidate, chosen)))
                        allowed = false;
                if (!allowed)
                    continue;
                tried++;
                List<Integer> chosen = new ArrayList<>(frame.chosen);
                chosen.add(candidate);
                frame.stage = 3;
                stack.push(new AssignFrame(frame.level, frame.goals, frame.position + 1, chosen));
                pushed = true;
                break;
            }
            if (!pushed) {
                stack.pop();
                result = null;
            }
        }
        return result;
    }
    Result finish(String status, List<List<Integer>> layers) {
        List<Integer> plan = new ArrayList<>();
        for (List<Integer> layer : layers)
            plan.addAll(layer);
        return new Result(new Search.Result(status, searched, tried, plan), layers, lines,
                          memoHits);
    }
    Result run() {
        for (int level = 0; level <= limit; level++) {
            BitSet present = facts.get(level);
            Set<Pair> mutexes = factMutexes.get(level);
            lines.add("fact level " + level + ": facts=" + present.cardinality() +
                      " mutexes=" + mutexes.size());
            boolean possible = Grounding.contains(present, goal) && compatible(goal, mutexes);
            if (possible) {
                int before = searched, beforeHits = memoHits;
                List<List<Integer>> layers = extract(level, Grounding.numbers(goal));
                lines.add("extract level " + level + ": " + (layers == null ? "fail" : "success") +
                          " searched=" + (searched - before) +
                          " memo_hits=" + (memoHits - beforeHits));
                if (layers != null)
                    return finish("solved", layers);
            } else if (level > 0 && present.cardinality() == facts.get(level - 1).cardinality() &&
                       mutexes.size() == factMutexes.get(level - 1).size())
                return finish("unreachable", List.of());
            if (level == limit)
                return finish("level limit", List.of());
            expand(level);
        }
        throw new IllegalStateException();
    }
}
