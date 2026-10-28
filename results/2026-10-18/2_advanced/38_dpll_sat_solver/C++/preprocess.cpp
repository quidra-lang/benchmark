#include "sat.hpp"
int Preprocess::removed_count() const {
    return tautologies + unit_removed + subsumed + pure_removed;
}
Preprocess preprocess(const Formula &formula, bool pure) {
    Preprocess out;
    out.pure = pure;
    out.fixed.assign(formula.variables + 1, -1);
    for (std::size_t i = 0; i < formula.clauses.size(); ++i) {
        const Clause &clause = formula.clauses[i];
        std::set<int> literals(clause.begin(), clause.end());
        bool tautology = false;
        for (int literal : clause)
            if (literals.count(-literal))
                tautology = true;
        if (tautology) {
            ++out.tautologies;
            out.removed[0].push_back(i + 1);
            continue;
        }
        Clause normalized;
        std::set<int> seen;
        for (int literal : clause) {
            if (seen.insert(literal).second)
                normalized.push_back(literal);
            else
                ++out.duplicate_literals;
        }
        out.clauses.push_back({int(i + 1), normalized});
    }
    while (true) {
        int unit = 0;
        for (const WorkingClause &clause : out.clauses)
            if (clause.literals.empty()) {
                out.conflict = true;
                out.empty_clause = clause.id;
                return out;
            }
        for (const WorkingClause &clause : out.clauses)
            if (clause.literals.size() == 1) {
                unit = clause.literals[0];
                break;
            }
        if (unit == 0)
            break;
        out.fixed[std::abs(unit)] = unit > 0 ? 1 : 0;
        ++out.unit_fixed;
        std::vector<WorkingClause> remaining;
        for (const WorkingClause &clause : out.clauses) {
            if (std::find(clause.literals.begin(), clause.literals.end(), unit) != clause.literals.end()) {
                ++out.unit_removed;
                out.removed[1].push_back(clause.id);
            } else {
                WorkingClause next{clause.id, {}};
                for (int literal : clause.literals)
                    if (literal != -unit)
                        next.literals.push_back(literal);
                remaining.push_back(std::move(next));
            }
        }
        out.clauses = std::move(remaining);
    }
    std::vector<bool> remove(out.clauses.size());
    for (std::size_t b = 0; b < out.clauses.size(); ++b)
        for (std::size_t a = 0; a < out.clauses.size(); ++a) {
            if (a == b)
                continue;
            const Clause &first = out.clauses[a].literals, &second = out.clauses[b].literals;
            if (!(first.size() < second.size() || a < b))
                continue;
            bool contained = true;
            for (int literal : first)
                if (std::find(second.begin(), second.end(), literal) == second.end())
                    contained = false;
            if (contained) {
                remove[b] = true;
                break;
            }
        }
    std::vector<WorkingClause> remaining;
    for (std::size_t i = 0; i < out.clauses.size(); ++i) {
        if (remove[i]) {
            ++out.subsumed;
            out.removed[2].push_back(out.clauses[i].id);
        } else
            remaining.push_back(out.clauses[i]);
    }
    out.clauses = std::move(remaining);
    if (pure)
        while (true) {
            std::set<int> literals, pure_literals;
            for (const WorkingClause &clause : out.clauses)
                literals.insert(clause.literals.begin(), clause.literals.end());
            for (int literal : literals)
                if (!literals.count(-literal))
                    pure_literals.insert(literal);
            if (pure_literals.empty())
                break;
            for (int literal : pure_literals) {
                out.fixed[std::abs(literal)] = literal > 0 ? 1 : 0;
                ++out.pure_fixed;
            }
            remaining.clear();
            for (const WorkingClause &clause : out.clauses) {
                bool removed = false;
                for (int literal : clause.literals)
                    if (pure_literals.count(literal))
                        removed = true;
                if (removed) {
                    ++out.pure_removed;
                    out.removed[3].push_back(clause.id);
                } else
                    remaining.push_back(clause);
            }
            out.clauses = remaining;
        }
    return out;
}
