#include "simulation.hpp"
Graph graph_edges(const std::deque<Event> &events, const std::deque<Copy> &copies,
                  const std::deque<Message> &messages, const std::vector<Process> &processes) {
    Graph out(events.size());
    for (int i = 0; i < int(events.size()); ++i) {
        const Event &event = events[i];
        if (event.local < int(processes[event.process].events.size()))
            out[i].push_back(processes[event.process].events[event.local]);
    }
    for (const Copy &copy : copies)
        if (copy.received >= 0)
            out[messages[copy.message].send].push_back(copy.received);
    return out;
}
Ids graph_path(int source, int target, const Graph &graph) {
    Ids parent(graph.size(), -1);
    std::queue<int> pending;
    pending.push(source);
    parent[source] = source;
    while (!pending.empty() && parent[target] < 0) {
        int current = pending.front();
        pending.pop();
        for (int next : graph[current])
            if (parent[next] < 0) {
                parent[next] = current;
                pending.push(next);
            }
    }
    if (parent[target] < 0)
        return {};
    Ids path;
    for (int cursor = target;; cursor = parent[cursor]) {
        path.push_back(cursor);
        if (cursor == source)
            break;
    }
    std::reverse(path.begin(), path.end());
    return path;
}
Concurrency concurrency(const std::deque<Event> &events, int count) {
    Concurrency out;
    out.pairs.assign(count, Vector(count));
    for (int i = 0; i < int(events.size()); ++i)
        for (int j = i + 1; j < int(events.size()); ++j) {
            const Event &a = events[i], &b = events[j];
            if (relation(a.clock, b.clock) == 0) {
                ++out.concurrent;
                out.same += a.lamport == b.lamport;
                ++out.pairs[std::min(a.process, b.process)][std::max(a.process, b.process)];
            } else
                ++out.ordered;
            if (a.time != b.time && a.lamport != b.lamport &&
                ((a.time < b.time) != (a.lamport < b.lamport)))
                ++out.inversions;
        }
    return out;
}
Orders orders(const std::vector<Process> &processes, const std::deque<Copy> &copies,
              const std::deque<Message> &messages, const std::deque<Event> &events) {
    Orders out;
    for (int p = 0; p < int(processes.size()); ++p) {
        const Ids &delivered = processes[p].delivered;
        for (int i = 0; i + 1 < int(delivered.size()); ++i) {
            int a = delivered[i], b = delivered[i + 1];
            if (relation(events[messages[copies[a].message].send].clock,
                         events[messages[copies[b].message].send].clock) == 0)
                out.races.push_back({p, a, b});
        }
        for (int i = 0; i < int(delivered.size()); ++i)
            for (int j = i + 1; j < int(delivered.size()); ++j) {
                int a = delivered[i], b = delivered[j];
                if (before(events[messages[copies[b].message].send].clock,
                           events[messages[copies[a].message].send].clock)) {
                    out.violations.push_back({p, a, b});
                    out.fifo += copies[a].source == copies[b].source;
                }
            }
    }
    return out;
}
Enumeration enumerate(const std::vector<Process> &processes, const std::deque<Event> &events,
                      int time, const Vector &thresholds) {
    const int n = int(processes.size());
    Enumeration out;
    out.limits.resize(n);
    Vector strides(n);
    I level_max = 0, initial = 0;
    for (int p = n - 1; p >= 0; --p) {
        for (int index : processes[p].events)
            out.limits[p] += events[index].time <= time;
        strides[p] = out.product;
        out.product *= out.limits[p] + 1;
        level_max += out.limits[p];
        initial += processes[p].initial;
    }
    out.levels.resize(std::size_t(level_max + 1));
    out.predicates.resize(thresholds.size());
    std::vector<bool> consistent(std::size_t(out.product));
    Vector transit(std::size_t(out.product), 0);
    for (I index = 0; index < out.product; ++index) {
        Vector cut(n);
        I level = 0, balance = 0;
        for (int p = 0; p < n; ++p) {
            cut[p] = index / strides[p] % (out.limits[p] + 1);
            level += cut[p];
            balance += balance_at_cut(processes[p], events, cut[p]);
        }
        bool good = true;
        for (int p = 0; p < n; ++p)
            if (cut[p] > 0 &&
                !less_equal(events[processes[p].events[std::size_t(cut[p] - 1)]].clock, cut))
                good = false;
        if (!good)
            continue;
        consistent[std::size_t(index)] = true;
        ++out.consistent;
        ++out.levels[std::size_t(level)];
        transit[std::size_t(index)] = initial - balance;
        for (int t = 0; t < int(thresholds.size()); ++t)
            out.predicates[t].cuts += transit[std::size_t(index)] >= thresholds[t];
    }
    for (int t = 0; t < int(thresholds.size()); ++t) {
        std::vector<bool> reachable(std::size_t(out.product));
        for (I index = 0; index < out.product; ++index) {
            if (!consistent[std::size_t(index)] || transit[std::size_t(index)] >= thresholds[t])
                continue;
            if (index == 0)
                reachable[0] = true;
            for (int p = 0; p < n && !reachable[std::size_t(index)]; ++p)
                if (index / strides[p] % (out.limits[p] + 1) > 0 &&
                    reachable[std::size_t(index - strides[p])])
                    reachable[std::size_t(index)] = true;
        }
        out.predicates[t].definite = !reachable.back();
    }
    return out;
}
