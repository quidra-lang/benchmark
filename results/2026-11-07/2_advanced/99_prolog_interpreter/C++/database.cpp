#include "prolog.hpp"
namespace prolog {
    std::pair<Term, Term> Clause::copy() const {std::vector<Term> terms = copy_terms({head, body});
    return {terms[0], terms[1]};
    } void Database::add(const Clause& clause) {
        Indicator key = indicator(clause.head);
        if (!predicates.count(key)) order.push_back(key);
        predicates[key].push_back(clause);
    }
    std::vector<const Clause*> Database::candidates(const Term& goal) const {Indicator key = indicator(goal);
    std::vector<const Clause*> result;
    for (const Clause& clause : predicates.at(key)) if (key.second == 0 || same_kind(dereference(goal)->args[0], dereference(clause.head)->args[0])) result.push_back(&clause);
    return result;
    }
}
