#include "sat.h"
static void working_push(Preprocess *out, int id, Clause literals) {
    if (out->count == out->capacity) {
        out->capacity = out->capacity ? out->capacity * 2 : 16;
        out->clauses = resize(out->clauses, (size_t)out->capacity * sizeof(WorkingClause));
    }
    out->clauses[out->count++] = (WorkingClause){id, literals};
}
int removed_count(const Preprocess *reduced) {
    return reduced->tautologies + reduced->unit_removed + reduced->subsumed + reduced->pure_removed;
}
void preprocess_free(Preprocess *reduced) {
    for (int i = 0; i < reduced->count; ++i)
        int_free(&reduced->clauses[i].literals);
    free(reduced->clauses);
    for (int i = 0; i < 4; ++i)
        int_free(&reduced->removed[i]);
    *reduced = (Preprocess){0};
}
Preprocess preprocess(const Formula *formula, bool pure) {
    Preprocess out = {.pure = pure};
    for (int x = 0; x <= 200; ++x)
        out.fixed.values[x] = -1;
    for (int i = 0; i < formula->count; ++i) {
        const Clause *clause = &formula->clauses[i];
        bool tautology = false;
        for (int j = 0; j < clause->count; ++j)
            if (int_contains(clause, -clause->data[j]))
                tautology = true;
        if (tautology) {
            ++out.tautologies;
            int_push(&out.removed[0], i + 1);
            continue;
        }
        Clause normalized = {0};
        for (int j = 0; j < clause->count; ++j) {
            if (int_contains(&normalized, clause->data[j]))
                ++out.duplicate_literals;
            else
                int_push(&normalized, clause->data[j]);
        }
        working_push(&out, i + 1, normalized);
    }
    while (true) {
        int unit = 0;
        for (int i = 0; i < out.count; ++i)
            if (!out.clauses[i].literals.count) {
                out.conflict = true;
                out.empty_clause = out.clauses[i].id;
                return out;
            }
        for (int i = 0; i < out.count; ++i)
            if (out.clauses[i].literals.count == 1) {
                unit = out.clauses[i].literals.data[0];
                break;
            }
        if (!unit)
            break;
        out.fixed.values[abs(unit)] = unit > 0;
        ++out.unit_fixed;
        int remaining = 0;
        for (int i = 0; i < out.count; ++i) {
            WorkingClause clause = out.clauses[i];
            if (int_contains(&clause.literals, unit)) {
                ++out.unit_removed;
                int_push(&out.removed[1], clause.id);
                int_free(&clause.literals);
            } else {
                int length = 0;
                for (int j = 0; j < clause.literals.count; ++j)
                    if (clause.literals.data[j] != -unit)
                        clause.literals.data[length++] = clause.literals.data[j];
                clause.literals.count = length;
                out.clauses[remaining++] = clause;
            }
        }
        out.count = remaining;
    }
    bool *remove = calloc((size_t)out.count + 1, sizeof(bool));
    for (int b = 0; b < out.count; ++b)
        for (int a = 0; a < out.count; ++a) {
            const Clause *first = &out.clauses[a].literals, *second = &out.clauses[b].literals;
            if (a == b || !(first->count < second->count || a < b))
                continue;
            bool contained = true;
            for (int j = 0; j < first->count; ++j)
                if (!int_contains(second, first->data[j]))
                    contained = false;
            if (contained) {
                remove[b] = true;
                break;
            }
        }
    int remaining = 0;
    for (int i = 0; i < out.count; ++i) {
        if (remove[i]) {
            ++out.subsumed;
            int_push(&out.removed[2], out.clauses[i].id);
            int_free(&out.clauses[i].literals);
        } else
            out.clauses[remaining++] = out.clauses[i];
    }
    out.count = remaining;
    free(remove);
    if (pure)
        while (true) {
            bool present[401] = {0}, pure_literals[401] = {0};
            int count = 0;
            for (int i = 0; i < out.count; ++i)
                for (int j = 0; j < out.clauses[i].literals.count; ++j)
                    present[out.clauses[i].literals.data[j] + 200] = true;
            for (int literal = -200; literal <= 200; ++literal)
                if (present[literal + 200] && !present[200 - literal]) {
                    pure_literals[literal + 200] = true;
                    out.fixed.values[abs(literal)] = literal > 0;
                    ++count;
                }
            if (!count)
                break;
            out.pure_fixed += count;
            remaining = 0;
            for (int i = 0; i < out.count; ++i) {
                WorkingClause clause = out.clauses[i];
                bool removed = false;
                for (int j = 0; j < clause.literals.count; ++j)
                    if (pure_literals[clause.literals.data[j] + 200])
                        removed = true;
                if (removed) {
                    ++out.pure_removed;
                    int_push(&out.removed[3], clause.id);
                    int_free(&clause.literals);
                } else
                    out.clauses[remaining++] = clause;
            }
            out.count = remaining;
        }
    return out;
}
