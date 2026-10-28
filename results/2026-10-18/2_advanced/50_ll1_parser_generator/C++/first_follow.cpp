#include "parser.hpp"
std::pair<Terminals, bool> first_sequence(const Sequence &sequence, const Sets &sets) {
    Terminals out;
    for (const std::string &symbol : sequence) {
        if (!nonterminal(symbol)) {
            out.insert(symbol);
            return {out, false};
        }
        const auto &first = sets.first.at(symbol);
        out.insert(first.begin(), first.end());
        if (!sets.nullable.at(symbol))
            return {out, false};
    }
    return {out, true};
}
static bool unite(Terminals &target, const Terminals &source) {
    bool changed = false;
    for (const std::string &value : source)
        changed = target.insert(value).second || changed;
    return changed;
}
Sets first_follow(const Grammar &grammar) {
    Sets out;
    for (const std::string &name : grammar.order) {
        out.nullable[name] = false;
        out.first[name] = {};
        out.follow[name] = {};
    }
    bool changed;
    do {
        changed = false;
        ++out.nullable_passes;
        for (const std::string &name : grammar.order)
            for (const Sequence &alternative : grammar.rules.at(name)) {
                bool nullable = true;
                for (const std::string &symbol : alternative)
                    if (!nonterminal(symbol) || !out.nullable[symbol]) {
                        nullable = false;
                        break;
                    }
                if (nullable && !out.nullable[name]) {
                    out.nullable[name] = true;
                    changed = true;
                }
            }
    } while (changed);
    do {
        changed = false;
        ++out.first_passes;
        for (const std::string &name : grammar.order)
            for (const Sequence &alternative : grammar.rules.at(name))
                changed = unite(out.first[name], first_sequence(alternative, out).first) || changed;
    } while (changed);
    out.follow[grammar.start].insert("$");
    do {
        changed = false;
        ++out.follow_passes;
        for (const std::string &name : grammar.order)
            for (const Sequence &alternative : grammar.rules.at(name))
                for (std::size_t i = 0; i < alternative.size(); ++i)
                    if (nonterminal(alternative[i])) {
                        const Sequence suffix(alternative.begin() + i + 1, alternative.end());
                        const auto first = first_sequence(suffix, out);
                        changed = unite(out.follow[alternative[i]], first.first) || changed;
                        if (first.second)
                            changed = unite(out.follow[alternative[i]], out.follow[name]) || changed;
                    }
    } while (changed);
    return out;
}
