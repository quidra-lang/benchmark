#include "parser.h"
int terminal_index(const Table *table, const char *name) {
    for (int i = 0; i < table->terminals.n; ++i)
        if (strcmp(table->terminals.v[i], name) == 0)
            return i;
    return -1;
}
Table build_table(const Grammar *grammar, const Sets *sets) {
    Table out = {.grammar = grammar};
    for (int a = 0; a < grammar->n; ++a) {
        const Alternatives values = grammar->v[a].alternatives;
        for (int i = 0; i < values.n; ++i) {
            if (out.nproductions == out.capacity) {
                const int capacity = out.capacity ? out.capacity * 2 : 16;
                out.productions = grow(out.productions, (size_t)out.nproductions * sizeof *out.productions,
                                       (size_t)capacity * sizeof *out.productions);
                out.capacity = capacity;
            }
            out.productions[out.nproductions++] = (Production){a, values.v[i]};
            for (int j = 0; j < values.v[i].n; ++j)
                if (!nonterminal(values.v[i].v[j]))
                    strings_unique(&out.terminals, values.v[i].v[j]);
        }
    }
    strings_unique(&out.terminals, "$");
    terminal_sort(out.terminals);
    out.predict = allocate((size_t)out.nproductions * sizeof *out.predict);
    out.first = allocate((size_t)out.nproductions * sizeof *out.first);
    const int cells = grammar->n * out.terminals.n;
    out.cells = allocate((size_t)cells * sizeof *out.cells);
    out.chosen = allocate((size_t)cells * sizeof *out.chosen);
    for (int i = 0; i < cells; ++i)
        out.chosen[i] = -1;
    for (int p = 0; p < out.nproductions; ++p) {
        const Production production = out.productions[p];
        const First first = first_sequence(production.rhs, sets);
        out.first[p] = first.terminals;
        out.predict[p] = strings_slice(first.terminals, 0, first.terminals.n);
        if (first.nullable)
            for (int j = 0; j < sets->follow[production.lhs].n; ++j)
                strings_unique(&out.predict[p], sets->follow[production.lhs].v[j]);
        for (int j = 0; j < out.predict[p].n; ++j) {
            const int terminal = terminal_index(&out, out.predict[p].v[j]);
            ints_add(&out.cells[production.lhs * out.terminals.n + terminal], p);
        }
    }
    for (int a = 0; a < grammar->n; ++a)
        for (int t = 0; t < out.terminals.n; ++t) {
            const int index = a * out.terminals.n + t;
            const Ints cell = out.cells[index];
            if (!cell.n)
                continue;
            if (cell.n > 1)
                ++out.conflicts;
            int chosen = cell.v[0];
            for (int i = 0; i < cell.n; ++i)
                if (strings_has(out.first[cell.v[i]], out.terminals.v[t])) {
                    chosen = cell.v[i];
                    break;
                }
            out.chosen[index] = chosen;
        }
    return out;
}
const char *reason(const Table *table, int production, const char *terminal) {
    return strings_has(table->first[production], terminal) ? "FIRST" : "FOLLOW";
}
const char *conflict_kind(const Table *table, Ints cell, const char *terminal) {
    int first = 0;
    for (int i = 0; i < cell.n; ++i)
        first += strings_has(table->first[cell.v[i]], terminal);
    return first == cell.n ? "FIRST/FIRST" : first == 0 ? "FOLLOW/FOLLOW" : "FIRST/FOLLOW";
}
