#include "sat.hpp"
void Statistics::add(const Statistics &other) {
    decisions += other.decisions;
    propagations += other.propagations;
    conflicts += other.conflicts;
    max_depth = std::max(max_depth, other.max_depth);
}
Round dpll_round(int variables, std::vector<Clause> clauses) {
    enum class Kind { decision, flip, propagation };
    struct Trail {
        int literal;
        Kind kind;
    };
    Round out;
    Model values(variables + 1, -1);
    std::vector<Trail> trail;
    std::size_t position = 0;
    std::vector<std::vector<int>> watches(2 * (variables + 1));
    auto watch_index = [](int literal) { return 2 * std::abs(literal) + (literal < 0 ? 1 : 0); };
    auto value = [&](int literal) {
        const int assigned = values[std::abs(literal)];
        return assigned < 0 ? -1 : literal > 0 ? assigned : 1 - assigned;
    };
    auto assign = [&](int literal, Kind kind) {
        values[std::abs(literal)] = literal > 0 ? 1 : 0;
        trail.push_back({literal, kind});
        out.events.push_back(std::string(kind == Kind::decision ? "D"
                                         : kind == Kind::flip   ? "F"
                                                                : "P") +
                             number(literal));
    };
    for (std::size_t i = 0; i < clauses.size(); ++i)
        if (clauses[i].size() >= 2) {
            watches[watch_index(clauses[i][0])].push_back(i);
            watches[watch_index(clauses[i][1])].push_back(i);
        }
    for (const Clause &clause : clauses) {
        if (clause.empty() || (clause.size() == 1 && value(clause[0]) == 0)) {
            ++out.stats.conflicts;
            out.events.push_back("C");
            return out;
        }
        if (clause.size() == 1 && value(clause[0]) < 0) {
            assign(clause[0], Kind::propagation);
            ++out.stats.propagations;
        }
    }
    while (true) {
        bool conflict = false;
        while (position < trail.size() && !conflict) {
            const int f = -trail[position++].literal;
            auto &watch = watches[watch_index(f)];
            std::size_t i = 0;
            while (i < watch.size()) {
                const int id = watch[i];
                Clause &clause = clauses[id];
                if (clause[0] == f)
                    std::swap(clause[0], clause[1]);
                if (value(clause[0]) == 1) {
                    ++i;
                    continue;
                }
                std::size_t replacement = 2;
                while (replacement < clause.size() && value(clause[replacement]) == 0)
                    ++replacement;
                if (replacement < clause.size()) {
                    std::swap(clause[1], clause[replacement]);
                    watch.erase(watch.begin() + i);
                    watches[watch_index(clause[1])].push_back(id);
                    continue;
                }
                if (value(clause[0]) == 0) {
                    ++out.stats.conflicts;
                    out.events.push_back("C");
                    conflict = true;
                    break;
                }
                if (value(clause[0]) < 0) {
                    assign(clause[0], Kind::propagation);
                    ++out.stats.propagations;
                }
                ++i;
            }
        }
        if (conflict) {
            while (!trail.empty() && trail.back().kind != Kind::decision) {
                values[std::abs(trail.back().literal)] = -1;
                trail.pop_back();
            }
            if (trail.empty())
                return out;
            const int literal = trail.back().literal;
            values[std::abs(literal)] = -1;
            trail.pop_back();
            position = trail.size();
            assign(-literal, Kind::flip);
            continue;
        }
        std::vector<std::array<int, 2>> counts(variables + 1);
        for (const Clause &clause : clauses) {
            bool satisfied = false;
            for (int literal : clause)
                if (value(literal) == 1)
                    satisfied = true;
            if (satisfied)
                continue;
            std::set<int> seen;
            for (int literal : clause)
                if (value(literal) < 0 && seen.insert(literal).second)
                    ++counts[std::abs(literal)][literal < 0 ? 1 : 0];
        }
        int selected = 0, greatest = 0;
        for (int x = 1; x <= variables; ++x)
            for (int negative = 0; negative < 2; ++negative)
                if (counts[x][negative] > greatest) {
                    greatest = counts[x][negative];
                    selected = negative ? -x : x;
                }
        if (selected == 0) {
            out.sat = true;
            out.values = values;
            for (int &assigned : out.values)
                if (assigned < 0)
                    assigned = 0;
            return out;
        }
        assign(selected, Kind::decision);
        ++out.stats.decisions;
        int depth = 0;
        for (const Trail &entry : trail)
            if (entry.kind != Kind::propagation)
                ++depth;
        out.stats.max_depth = std::max(out.stats.max_depth, depth);
    }
}
