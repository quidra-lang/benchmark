#include "planner.h"
Value heuristic_value(const Heuristic *heuristic, const char *name) {
    if (!strcmp(name, "none"))
        return 0;
    if (!strcmp(name, "goalcount"))
        return heuristic->goalcount;
    if (!strcmp(name, "hmax"))
        return heuristic->hmax;
    if (!strcmp(name, "hadd"))
        return heuristic->hadd;
    if (!strcmp(name, "ff"))
        return heuristic->ff;
    return heuristic->lmcount;
}
static Value aggregate(const Value *costs, State required, bool sum) {
    Value out = 0;
    for (int i = 0; i < 100; ++i)
        if (state_has(required, i)) {
            if (costs[i] == INFINITY_VALUE)
                return INFINITY_VALUE;
            if (sum)
                out += costs[i];
            else if (costs[i] > out)
                out = costs[i];
        }
    return out;
}
static void relaxed_costs(const GroundProblem *ground, State state, bool sum, Value *costs) {
    for (int i = 0; i < ground->facts.count; ++i)
        costs[i] = state_has(state, i) ? 0 : INFINITY_VALUE;
    for (;;) {
        bool changed = false;
        for (int i = 0; i < ground->action_count; ++i) {
            const GroundAction *action = &ground->actions[i];
            Value pre = aggregate(costs, action->pre, sum);
            if (pre == INFINITY_VALUE)
                continue;
            Value value = action->cost + pre;
            for (int fact = 0; fact < ground->facts.count; ++fact)
                if (state_has(action->add, fact) && value < costs[fact]) {
                    costs[fact] = value;
                    changed = true;
                }
        }
        if (!changed)
            return;
    }
}
static State reachable_without(const GroundProblem *ground, State state, int forbidden) {
    for (;;) {
        State previous = state;
        for (int i = 0; i < ground->action_count; ++i) {
            const GroundAction *action = &ground->actions[i];
            if (!state_has(action->add, forbidden) && state_contains(state, action->pre))
                state = state_union(state, action->add);
        }
        if (state_equal(previous, state))
            return state;
    }
}
static void require_fact(const GroundProblem *ground, State state, const int *best, bool *selected,
                         int fact) {
    if (state_has(state, fact))
        return;
    int action = best[fact];
    if (selected[action])
        return;
    selected[action] = true;
    for (int pre = 0; pre < ground->facts.count; ++pre)
        if (state_has(ground->actions[action].pre, pre))
            require_fact(ground, state, best, selected, pre);
}
static void cache_rehash(GroundProblem *ground, int size) {
    free(ground->cache_slots);
    ground->cache_slots = allocate((size_t)size * sizeof *ground->cache_slots);
    ground->cache_slot_count = size;
    for (int i = 0; i < ground->cache_count; ++i) {
        int slot = (int)(state_hash(ground->cache[i].state) & (uint64_t)(size - 1));
        while (ground->cache_slots[slot])
            slot = (slot + 1) & (size - 1);
        ground->cache_slots[slot] = i + 1;
    }
}
Heuristic *heuristics(GroundProblem *ground, State state) {
    if (!ground->cache_slot_count || (ground->cache_count + 1) * 10 > ground->cache_slot_count * 7)
        cache_rehash(ground, ground->cache_slot_count ? ground->cache_slot_count * 2 : 128);
    int slot = (int)(state_hash(state) & (uint64_t)(ground->cache_slot_count - 1));
    while (ground->cache_slots[slot]) {
        int index = ground->cache_slots[slot] - 1;
        if (state_equal(ground->cache[index].state, state))
            return ground->cache[index].heuristic;
        slot = (slot + 1) & (ground->cache_slot_count - 1);
    }
    Heuristic *out = allocate(sizeof *out);
    out->goalcount = state_count(state_without(ground->goal, state));
    Value cmax[100] = {0}, cadd[100] = {0};
    relaxed_costs(ground, state, false, cmax);
    relaxed_costs(ground, state, true, cadd);
    out->hmax = aggregate(cmax, ground->goal, false);
    out->hadd = aggregate(cadd, ground->goal, true);
    IntList achievers[100] = {0};
    for (int i = 0; i < ground->action_count; ++i)
        for (int fact = 0; fact < ground->facts.count; ++fact)
            if (state_has(ground->actions[i].add, fact))
                int_push(&achievers[fact], i);
    if (out->hadd == INFINITY_VALUE)
        out->ff = INFINITY_VALUE;
    else {
        int best[100];
        for (int fact = 0; fact < ground->facts.count; ++fact) {
            best[fact] = -1;
            if (state_has(state, fact) || cadd[fact] == INFINITY_VALUE)
                continue;
            Value minimum = INFINITY_VALUE;
            for (int j = 0; j < achievers[fact].count; ++j) {
                int index = achievers[fact].data[j];
                const GroundAction *action = &ground->actions[index];
                Value pre = aggregate(cadd, action->pre, true);
                if (pre != INFINITY_VALUE && action->cost + pre < minimum) {
                    minimum = action->cost + pre;
                    best[fact] = index;
                }
            }
        }
        bool selected[300] = {0};
        for (int fact = 0; fact < ground->facts.count; ++fact)
            if (state_has(ground->goal, fact))
                require_fact(ground, state, best, selected, fact);
        for (int i = 0; i < ground->action_count; ++i)
            if (selected[i]) {
                int_push(&out->relaxed, i);
                out->ff += ground->actions[i].cost;
                if (applicable(&ground->actions[i], state))
                    int_push(&out->helpful, i);
            }
    }
    int fact_levels[100], action_levels[300];
    for (int i = 0; i < ground->facts.count; ++i)
        fact_levels[i] = state_has(state, i) ? 0 : -1;
    for (int i = 0; i < ground->action_count; ++i)
        action_levels[i] = -1;
    for (int level = 0;; ++level) {
        bool changed = false;
        for (int i = 0; i < ground->action_count; ++i)
            if (action_levels[i] < 0) {
                const GroundAction *action = &ground->actions[i];
                bool ready = true;
                for (int pre = 0; pre < ground->facts.count; ++pre)
                    if (state_has(action->pre, pre) &&
                        (fact_levels[pre] < 0 || fact_levels[pre] > level)) {
                        ready = false;
                        break;
                    }
                if (!ready)
                    continue;
                action_levels[i] = level;
                for (int fact = 0; fact < ground->facts.count; ++fact)
                    if (state_has(action->add, fact) && fact_levels[fact] < 0) {
                        fact_levels[fact] = level + 1;
                        changed = true;
                    }
            }
        if (!changed)
            break;
    }
    bool unreachable = false;
    for (int fact = 0; fact < ground->facts.count; ++fact)
        if (state_has(ground->goal, fact) && fact_levels[fact] < 0)
            unreachable = true;
    if (unreachable)
        out->lmcount = INFINITY_VALUE;
    else {
        out->landmarks = state_without(ground->goal, state);
        int verified[100];
        for (int i = 0; i < 100; ++i)
            verified[i] = -1;
        for (;;) {
            State previous = out->landmarks;
            for (int fact = 0; fact < ground->facts.count; ++fact)
                if (state_has(previous, fact)) {
                    State common = {0};
                    bool first = true;
                    for (int j = 0; j < achievers[fact].count; ++j) {
                        int index = achievers[fact].data[j];
                        if (action_levels[index] == fact_levels[fact] - 1) {
                            common = first ? ground->actions[index].pre
                                           : state_intersection(common, ground->actions[index].pre);
                            first = false;
                        }
                    }
                    common = state_without(common, state);
                    for (int candidate = 0; candidate < ground->facts.count; ++candidate)
                        if (state_has(common, candidate) && !state_has(out->landmarks, candidate)) {
                            if (verified[candidate] < 0)
                                verified[candidate] = !state_contains(
                                    reachable_without(ground, state, candidate), ground->goal);
                            if (verified[candidate])
                                state_put(&out->landmarks, candidate);
                        }
                }
            if (state_equal(previous, out->landmarks))
                break;
        }
        out->lmcount = state_count(out->landmarks);
    }
    for (int i = 0; i < ground->facts.count; ++i)
        int_free(&achievers[i]);
    if (ground->cache_count == ground->cache_capacity) {
        ground->cache_capacity = ground->cache_capacity ? ground->cache_capacity * 2 : 64;
        ground->cache =
            resize(ground->cache, (size_t)ground->cache_capacity * sizeof *ground->cache);
    }
    ground->cache_slots[slot] = ground->cache_count + 1;
    ground->cache[ground->cache_count++] = (HeuristicEntry){state, out};
    return out;
}
