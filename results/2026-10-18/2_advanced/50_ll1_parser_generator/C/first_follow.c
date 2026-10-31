#include "parser.h"
First first_sequence(Strings sequence, const Sets *sets) {
    First out = {.nullable = true};
    for (int i = 0; i < sequence.n; ++i) {
        const char *symbol = sequence.v[i];
        if (!nonterminal(symbol)) {
            strings_unique(&out.terminals, symbol);
            out.nullable = false;
            return out;
        }
        const int index = rule_index(sets->grammar, symbol);
        const Strings first = sets->first[index];
        for (int j = 0; j < first.n; ++j)
            strings_unique(&out.terminals, first.v[j]);
        if (!sets->nullable[index]) {
            out.nullable = false;
            return out;
        }
    }
    return out;
}
static bool unite(Strings *target, Strings source) {
    bool changed = false;
    for (int i = 0; i < source.n; ++i)
        changed = strings_unique(target, source.v[i]) || changed;
    return changed;
}
Sets first_follow(const Grammar *grammar) {
    Sets out = {.grammar = grammar};
    out.nullable = allocate((size_t)grammar->n * sizeof *out.nullable);
    out.first = allocate((size_t)grammar->n * sizeof *out.first);
    out.follow = allocate((size_t)grammar->n * sizeof *out.follow);
    bool changed;
    do {
        changed = false;
        ++out.nullable_passes;
        for (int a = 0; a < grammar->n; ++a) {
            const Alternatives values = grammar->v[a].alternatives;
            for (int i = 0; i < values.n; ++i) {
                const Strings rhs = values.v[i];
                bool nullable = true;
                for (int j = 0; j < rhs.n; ++j)
                    if (!nonterminal(rhs.v[j]) || !out.nullable[rule_index(grammar, rhs.v[j])]) {
                        nullable = false;
                        break;
                    }
                if (nullable && !out.nullable[a]) {
                    out.nullable[a] = true;
                    changed = true;
                }
            }
        }
    } while (changed);
    do {
        changed = false;
        ++out.first_passes;
        for (int a = 0; a < grammar->n; ++a) {
            const Alternatives values = grammar->v[a].alternatives;
            for (int i = 0; i < values.n; ++i) {
                const First first = first_sequence(values.v[i], &out);
                changed = unite(&out.first[a], first.terminals) || changed;
            }
        }
    } while (changed);
    strings_unique(&out.follow[rule_index(grammar, grammar->start)], "$");
    do {
        changed = false;
        ++out.follow_passes;
        for (int a = 0; a < grammar->n; ++a) {
            const Alternatives values = grammar->v[a].alternatives;
            for (int i = 0; i < values.n; ++i) {
                const Strings rhs = values.v[i];
                for (int j = 0; j < rhs.n; ++j)
                    if (nonterminal(rhs.v[j])) {
                        const int b = rule_index(grammar, rhs.v[j]);
                        const First first = first_sequence(strings_slice(rhs, j + 1, rhs.n), &out);
                        changed = unite(&out.follow[b], first.terminals) || changed;
                        if (first.nullable)
                            changed = unite(&out.follow[b], out.follow[a]) || changed;
                    }
            }
        }
    } while (changed);
    return out;
}
