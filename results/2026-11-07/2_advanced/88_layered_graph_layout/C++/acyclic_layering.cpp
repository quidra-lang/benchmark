#include "layout.hpp"
Order acyclic(int nodes, const std::vector<Edge> &edges) {
    std::vector<bool> remaining(nodes, true);
    Order head, tail;
    for (int count = 0; count < nodes; ++count) {
        Order incoming(nodes), outgoing(nodes);
        for (const Edge &edge : edges)
            if (remaining[edge.from] && remaining[edge.to]) {
                ++outgoing[edge.from];
                ++incoming[edge.to];
            }
        int chosen = -1;
        bool toTail = false;
        for (int v = 0; v < nodes; ++v)
            if (remaining[v] && !outgoing[v]) {
                chosen = v;
                toTail = true;
                break;
            }
        if (chosen < 0)
            for (int v = 0; v < nodes; ++v)
                if (remaining[v] && !incoming[v]) {
                    chosen = v;
                    break;
                }
        if (chosen < 0)
            for (int v = 0; v < nodes; ++v)
                if (remaining[v] &&
                    (chosen < 0 || outgoing[v] - incoming[v] > outgoing[chosen] - incoming[chosen]))
                    chosen = v;
        remaining[chosen] = false;
        if (toTail)
            tail.insert(tail.begin(), chosen);
        else
            head.push_back(chosen);
    }
    head.insert(head.end(), tail.begin(), tail.end());
    return head;
}
LayeringResult assignLayers(const Orders &predecessors, const Orders &successors,
                            const Settings &settings) {
    int nodes = static_cast<int>(predecessors.size());
    LayeringResult out;
    out.height.resize(nodes);
    out.labels.resize(nodes);
    if (!settings.coffman) {
        std::vector<bool> known(nodes);
        std::function<int(int)> height = [&](int v) {
            if (known[v])
                return out.height[v];
            for (int next : successors[v])
                out.height[v] = std::max(out.height[v], height(next) + 1);
            known[v] = true;
            return out.height[v];
        };
        for (int v = 0; v < nodes; ++v)
            height(v);
    } else {
        for (int label = 1; label <= nodes; ++label) {
            int chosen = -1;
            Order best;
            for (int v = 0; v < nodes; ++v)
                if (!out.labels[v]) {
                    bool ready = true;
                    Order key;
                    for (int previous : predecessors[v]) {
                        if (!out.labels[previous]) {
                            ready = false;
                            break;
                        }
                        key.push_back(out.labels[previous]);
                    }
                    if (!ready)
                        continue;
                    std::sort(key.begin(), key.end(), std::greater<int>());
                    if (chosen < 0 || key < best) {
                        chosen = v;
                        best = std::move(key);
                    }
                }
            out.labels[chosen] = label;
        }
        std::fill(out.height.begin(), out.height.end(), -1);
        int current = 0, count = 0;
        for (int k = 0; k < nodes; ++k) {
            int chosen = -1;
            for (int v = 0; v < nodes; ++v)
                if (out.height[v] < 0) {
                    bool ready = true;
                    for (int next : successors[v])
                        if (out.height[next] < 0)
                            ready = false;
                    if (ready && (chosen < 0 || out.labels[v] > out.labels[chosen]))
                        chosen = v;
                }
            bool next = count == settings.width;
            for (int successor : successors[chosen])
                if (out.height[successor] == current)
                    next = true;
            if (next) {
                ++current;
                count = 0;
            }
            out.height[chosen] = current;
            ++count;
        }
    }
    for (int v = 0; v < nodes; ++v)
        for (int next : successors[v])
            out.dummiesBefore += out.height[v] - out.height[next] - 1;
    if (settings.promotion) {
        std::function<int(int)> promote = [&](int v) {
            int difference = 0;
            for (int previous : predecessors[v])
                if (out.height[previous] == out.height[v] + 1)
                    difference += promote(previous);
            ++out.height[v];
            return difference + static_cast<int>(successors[v].size()) -
                   static_cast<int>(predecessors[v].size());
        };
        for (;;) {
            ++out.rounds;
            int accepted = 0;
            for (int v = 0; v < nodes; ++v)
                if (!predecessors[v].empty()) {
                    Order saved = out.height;
                    int difference = promote(v);
                    if (difference < 0) {
                        ++accepted;
                        out.promotions.push_back({out.rounds, v, difference});
                    } else
                        out.height = std::move(saved);
                }
            if (!accepted)
                break;
        }
    }
    return out;
}
