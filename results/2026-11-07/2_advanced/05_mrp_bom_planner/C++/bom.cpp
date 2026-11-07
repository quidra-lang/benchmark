#include "mrp.hpp"
#include <algorithm>

Integer Edge::need(Integer units) const { return (units * quantity * (100 + scrap) + 99) / 100; }
bool Bom::manufactured(const std::string& item) const { return !children.at(item).empty(); }
bool Bom::topLevel(const std::string& item) const { return manufactured(item) && parents.at(item).empty(); }
std::optional<Lines> Bom::path(const std::string& start, const std::string& goal, std::set<std::string>& visited) const {
    if (start == goal) return Lines{start}; visited.insert(start);
    for (const Edge& edge : children.at(start)) if (!visited.count(edge.child)) {
        auto rest = path(edge.child, goal, visited); if (rest) { rest->insert(rest->begin(), start); return rest; }
    }
    return std::nullopt;
}
int Bom::lowLevel(const std::string& item, std::map<std::string, int>& codes) const {
    if (codes.count(item)) return codes.at(item); int code = 0;
    for (const Edge& edge : parents.at(item)) code = std::max(code, lowLevel(edge.parent, codes) + 1);
    codes[item] = code; return code;
}
int Bom::cumulative(const std::string& item, const Items& items, std::map<std::string, int>& times) const {
    if (times.count(item)) return times.at(item); int longest = 0;
    for (const Edge& edge : children.at(item)) longest = std::max(longest, cumulative(edge.child, items, times));
    times[item] = items.at(item).lead + longest; return times.at(item);
}
Bom readBom(const Items& items, Lines& errors) {
    Bom bom; for (const auto& [id, item] : items) { bom.children[id] = {}; bom.parents[id] = {}; }
    for (const Row& row : readRows("bom.csv")) {
        const Lines& f = row.fields; Edge edge{f[0], f[1], std::stoll(f[2]), std::stoll(f[3])}; std::string error;
        if (!items.count(edge.parent)) error = "unknown item " + edge.parent;
        else if (!items.count(edge.child)) error = "unknown item " + edge.child;
        else if (edge.quantity < 1) error = "bad quantity " + f[2];
        else if (edge.scrap > 50) error = "bad scrap " + f[3];
        else if (edge.parent == edge.child) error = "cycle " + edge.parent + " -> " + edge.parent;
        else if (std::any_of(bom.children.at(edge.parent).begin(), bom.children.at(edge.parent).end(), [&](const Edge& old) { return old.child == edge.child; })) error = "duplicate " + edge.parent + " -> " + edge.child;
        else { std::set<std::string> visited; auto path = bom.path(edge.child, edge.parent, visited); if (path) error = "cycle " + edge.parent + " -> " + join(*path, " -> "); }
        if (!error.empty()) { inputError(errors, "bom.csv", row.line, error); continue; }
        auto& children = bom.children.at(edge.parent); children.push_back(edge); std::sort(children.begin(), children.end(), [](const Edge& a, const Edge& b) { return a.child < b.child; });
        auto& parents = bom.parents.at(edge.child); parents.push_back(edge); std::sort(parents.begin(), parents.end(), [](const Edge& a, const Edge& b) { return a.parent < b.parent; });
    }
    return bom;
}
