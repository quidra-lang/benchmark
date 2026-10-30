#include "planner.hpp"
bool State::has(int fact) const {
    return (words[fact / 64] & (std::uint64_t{1} << (fact % 64))) != 0;
}
void State::put(int fact) { words[fact / 64] |= std::uint64_t{1} << (fact % 64); }
State State::united(State other) const {
    for (int i = 0; i < 4; ++i)
        other.words[i] |= words[i];
    return other;
}
State State::without(State other) const {
    for (int i = 0; i < 4; ++i)
        other.words[i] = words[i] & ~other.words[i];
    return other;
}
State State::intersected(State other) const {
    for (int i = 0; i < 4; ++i)
        other.words[i] &= words[i];
    return other;
}
bool State::contains(State other) const {
    for (int i = 0; i < 4; ++i)
        if ((words[i] & other.words[i]) != other.words[i])
            return false;
    return true;
}
bool State::intersects(State other) const {
    for (int i = 0; i < 4; ++i)
        if (words[i] & other.words[i])
            return true;
    return false;
}
Plan State::numbers() const {
    Plan out;
    for (int i = 0; i < 256; ++i)
        if (has(i))
            out.push_back(i);
    return out;
}
bool Domain::subtype(std::string type, const std::string &expected) const {
    while (type != expected) {
        if (type == "object")
            return false;
        type = parents.at(type);
    }
    return true;
}
void Domain::classify() {
    fluent.clear();
    for (const Schema &schema : actions)
        for (const Literal &effect : schema.effects)
            fluent.insert(effect.atom.predicate);
}
Atom substitute(const Atom &atom, const std::map<std::string, std::string> &assignment) {
    Atom out{atom.predicate, {}};
    for (const std::string &term : atom.terms)
        out.terms.push_back(assignment.at(term));
    return out;
}
std::string GroundAction::text(const Domain &domain) const {
    return Atom{domain.actions[schema].name, arguments}.text();
}
std::map<std::string, std::string> objectTypes(const Problem &problem) {
    std::map<std::string, std::string> out;
    for (const Typed &object : problem.objects)
        out[object.name] = object.type;
    return out;
}
Lines objectsOfType(const Domain &domain, const Problem &problem, const std::string &type) {
    Lines out;
    for (const Typed &object : problem.objects)
        if (domain.subtype(object.type, type))
            out.push_back(object.name);
    return out;
}
static bool containsAtoms(const AtomSet &set, const AtomSet &required) {
    for (const auto &entry : required)
        if (!set.count(entry.first))
            return false;
    return true;
}
struct Candidate {
    int schema;
    Lines arguments;
    AtomSet pre, neg, add, del;
    bool reachable = false;
};
GroundProblem ground(const Domain &domain, const Problem &problem) {
    GroundProblem out;
    out.domain = &domain;
    out.problem = &problem;
    out.counts.resize(domain.actions.size());
    AtomSet initial, reachable;
    for (const Atom &atom : problem.initial) {
        initial[atom.text()] = atom;
        if (domain.fluent.count(atom.predicate))
            reachable[atom.text()] = atom;
        else
            ++out.staticFacts;
    }
    std::vector<Candidate> candidates;
    for (std::size_t index = 0; index < domain.actions.size(); ++index) {
        const Schema &schema = domain.actions[index];
        SchemaCount &count = out.counts[index];
        std::vector<Lines> choices;
        for (const Typed &parameter : schema.parameters) {
            choices.push_back(objectsOfType(domain, problem, parameter.type));
            count.assignments *= static_cast<int>(choices.back().size());
        }
        std::map<std::string, std::string> assignment;
        Lines arguments(schema.parameters.size());
        std::function<void(std::size_t)> enumerate = [&](std::size_t at) {
            if (at < schema.parameters.size()) {
                for (const std::string &object : choices[at]) {
                    arguments[at] = object;
                    assignment[schema.parameters[at].name] = object;
                    enumerate(at + 1);
                }
                return;
            }
            Candidate candidate{static_cast<int>(index), arguments, {}, {}, {}, {}, false};
            for (const Literal &literal : schema.conditions) {
                Atom atom = substitute(literal.atom, assignment);
                if (atom.predicate == "=" || !domain.fluent.count(atom.predicate)) {
                    bool truth = atom.predicate == "=" ? atom.terms[0] == atom.terms[1]
                                                       : initial.count(atom.text()) != 0;
                    if (truth == literal.negative)
                        return;
                } else if (literal.negative)
                    candidate.neg[atom.text()] = atom;
                else
                    candidate.pre[atom.text()] = atom;
            }
            for (const Literal &literal : schema.effects) {
                Atom atom = substitute(literal.atom, assignment);
                (literal.negative ? candidate.del : candidate.add)[atom.text()] = atom;
            }
            for (const auto &entry : candidate.add)
                candidate.del.erase(entry.first);
            candidates.push_back(std::move(candidate));
            ++count.candidates;
        };
        enumerate(0);
    }
    out.candidateCount = static_cast<int>(candidates.size());
    bool changed = true;
    while (changed) {
        changed = false;
        for (Candidate &candidate : candidates)
            if (!candidate.reachable && containsAtoms(reachable, candidate.pre)) {
                candidate.reachable = true;
                changed = true;
                reachable.insert(candidate.add.begin(), candidate.add.end());
            }
    }
    for (const auto &entry : reachable)
        out.facts.push_back(entry.second);
    std::map<std::string, int> objectNumber;
    for (std::size_t i = 0; i < problem.objects.size(); ++i)
        objectNumber[problem.objects[i].name] = static_cast<int>(i);
    std::sort(out.facts.begin(), out.facts.end(), [&](const Atom &a, const Atom &b) {
        int ap = domain.predicateIndex.at(a.predicate), bp = domain.predicateIndex.at(b.predicate);
        if (ap != bp)
            return ap < bp;
        Plan left, right;
        for (const std::string &term : a.terms)
            left.push_back(objectNumber.at(term));
        for (const std::string &term : b.terms)
            right.push_back(objectNumber.at(term));
        return left < right;
    });
    for (std::size_t i = 0; i < out.facts.size(); ++i)
        out.factIndex[out.facts[i].text()] = static_cast<int>(i);
    const auto toState = [&](const AtomSet &atoms) {
        State state;
        for (const auto &entry : atoms) {
            auto found = out.factIndex.find(entry.first);
            if (found != out.factIndex.end())
                state.put(found->second);
        }
        return state;
    };
    out.initial = toState(initial);
    for (const Candidate &candidate : candidates)
        if (candidate.reachable) {
            out.actions.push_back({candidate.schema, candidate.arguments,
                                   domain.actions[candidate.schema].cost, toState(candidate.pre),
                                   toState(candidate.neg), toState(candidate.add),
                                   toState(candidate.del)});
            ++out.counts[candidate.schema].reachable;
        }
    for (const Atom &atom : problem.goals) {
        auto found = out.factIndex.find(atom.text());
        if (found != out.factIndex.end())
            out.goal.put(found->second);
        else if (domain.fluent.count(atom.predicate) || !initial.count(atom.text()))
            out.unreachable.push_back(atom);
    }
    return out;
}
