#include "timetable.hpp"

ConflictGraph::ConflictGraph(const std::vector<Course>& courses, const std::vector<Student>& students)
    : shared(courses.size(), Indices(courses.size())), degrees(courses.size()) {
    for (int c = 0; c < static_cast<int>(courses.size()); ++c) if (courses[c].size()) vertices.push_back(c);
    for (const Student& student : students)
        for (std::size_t i = 0; i < student.courses.size(); ++i)
            for (std::size_t j = i + 1; j < student.courses.size(); ++j) {
                int a = student.courses[i], b = student.courses[j]; ++shared[a][b]; ++shared[b][a];
            }
    for (int c : vertices) for (int value : shared[c]) if (value) ++degrees[c];
}
std::vector<Indices> ConflictGraph::components() const {
    std::vector<Indices> result; std::set<int> seen;
    for (int c : vertices) {
        if (!seen.insert(c).second) continue;
        Indices component{c};
        for (std::size_t i = 0; i < component.size(); ++i)
            for (int n : vertices) if (shared[component[i]][n] && seen.insert(n).second) component.push_back(n);
        std::sort(component.begin(), component.end()); result.push_back(std::move(component));
    }
    std::sort(result.begin(), result.end(), [](const Indices& a, const Indices& b) { return a.size() != b.size() ? a.size() > b.size() : a.front() < b.front(); });
    return result;
}
Indices ConflictGraph::clique(Indices candidates) const {
    Indices result;
    while (!candidates.empty()) {
        int chosen = *std::min_element(candidates.begin(), candidates.end(), [&](int a, int b) { return degrees[a] != degrees[b] ? degrees[a] > degrees[b] : a < b; });
        result.push_back(chosen);
        candidates.erase(std::remove_if(candidates.begin(), candidates.end(), [&](int c) { return !shared[chosen][c]; }), candidates.end());
    }
    return result;
}
Indices ConflictGraph::kempeChain(const Assignment& assignment, int start, int home, int target) const {
    Indices chain{start}; std::set<int> seen{start};
    for (std::size_t i = 0; i < chain.size(); ++i)
        for (int n : vertices) if (shared[chain[i]][n] && (assignment[n] == home || assignment[n] == target) && seen.insert(n).second) chain.push_back(n);
    std::sort(chain.begin(), chain.end()); return chain;
}
bool reachable(const std::vector<std::pair<int, int>>& orders, int source, int target) {
    Indices stack{source}; std::set<int> seen{source};
    while (!stack.empty()) {
        int current = stack.back(); stack.pop_back(); if (current == target) return true;
        for (const std::pair<int, int>& order : orders)
            if (order.first == current && seen.insert(order.second).second) stack.push_back(order.second);
    }
    return false;
}
