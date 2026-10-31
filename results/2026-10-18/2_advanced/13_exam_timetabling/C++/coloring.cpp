#include "timetable.hpp"

Attempt::Attempt(const ConflictGraph& graph, Indices pending, int limit, std::function<Indices(int, const Assignment&)> candidates)
    : graph(graph), pending(std::move(pending)), limit(limit), candidates(std::move(candidates)) {}
int Attempt::saturation(int course, const Assignment& assignment) const {
    std::set<int> slots;
    for (int n : graph.vertices) if (graph.shared[course][n] && assignment[n]) slots.insert(assignment[n]);
    return static_cast<int>(slots.size());
}
bool Attempt::search(Assignment& assignment) {
    int chosen = -1, best = -1;
    for (int c : pending) if (!assignment[c]) {
        int value = saturation(c, assignment);
        if (chosen < 0 || value > best || (value == best &&
            (graph.degrees[c] > graph.degrees[chosen] || (graph.degrees[c] == graph.degrees[chosen] && c < chosen)))) { chosen = c; best = value; }
    }
    if (chosen < 0) return true;
    std::size_t depth = choices.size(); choices.push_back({chosen, 0, best});
    for (int slot : candidates(chosen, assignment)) {
        assignment[chosen] = slot; choices[depth].slot = slot;
        if (search(assignment)) return true;
        assignment[chosen] = 0;
        if (aborted) return false;
    }
    choices.pop_back(); ++deadEnds; deadEndCourse = chosen; aborted = deadEnds > limit;
    return false;
}
int greedyNumbering(const ConflictGraph& graph, const Indices& order) {
    Indices numbers(graph.shared.size()); int maximum = 0;
    for (int c : order) {
        std::set<int> taken;
        for (int n : graph.vertices) if (graph.shared[c][n] && numbers[n]) taken.insert(numbers[n]);
        int number = 1; while (taken.count(number)) ++number;
        numbers[c] = number; maximum = std::max(maximum, number);
    }
    return maximum;
}
