#include "sat.h"
void stats_add(Statistics *target, const Statistics *source) {
    target->decisions += source->decisions;
    target->propagations += source->propagations;
    target->conflicts += source->conflicts;
    if (source->max_depth > target->max_depth)
        target->max_depth = source->max_depth;
}
typedef enum { DECISION, FLIP, PROPAGATION } Kind;
typedef struct {
    int literal;
    Kind kind;
} Trail;
typedef struct {
    Model values;
    Trail trail[201];
    int count, position;
    IntList watches[402];
    Round out;
} Search;
static int watch_index(int literal) {
    return 2 * abs(literal) + (literal < 0);
}
static int value(const Search *search, int literal) {
    int assigned = search->values.values[abs(literal)];
    return assigned < 0 ? -1 : literal > 0 ? assigned : 1 - assigned;
}
static void assign(Search *search, int literal, Kind kind) {
    search->values.values[abs(literal)] = literal > 0;
    search->trail[search->count++] = (Trail){literal, kind};
    line_push(&search->out.events, format("%c%d",
                                          kind == DECISION ? 'D'
                                          : kind == FLIP   ? 'F'
                                                           : 'P',
                                          literal));
}
static Round finish(Search *search, Formula *formula) {
    Round out = search->out;
    for (int i = 0; i < 402; ++i)
        int_free(&search->watches[i]);
    formula_free(formula);
    return out;
}
Round dpll_round(const Formula *received) {
    Formula formula = formula_copy(received);
    Search search = {0};
    for (int x = 0; x <= 200; ++x)
        search.values.values[x] = -1;
    for (int i = 0; i < formula.count; ++i)
        if (formula.clauses[i].count >= 2) {
            int_push(&search.watches[watch_index(formula.clauses[i].data[0])], i);
            int_push(&search.watches[watch_index(formula.clauses[i].data[1])], i);
        }
    for (int i = 0; i < formula.count; ++i) {
        Clause *clause = &formula.clauses[i];
        if (!clause->count || (clause->count == 1 && value(&search, clause->data[0]) == 0)) {
            ++search.out.stats.conflicts;
            line_push(&search.out.events, text("C"));
            return finish(&search, &formula);
        }
        if (clause->count == 1 && value(&search, clause->data[0]) < 0) {
            assign(&search, clause->data[0], PROPAGATION);
            ++search.out.stats.propagations;
        }
    }
    while (true) {
        bool conflict = false;
        while (search.position < search.count && !conflict) {
            int f = -search.trail[search.position++].literal;
            IntList *watch = &search.watches[watch_index(f)];
            int i = 0;
            while (i < watch->count) {
                int id = watch->data[i];
                Clause *clause = &formula.clauses[id];
                if (clause->data[0] == f) {
                    int temporary = clause->data[0];
                    clause->data[0] = clause->data[1];
                    clause->data[1] = temporary;
                }
                if (value(&search, clause->data[0]) == 1) {
                    ++i;
                    continue;
                }
                int replacement = 2;
                while (replacement < clause->count && value(&search, clause->data[replacement]) == 0)
                    ++replacement;
                if (replacement < clause->count) {
                    int temporary = clause->data[1];
                    clause->data[1] = clause->data[replacement];
                    clause->data[replacement] = temporary;
                    memmove(watch->data + i, watch->data + i + 1,
                            (size_t)(watch->count - i - 1) * sizeof(int));
                    --watch->count;
                    int_push(&search.watches[watch_index(clause->data[1])], id);
                    continue;
                }
                if (value(&search, clause->data[0]) == 0) {
                    ++search.out.stats.conflicts;
                    line_push(&search.out.events, text("C"));
                    conflict = true;
                    break;
                }
                if (value(&search, clause->data[0]) < 0) {
                    assign(&search, clause->data[0], PROPAGATION);
                    ++search.out.stats.propagations;
                }
                ++i;
            }
        }
        if (conflict) {
            while (search.count && search.trail[search.count - 1].kind != DECISION)
                search.values.values[abs(search.trail[--search.count].literal)] = -1;
            if (!search.count)
                return finish(&search, &formula);
            int literal = search.trail[--search.count].literal;
            search.values.values[abs(literal)] = -1;
            search.position = search.count;
            assign(&search, -literal, FLIP);
            continue;
        }
        int counts[201][2] = {{0}};
        for (int i = 0; i < formula.count; ++i) {
            Clause *clause = &formula.clauses[i];
            bool satisfied = false, seen[401] = {0};
            for (int j = 0; j < clause->count; ++j)
                if (value(&search, clause->data[j]) == 1)
                    satisfied = true;
            if (satisfied)
                continue;
            for (int j = 0; j < clause->count; ++j) {
                int literal = clause->data[j];
                if (value(&search, literal) < 0 && !seen[literal + 200]) {
                    ++counts[abs(literal)][literal < 0];
                    seen[literal + 200] = true;
                }
            }
        }
        int selected = 0, greatest = 0;
        for (int x = 1; x <= formula.variables; ++x)
            for (int negative = 0; negative < 2; ++negative)
                if (counts[x][negative] > greatest) {
                    greatest = counts[x][negative];
                    selected = negative ? -x : x;
                }
        if (!selected) {
            search.out.sat = true;
            search.out.values = search.values;
            for (int x = 0; x <= 200; ++x)
                if (search.out.values.values[x] < 0)
                    search.out.values.values[x] = 0;
            return finish(&search, &formula);
        }
        assign(&search, selected, DECISION);
        ++search.out.stats.decisions;
        int depth = 0;
        for (int i = 0; i < search.count; ++i)
            if (search.trail[i].kind != PROPAGATION)
                ++depth;
        if (depth > search.out.stats.max_depth)
            search.out.stats.max_depth = depth;
    }
}
