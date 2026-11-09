#include "simulation.h"
Ids *graph_edges(const Simulation *simulation) {
    Ids *out = allocate((size_t)simulation->event_count, sizeof(Ids));
    for (int i = 0; i < simulation->event_count; ++i) {
        Event event = simulation->events[i];
        Ids local = simulation->processes[event.process].events;
        if (event.local < local.count)
            append_id(&out[i], local.data[event.local]);
    }
    for (int i = 0; i < simulation->copy_count; ++i) {
        Copy copy = simulation->copies[i];
        if (copy.received >= 0)
            append_id(&out[simulation->messages[copy.message].send], copy.received);
    }
    return out;
}
Ids graph_path(int source, int target, const Ids *graph, int count) {
    int *parent = allocate((size_t)count, sizeof(int));
    for (int i = 0; i < count; ++i)
        parent[i] = -1;
    Ids queue = {0};
    append_id(&queue, source);
    parent[source] = source;
    int head = 0;
    while (head < queue.count && parent[target] < 0) {
        int current = queue.data[head++];
        for (int i = 0; i < graph[current].count; ++i) {
            int next = graph[current].data[i];
            if (parent[next] < 0) {
                parent[next] = current;
                append_id(&queue, next);
            }
        }
    }
    Ids out = {0};
    if (parent[target] < 0)
        return out;
    for (int cursor = target;; cursor = parent[cursor]) {
        append_id(&out, cursor);
        if (cursor == source)
            break;
    }
    for (int i = 0; i < out.count / 2; ++i) {
        int value = out.data[i];
        out.data[i] = out.data[out.count - 1 - i];
        out.data[out.count - 1 - i] = value;
    }
    return out;
}
Concurrency concurrency(const Simulation *simulation) {
    Concurrency out = {0};
    for (int i = 0; i < simulation->event_count; ++i)
        for (int j = i + 1; j < simulation->event_count; ++j) {
            Event a = simulation->events[i], b = simulation->events[j];
            if (relation(a.clock, b.clock, simulation->topology.count) == 0) {
                ++out.concurrent;
                out.same += a.lamport == b.lamport;
                int p = a.process < b.process ? a.process : b.process,
                    q = a.process > b.process ? a.process : b.process;
                ++out.pairs[p][q];
            } else
                ++out.ordered;
            if (a.time != b.time && a.lamport != b.lamport &&
                ((a.time < b.time) != (a.lamport < b.lamport)))
                ++out.inversions;
        }
    return out;
}
static void append_violation(Violation **data, int *count, int *capacity, Violation value) {
    if (*count == *capacity)
        grow((void **)data, capacity, sizeof(Violation));
    (*data)[(*count)++] = value;
}
Orders orders(const Simulation *simulation) {
    Orders out = {0};
    int count = simulation->topology.count;
    for (int p = 0; p < count; ++p) {
        Ids delivered = simulation->processes[p].delivered;
        for (int i = 0; i + 1 < delivered.count; ++i) {
            int a = delivered.data[i], b = delivered.data[i + 1];
            if (relation(
                    simulation->events[simulation->messages[simulation->copies[a].message].send]
                        .clock,
                    simulation->events[simulation->messages[simulation->copies[b].message].send]
                        .clock,
                    count) == 0)
                append_violation(&out.races, &out.race_count, &out.race_capacity,
                                 (Violation){p, a, b});
        }
        for (int i = 0; i < delivered.count; ++i)
            for (int j = i + 1; j < delivered.count; ++j) {
                int a = delivered.data[i], b = delivered.data[j];
                if (relation(
                        simulation->events[simulation->messages[simulation->copies[b].message].send]
                            .clock,
                        simulation->events[simulation->messages[simulation->copies[a].message].send]
                            .clock,
                        count) == 1) {
                    append_violation(&out.violations, &out.violation_count, &out.violation_capacity,
                                     (Violation){p, a, b});
                    out.fifo += simulation->copies[a].source == simulation->copies[b].source;
                }
            }
    }
    return out;
}
Enumeration enumerate_cuts(const Simulation *simulation) {
    Enumeration out = {0};
    out.product = 1;
    const int n = simulation->topology.count;
    I strides[6], initial = 0, level_max = 0;
    for (int p = n - 1; p >= 0; --p) {
        Process state = simulation->processes[p];
        for (int i = 0; i < state.events.count; ++i)
            out.limits[p] +=
                simulation->events[state.events.data[i]].time <= simulation->params->cutcount;
        strides[p] = out.product;
        out.product *= out.limits[p] + 1;
        level_max += out.limits[p];
        initial += state.initial;
    }
    out.level_count = (int)level_max + 1;
    out.levels = allocate((size_t)out.level_count, sizeof(I));
    out.predicates = allocate((size_t)simulation->params->predicate_count, sizeof(Predicate));
    bool *consistent = allocate((size_t)out.product, sizeof(bool));
    I *transit = allocate((size_t)out.product, sizeof(I));
    for (I index = 0; index < out.product; ++index) {
        I cut[6], level = 0, balance = 0;
        for (int p = 0; p < n; ++p) {
            cut[p] = index / strides[p] % (out.limits[p] + 1);
            level += cut[p];
            balance += balance_at_cut(simulation, p, cut[p]);
        }
        bool good = true;
        for (int p = 0; p < n; ++p)
            if (cut[p] > 0 &&
                !less_equal(
                    simulation->events[simulation->processes[p].events.data[cut[p] - 1]].clock, cut,
                    n))
                good = false;
        if (!good)
            continue;
        consistent[index] = true;
        ++out.consistent;
        ++out.levels[level];
        transit[index] = initial - balance;
        for (int t = 0; t < simulation->params->predicate_count; ++t)
            out.predicates[t].cuts += transit[index] >= simulation->params->predicates[t];
    }
    bool *reachable = allocate((size_t)out.product, sizeof(bool));
    for (int t = 0; t < simulation->params->predicate_count; ++t) {
        memset(reachable, 0, (size_t)out.product * sizeof(bool));
        for (I index = 0; index < out.product; ++index) {
            if (!consistent[index] || transit[index] >= simulation->params->predicates[t])
                continue;
            if (index == 0)
                reachable[0] = true;
            for (int p = 0; p < n && !reachable[index]; ++p)
                if (index / strides[p] % (out.limits[p] + 1) > 0 && reachable[index - strides[p]])
                    reachable[index] = true;
        }
        out.predicates[t].definite = !reachable[out.product - 1];
    }
    return out;
}
