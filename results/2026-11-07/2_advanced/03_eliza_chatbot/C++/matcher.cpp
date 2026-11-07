#include "eliza.hpp"
#include <algorithm>
#include <functional>

bool wildcard(const std::string& e) { return e == "*" || e == "#" || e.front() == '@'; }
std::optional<Clauses> match(const Words& pattern, const Words& text, const Groups& groups) {
    Clauses bindings;
    std::function<bool(std::size_t, std::size_t)> visit = [&](std::size_t p, std::size_t start) {
        if (p == pattern.size()) return start == text.size();
        const std::string& e = pattern[p];
        std::size_t low = start, high = text.size();
        if (e != "*") {
            if (start == text.size()) return false;
            bool fits = e == "#" || e == text[start];
            if (e.front() == '@') { auto g = groups.find(e.substr(1)); fits = g != groups.end() && g->second.count(text[start]); }
            if (!fits) return false;
            low = high = start + 1;
        }
        for (std::size_t end = low; end <= high; ++end) {
            if (wildcard(e)) bindings.emplace_back(text.begin() + start, text.begin() + end);
            if (visit(p + 1, end)) return true;
            if (wildcard(e)) bindings.pop_back();
        }
        return false;
    };
    if (visit(0, 0)) return bindings;
    return std::nullopt;
}
bool covers(const Words& earlier, const Words& later, const Groups& groups) {
    auto one = [&](const std::string& a, const std::string& b) {
        if (a == "#") return b != "*";
        if (a.front() != '@') return a == b;
        const auto& members = groups.at(a.substr(1));
        if (b.front() != '@') return members.count(b) != 0;
        const auto& others = groups.at(b.substr(1));
        return std::includes(members.begin(), members.end(), others.begin(), others.end());
    };
    std::function<bool(std::size_t, std::size_t)> visit = [&](std::size_t p, std::size_t start) {
        if (p == earlier.size()) return start == later.size();
        if (earlier[p] == "*") {
            for (std::size_t end = start; end <= later.size(); ++end) if (visit(p + 1, end)) return true;
            return false;
        }
        return start < later.size() && one(earlier[p], later[start]) && visit(p + 1, start + 1);
    };
    return visit(0, 0);
}
