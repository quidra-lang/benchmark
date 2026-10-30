#include "bayes.h"
int contains(const Vars *variables, int variable) {
    for (int i = 0; i < variables->count; ++i)
        if (variables->values[i] == variable)
            return 1;
    return 0;
}
static int integer_order(const void *left, const void *right) {
    return *(const int *)left - *(const int *)right;
}
Vars canonical(Vars variables) {
    qsort(variables.values, (size_t)variables.count, sizeof(int), integer_order);
    return variables;
}
Vars vars_union(Vars a, Vars b) {
    for (int i = 0; i < b.count; ++i)
        if (!contains(&a, b.values[i]))
            a.values[a.count++] = b.values[i];
    return canonical(a);
}
Vars vars_difference(Vars a, Vars b) {
    Vars out = {0};
    for (int i = 0; i < a.count; ++i)
        if (!contains(&b, a.values[i]))
            out.values[out.count++] = a.values[i];
    return out;
}
Vars observed(const Evidence *evidence) {
    Vars out = {0};
    for (int i = 0; i < evidence->count; ++i)
        out.values[out.count++] = evidence->values[i].variable;
    return canonical(out);
}
I entry_count(const Vars *variables, const Network *network) {
    I count = 1;
    for (int i = 0; i < variables->count; ++i)
        count *= network->sizes[variables->values[i]];
    return count;
}
Assignment decode(I index, const Vars *variables, const Network *network, Assignment initial) {
    for (int i = variables->count - 1; i >= 0; --i) {
        int v = variables->values[i];
        initial.values[v] = (int)(index % network->sizes[v]);
        index /= network->sizes[v];
    }
    return initial;
}
int evidence_state(const Evidence *evidence, int variable) {
    for (int i = 0; i < evidence->count; ++i)
        if (evidence->values[i].variable == variable)
            return evidence->values[i].state;
    return -1;
}
static Factor factor_create(Vars variables, const Network *network) {
    Factor out = {0};
    out.variables = variables;
    out.network = network;
    out.count = entry_count(&variables, network);
    out.values = calloc((size_t)out.count, sizeof(double));
    return out;
}
double factor_value(const Factor *factor, const Assignment *assignment) {
    return factor->values[parent_row(&factor->variables, assignment, factor->network)];
}
Factor reduced(const Factor *factor, const Evidence *evidence) {
    Vars variables = vars_difference(factor->variables, observed(evidence));
    Factor out = factor_create(variables, factor->network);
    Assignment initial = {0};
    for (int i = 0; i < evidence->count; ++i)
        initial.values[evidence->values[i].variable] = evidence->values[i].state;
    for (I row = 0; row < out.count; ++row) {
        Assignment assignment = decode(row, &variables, out.network, initial);
        out.values[row] = factor_value(factor, &assignment);
    }
    return out;
}
Factor multiplied(const Factor *first, const Factor *second) {
    Factor out = factor_create(vars_union(first->variables, second->variables), first->network);
    for (I row = 0; row < out.count; ++row) {
        Assignment initial = {0}, assignment = decode(row, &out.variables, out.network, initial);
        out.values[row] = factor_value(first, &assignment) * factor_value(second, &assignment);
    }
    return out;
}
Factor factor_eliminate(const Factor *factor, int variable, int maximize) {
    Vars removed = {.values = {variable}, .count = 1};
    Factor out = factor_create(vars_difference(factor->variables, removed), factor->network);
    for (I row = 0; row < out.count; ++row) {
        Assignment initial = {0}, assignment = decode(row, &out.variables, out.network, initial);
        double value = 0;
        for (int state = 0; state < out.network->sizes[variable]; ++state) {
            assignment.values[variable] = state;
            double candidate = factor_value(factor, &assignment);
            if (maximize) {
                if (!state || candidate > value)
                    value = candidate;
            } else
                value += candidate;
        }
        out.values[row] = value;
    }
    return out;
}
Factor cpt_factor(int variable, const Vars *parents, const CPT *cpt, const Network *network) {
    Vars own = {.values = {variable}, .count = 1};
    Factor out = factor_create(vars_union(*parents, own), network);
    for (I row = 0; row < out.count; ++row) {
        Assignment initial = {0}, assignment = decode(row, &out.variables, network, initial);
        out.values[row] =
            cpt->values[parent_row(parents, &assignment, network)][assignment.values[variable]];
    }
    return out;
}
Factor multiply(const Factors *factors, const Network *network) {
    if (!factors->count) {
        Vars empty = {0};
        Factor out = factor_create(empty, network);
        out.values[0] = 1;
        return out;
    }
    Factor result = factors->values[0];
    for (int i = 1; i < factors->count; ++i)
        result = multiplied(&result, &factors->values[i]);
    return result;
}
