#include "planner.hpp"
struct Mutex {
    std::set<std::pair<int, int>> pairs;
    bool has(int a, int b) const { return a != b && pairs.count(std::minmax(a, b)); }
    void put(int a, int b) { pairs.insert(std::minmax(a, b)); }
    bool compatible(State facts) const {
        Plan numbers = facts.numbers();
        for (std::size_t i = 0; i < numbers.size(); ++i)
            for (std::size_t j = i + 1; j < numbers.size(); ++j)
                if (has(numbers[i], numbers[j]))
                    return false;
        return true;
    }
};
struct PlanningGraph {
    const std::vector<GraphElement> &actions;
    std::vector<State> facts;
    std::vector<Mutex> factMutex;
    std::vector<std::vector<GraphElement>> elements;
    std::vector<Mutex> actionMutex;
    std::set<std::pair<int, State>> memo;
    GraphPlanResult result;
    std::optional<Layers> extract(int level, State goals) {
        if (!level)
            return Layers{};
        const std::pair<int, State> key{level, goals};
        if (memo.count(key)) {
            ++result.memoHits;
            return std::nullopt;
        }
        ++result.searched;
        const Plan numbers = goals.numbers();
        const std::vector<GraphElement> &entries = elements[level - 1];
        const Mutex &mutex = actionMutex[level - 1];
        Plan chosen;
        std::function<std::optional<Layers>(std::size_t)> assign =
            [&](std::size_t at) -> std::optional<Layers> {
            State covered;
            for (int index : chosen)
                covered = covered.united(entries[index].add);
            while (at < numbers.size() && covered.has(numbers[at]))
                ++at;
            if (at == numbers.size()) {
                State pre;
                for (int index : chosen)
                    pre = pre.united(entries[index].pre);
                std::optional<Layers> layers = extract(level - 1, pre);
                if (!layers)
                    return std::nullopt;
                Plan layer;
                for (int index : chosen)
                    if (entries[index].action >= 0)
                        layer.push_back(entries[index].action);
                std::sort(layer.begin(), layer.end());
                layers->push_back(std::move(layer));
                return layers;
            }
            int fact = numbers[at];
            Plan achievers;
            for (std::size_t i = 0; i < entries.size(); ++i)
                if (entries[i].action < 0 && entries[i].fact == fact)
                    achievers.push_back(static_cast<int>(i));
            for (std::size_t i = 0; i < entries.size(); ++i)
                if (entries[i].action >= 0 && entries[i].add.has(fact))
                    achievers.push_back(static_cast<int>(i));
            for (int index : achievers) {
                bool compatible = true;
                for (int previous : chosen)
                    if (mutex.has(index, previous)) {
                        compatible = false;
                        break;
                    }
                if (!compatible)
                    continue;
                ++result.tried;
                chosen.push_back(index);
                std::optional<Layers> layers = assign(at + 1);
                chosen.pop_back();
                if (layers)
                    return layers;
            }
            return std::nullopt;
        };
        std::optional<Layers> layers = assign(0);
        if (!layers)
            memo.insert(key);
        return layers;
    }
    void expand() {
        State previous = facts.back();
        const Mutex &previousMutex = factMutex.back();
        std::vector<GraphElement> entries;
        for (const GraphElement &action : actions)
            if (previous.contains(action.pre) && previousMutex.compatible(action.pre))
                entries.push_back(action);
        int real = static_cast<int>(entries.size());
        for (int fact : previous.numbers()) {
            State one;
            one.put(fact);
            entries.push_back({-1, fact, one, one, {}});
        }
        Mutex mutex;
        for (std::size_t i = 0; i < entries.size(); ++i)
            for (std::size_t j = i + 1; j < entries.size(); ++j) {
                const GraphElement &a = entries[i], &b = entries[j];
                bool exclusive =
                    a.del.intersects(b.pre.united(b.add)) || b.del.intersects(a.pre.united(a.add));
                if (!exclusive)
                    for (int p : a.pre.numbers())
                        for (int q : b.pre.numbers())
                            if (previousMutex.has(p, q))
                                exclusive = true;
                if (exclusive)
                    mutex.put(static_cast<int>(i), static_cast<int>(j));
            }
        result.logs.push_back("action level " + std::to_string(elements.size()) +
                              ": actions=" + std::to_string(real) +
                              " noops=" + std::to_string(previous.numbers().size()) +
                              " mutexes=" + std::to_string(mutex.pairs.size()));
        State next;
        std::array<Plan, 256> achievers;
        for (std::size_t i = 0; i < entries.size(); ++i) {
            next = next.united(entries[i].add);
            for (int fact : entries[i].add.numbers())
                achievers[fact].push_back(static_cast<int>(i));
        }
        Mutex nextMutex;
        Plan numbers = next.numbers();
        for (std::size_t i = 0; i < numbers.size(); ++i)
            for (std::size_t j = i + 1; j < numbers.size(); ++j) {
                int p = numbers[i], q = numbers[j];
                bool exclusive = true;
                for (int x : achievers[p])
                    for (int y : achievers[q])
                        if (x == y || !mutex.has(x, y))
                            exclusive = false;
                if (exclusive)
                    nextMutex.put(p, q);
            }
        elements.push_back(std::move(entries));
        actionMutex.push_back(std::move(mutex));
        facts.push_back(next);
        factMutex.push_back(std::move(nextMutex));
    }
};
GraphPlanResult graphPlan(const std::vector<GraphElement> &actions, State initial, State goal,
                          int limit) {
    PlanningGraph graph{actions, {initial}, {Mutex{}}, {}, {}, {}, {}};
    for (int level = 0;; ++level) {
        State facts = graph.facts[level];
        const Mutex &mutex = graph.factMutex[level];
        graph.result.logs.push_back("fact level " + std::to_string(level) +
                                    ": facts=" + std::to_string(facts.numbers().size()) +
                                    " mutexes=" + std::to_string(mutex.pairs.size()));
        bool attempted = facts.contains(goal) && mutex.compatible(goal);
        if (attempted) {
            Value searched = graph.result.searched, hits = graph.result.memoHits;
            std::optional<Layers> layers = graph.extract(level, goal);
            graph.result.logs.push_back(
                "extract level " + std::to_string(level) + ": " + (layers ? "success" : "fail") +
                " searched=" + std::to_string(graph.result.searched - searched) +
                " memo_hits=" + std::to_string(graph.result.memoHits - hits));
            if (layers) {
                graph.result.status = "solved";
                graph.result.layers = std::move(*layers);
                for (const Plan &layer : graph.result.layers)
                    graph.result.plan.insert(graph.result.plan.end(), layer.begin(), layer.end());
                return std::move(graph.result);
            }
        } else if (level && facts.numbers().size() == graph.facts[level - 1].numbers().size() &&
                   mutex.pairs.size() == graph.factMutex[level - 1].pairs.size()) {
            graph.result.status = "unreachable";
            return std::move(graph.result);
        }
        if (level == limit) {
            graph.result.status = "level limit";
            return std::move(graph.result);
        }
        graph.expand();
    }
}
