#include <iostream>
#include <string>
#include <vector>
#include <array>
#include <algorithm>

void solve(const std::vector<std::string> &names, const std::vector<std::array<std::string, 2>> &edges,
    bool show_cycle) {
    int n = static_cast<int>(names.size());
    std::vector<std::vector<bool>> graph(n, std::vector<bool>(n));
    std::vector<int> indegree(n);
    std::vector<bool> taken(n);
    for (const std::array<std::string, 2> &e : edges) {
        int a = static_cast<int>(std::find(names.begin(), names.end(), e[0]) - names.begin()), b = static_cast<int>(std::find(names.begin(),
            names.end(), e[1]) - names.begin());
        graph[a][b] = true;
        ++indegree[b];
    }
    std::cout << "order: ";
    int count = 0;
    while (true) {
        int best = -1;
        for (int v = 0; v < n; v++)
            if (!taken[v] && !indegree[v] && (best < 0 || names[v] < names[best]))
                best = v;
        if (best < 0)
            break;
        if (count++)
            std::cout << " -> ";
        std::cout << names[best];
        taken[best] = true;
        for (int v = 0; v < n; v++)
            if (graph[best][v])
                --indegree[v];
    }
    std::cout << '\n';
    if (show_cycle) {
        std::vector<std::string> remaining;
        for (int v = 0; v < n; v++)
            if (!taken[v])
                remaining.push_back(names[v]);
        std::sort(remaining.begin(), remaining.end());
        std::cout << "cycle:";
        for (const std::string &name : remaining)
            std::cout << ' ' << name;
        std::cout << '\n';
    }
}

int main() {
    solve({"physics", "algebra", "graphics", "programming", "statistics", "calculus", "databases", "algorithms"}, {{"calculus", "physics"}, {"algebra", "calculus"}, {"programming", "algorithms"}, {"algebra",
        "statistics"}, {"algorithms", "databases"}, {"statistics", "databases"}, {"calculus", "graphics"},
        {"algorithms", "graphics"}, {"physics", "graphics"}}, false);
    solve({"music", "ecology", "art", "geology", "biology", "chemistry"}, {{"music", "art"}, {"art", "ecology"}, {"biology", "chemistry"}, {"chemistry", "ecology"}, {"ecology",
        "geology"}, {"geology", "chemistry"}}, true);
}
