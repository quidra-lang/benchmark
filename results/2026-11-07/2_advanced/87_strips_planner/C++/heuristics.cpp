#include "planner.hpp"
Value Heuristic::value(const std::string &name) const {
    if (name == "none")
        return 0;
    if (name == "goalcount")
        return goalcount;
    if (name == "hmax")
        return hmax;
    if (name == "hadd")
        return hadd;
    if (name == "ff")
        return ff;
    return lmcount;
}
static Value aggregate(const std::vector<Value> &costs, State required, bool sum) {
    Value out = 0;
    for (int fact : required.numbers()) {
        if (costs[fact] == infinity)
            return infinity;
        out = sum ? out + costs[fact] : std::max(out, costs[fact]);
    }
    return out;
}
static std::vector<Value> relaxedCosts(const GroundProblem &problem, State state, bool sum) {
    std::vector<Value> costs(problem.facts.size(), infinity);
    for (int fact : state.numbers())
        costs[fact] = 0;
    bool changed = true;
    while (changed) {
        changed = false;
        for (const GroundAction &action : problem.actions) {
            Value pre = aggregate(costs, action.pre, sum);
            if (pre == infinity)
                continue;
            Value value = action.cost + pre;
            for (int fact : action.add.numbers())
                if (value < costs[fact]) {
                    costs[fact] = value;
                    changed = true;
                }
        }
    }
    return costs;
}
static State reachableWithout(const GroundProblem &problem, State state, int forbidden) {
    for (;;) {
        State previous = state;
        for (const GroundAction &action : problem.actions)
            if (!action.add.has(forbidden) && state.contains(action.pre))
                state = state.united(action.add);
        if (state == previous)
            return state;
    }
}
const Heuristic &GroundProblem::heuristics(State state) {
    auto cached = cache.find(state);
    if (cached != cache.end())
        return cached->second;
    Heuristic out;
    out.goalcount = static_cast<Value>(goal.without(state).numbers().size());
    std::vector<Value> cmax = relaxedCosts(*this, state, false),
                       cadd = relaxedCosts(*this, state, true);
    out.hmax = aggregate(cmax, goal, false);
    out.hadd = aggregate(cadd, goal, true);
    std::vector<Plan> achievers(facts.size());
    for (std::size_t i = 0; i < actions.size(); ++i)
        for (int fact : actions[i].add.numbers())
            achievers[fact].push_back(static_cast<int>(i));
    if (out.hadd == infinity)
        out.ff = infinity;
    else {
        Plan best(facts.size(), -1);
        for (std::size_t fact = 0; fact < facts.size(); ++fact)
            if (!state.has(static_cast<int>(fact)) && cadd[fact] != infinity) {
                Value minimum = infinity;
                for (int i : achievers[fact]) {
                    Value pre = aggregate(cadd, actions[i].pre, true);
                    if (pre != infinity && actions[i].cost + pre < minimum) {
                        minimum = actions[i].cost + pre;
                        best[fact] = i;
                    }
                }
            }
        std::vector<bool> selected(actions.size());
        std::function<void(int)> require = [&](int fact) {
            if (state.has(fact))
                return;
            int action = best[fact];
            if (selected[action])
                return;
            selected[action] = true;
            for (int pre : actions[action].pre.numbers())
                require(pre);
        };
        for (int fact : goal.numbers())
            require(fact);
        for (std::size_t i = 0; i < actions.size(); ++i)
            if (selected[i]) {
                out.relaxed.push_back(static_cast<int>(i));
                out.ff += actions[i].cost;
                if (applicable(actions[i], state))
                    out.helpful.push_back(static_cast<int>(i));
            }
    }
    Plan factLevels(facts.size(), -1), actionLevels(actions.size(), -1);
    for (int fact : state.numbers())
        factLevels[fact] = 0;
    for (int level = 0;; ++level) {
        bool changed = false;
        for (std::size_t i = 0; i < actions.size(); ++i)
            if (actionLevels[i] < 0) {
                bool ready = true;
                for (int pre : actions[i].pre.numbers())
                    if (factLevels[pre] < 0 || factLevels[pre] > level) {
                        ready = false;
                        break;
                    }
                if (!ready)
                    continue;
                actionLevels[i] = level;
                for (int fact : actions[i].add.numbers())
                    if (factLevels[fact] < 0) {
                        factLevels[fact] = level + 1;
                        changed = true;
                    }
            }
        if (!changed)
            break;
    }
    bool unreachable = false;
    for (int fact : goal.numbers())
        if (factLevels[fact] < 0)
            unreachable = true;
    if (unreachable)
        out.lmcount = infinity;
    else {
        out.landmarks = goal.without(state);
        Plan verified(facts.size(), -1);
        for (;;) {
            State previous = out.landmarks;
            for (int fact : previous.numbers()) {
                State common;
                bool first = true;
                for (int action : achievers[fact])
                    if (actionLevels[action] == factLevels[fact] - 1) {
                        common =
                            first ? actions[action].pre : common.intersected(actions[action].pre);
                        first = false;
                    }
                for (int candidate : common.without(state).numbers())
                    if (!out.landmarks.has(candidate)) {
                        if (verified[candidate] < 0)
                            verified[candidate] =
                                !reachableWithout(*this, state, candidate).contains(goal);
                        if (verified[candidate])
                            out.landmarks.put(candidate);
                    }
            }
            if (out.landmarks == previous)
                break;
        }
        out.lmcount = static_cast<Value>(out.landmarks.numbers().size());
    }
    return cache.emplace(state, std::move(out)).first->second;
}
