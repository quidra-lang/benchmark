#include <iostream>
#include <vector>
#include <array>
#include <algorithm>

void dfs(int v, const std::array<std::array<bool, 9>, 9> &graph, std::array<bool, 9> &seen, std::vector<int> &order) {
    seen[v] = true;
    order.push_back(v);
    for (int w = 0; w < 9; w++)
        if (graph[v][w] && !seen[w])
            dfs(w, graph, seen, order);
}

int main() {
    std::array<std::array<bool, 9>, 9> graph {};
    const int edges[][2] = {{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}};
    for (const int(&e)[2] : edges)
        graph[e[0]][e[1]] = graph[e[1]][e[0]] = true;
    std::array<bool, 9> seen {};
    std::vector<int> order;
    dfs(0, graph, seen, order);
    std::cout << "DFS:";
    for (int v : order)
        std::cout << ' ' << v;
    std::cout << '\n';
    seen.fill(false);
    std::vector<int> queue = {0};
    seen[0] = true;
    std::cout << "BFS:";
    for (std::size_t head = 0; head < queue.size(); head++) {
        int v = queue[head];
        std::cout << ' ' << v;
        for (int w = 0; w < 9; w++)
            if (graph[v][w] && !seen[w]) {
                seen[w] = true;
                queue.push_back(w);
            }
    }
    std::cout << '\n';
    seen.fill(false);
    std::vector<std::vector<int>> components;
    for (int v = 0; v < 9; v++)
        if (!seen[v]) {
            std::vector<int> component;
            dfs(v, graph, seen, component);
            std::sort(component.begin(), component.end());
            components.push_back(component);
        }
    std::cout << "components: " << components.size() << '\n';
    for (std::size_t i = 0; i < components.size(); i++) {
        std::cout << "component " << i + 1 << ':';
        for (int v : components[i])
            std::cout << ' ' << v;
        std::cout << '\n';
    }
}
