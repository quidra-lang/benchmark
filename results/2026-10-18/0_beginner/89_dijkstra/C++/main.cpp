#include <iostream>
#include <vector>
#include <array>
#include <algorithm>

int main() {
    int graph[7][7] {};
    const int edges[][3] = {{0, 1, 7}, {0, 2, 3}, {0, 3, 9}, {1, 2, 2}, {2, 4, 6}, {1, 3, 3}, {3, 4,
        4}, {3, 5, 5}, {4, 5, 3}, {4, 6, 8}, {5, 6, 4}};
    for (const int(&e)[3] : edges)
        graph[e[0]][e[1]] = graph[e[1]][e[0]] = e[2];
    std::array<int, 7> distance, parent;
    std::array<bool, 7> done {};
    distance.fill(1000000);
    parent.fill(-1);
    distance[0] = 0;
    for (int step = 0; step < 7; step++) {
        int u = -1;
        for (int v = 0; v < 7; v++)
            if (!done[v] && (u < 0 || distance[v] < distance[u]))
                u = v;
        done[u] = true;
        for (int v = 0; v < 7; v++)
            if (graph[u][v] && distance[u] + graph[u][v] < distance[v]) {
                distance[v] = distance[u] + graph[u][v];
                parent[v] = u;
            }
    }
    for (int v = 0; v < 7; v++) {
        std::vector<int> path;
        for (int u = v; u >= 0; u = parent[u])
            path.push_back(u);
        std::reverse(path.begin(), path.end());
        std::cout << static_cast<char>('A' + v) << ": distance=" << distance[v] << " path=";
        for (std::size_t i = 0; i < path.size(); i++) {
            if (i)
                std::cout << '-';
            std::cout << static_cast<char>('A' + path[i]);
        }
        std::cout << '\n';
    }
}
