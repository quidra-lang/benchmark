#include <iostream>
#include <vector>
#include <array>
#include <algorithm>

struct Edge {
    char a, b;
    int weight;
};
int find(std::array<int, 8> &parent, int v) {
    if (parent[v] != v)
        parent[v] = find(parent, parent[v]);
    return parent[v];
}

int main() {
    std::vector<Edge> edges = {{'A', 'B', 7}, {'C', 'A', 4}, {'B', 'C', 9}, {'B', 'D', 14}, {'D', 'C',
        6}, {'C', 'E', 3}, {'E', 'D', 5}, {'F', 'D', 11}, {'E', 'G', 16}, {'G', 'F', 8}, {'H', 'F', 12},
        {'G', 'H', 2}, {'H', 'E', 10}};
    std::sort(edges.begin(), edges.end(), [](const Edge &a, const Edge &b) {
        return a.weight < b.weight;
    });
    std::array<int, 8> parent {};
    for (int i = 0; i < 8; i++)
        parent[i] = i;
    int accepted = 0, total = 0, skipped = 0;
    for (const Edge &e : edges) {
        if (accepted == 7)
            break;
        int a = find(parent, e.a - 'A'), b = find(parent, e.b - 'A');
        if (a == b) {
            ++skipped;
            continue;
        }
        parent[a] = b;
        ++accepted;
        total += e.weight;
        std::cout << std::min(e.a, e.b) << '-' << std::max(e.a, e.b) << ' ' << e.weight << '\n';
    }
    std::cout << "total weight: " << total << "\nskipped: " << skipped << '\n';
}
