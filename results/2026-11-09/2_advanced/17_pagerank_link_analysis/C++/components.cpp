#include "analysis.hpp"

Adjacency strongComponents(const Adjacency& adjacency) {
    int count = static_cast<int>(adjacency.size()), counter = 0;
    Nodes order(count, -1), low(count), stack;
    std::vector<bool> onStack(count);
    Adjacency groups;
    for (int root = 0; root < count; ++root) {
        if (order[root] >= 0) continue;
        order[root] = low[root] = counter++;
        stack.push_back(root);
        onStack[root] = true;
        std::vector<std::pair<int, std::size_t>> work{{root, 0}};
        while (!work.empty()) {
            int node = work.back().first;
            std::size_t position = work.back().second;
            if (position < adjacency[node].size()) {
                ++work.back().second;
                int child = adjacency[node][position];
                if (order[child] < 0) {
                    order[child] = low[child] = counter++;
                    stack.push_back(child);
                    onStack[child] = true;
                    work.emplace_back(child, 0);
                } else if (onStack[child]) low[node] = std::min(low[node], order[child]);
                continue;
            }
            work.pop_back();
            if (!work.empty()) low[work.back().first] = std::min(low[work.back().first], low[node]);
            if (low[node] == order[node]) {
                Nodes group;
                while (true) { int member = stack.back(); stack.pop_back(); onStack[member] = false; group.push_back(member); if (member == node) break; }
                groups.push_back(std::move(group));
            }
        }
    }
    return groups;
}
std::vector<bool> reachable(const Adjacency& adjacency, const Nodes& starts) {
    std::vector<bool> seen(adjacency.size());
    Nodes stack;
    for (int node : starts) if (!seen[node]) { seen[node] = true; stack.push_back(node); }
    while (!stack.empty()) {
        int node = stack.back(); stack.pop_back();
        for (int child : adjacency[node]) if (!seen[child]) { seen[child] = true; stack.push_back(child); }
    }
    return seen;
}
Nodes bfsDistances(const Adjacency& adjacency, const Nodes& starts) {
    Nodes distances(adjacency.size(), -1), queue;
    for (int node : starts) if (distances[node] < 0) { distances[node] = 0; queue.push_back(node); }
    for (std::size_t head = 0; head < queue.size(); ++head) {
        int node = queue[head];
        for (int child : adjacency[node]) if (distances[child] < 0) { distances[child] = distances[node] + 1; queue.push_back(child); }
    }
    return distances;
}
Nodes weakComponents(const Adjacency& adjacency) {
    Nodes labels(adjacency.size(), -1);
    int number = 0;
    for (int root = 0; root < static_cast<int>(adjacency.size()); ++root) {
        if (labels[root] >= 0) continue;
        labels[root] = number;
        Nodes stack{root};
        while (!stack.empty()) {
            int node = stack.back(); stack.pop_back();
            for (int child : adjacency[node]) if (labels[child] < 0) { labels[child] = number; stack.push_back(child); }
        }
        ++number;
    }
    return labels;
}
