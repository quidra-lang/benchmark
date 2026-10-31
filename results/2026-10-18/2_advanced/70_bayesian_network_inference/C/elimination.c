#include "bayes.h"
Graph interaction_graph(const Factors *factors) {
    Graph out = {0};
    for (int i = 0; i < factors->count; ++i) {
        Vars variables = factors->values[i].variables;
        for (int a = 0; a < variables.count; ++a) {
            int v = variables.values[a];
            out.present |= 1u << v;
            for (int b = 0; b < variables.count; ++b)
                if (a != b)
                    out.neighbors[v] |= 1u << variables.values[b];
        }
    }
    return out;
}
static int population(unsigned mask) {
    int count = 0;
    while (mask) {
        count += (int)(mask & 1u);
        mask >>= 1;
    }
    return count;
}
Plan make_plan(const Factors *factors, const Vars *eliminate, int given, const Vars *order,
               const Network *network) {
    Graph graph = interaction_graph(factors);
    unsigned remaining = 0;
    int rank[15] = {0};
    for (int i = 0; i < eliminate->count; ++i)
        remaining |= 1u << eliminate->values[i];
    for (int i = 0; i < order->count; ++i)
        rank[order->values[i]] = i;
    Plan out = {0};
    while (remaining) {
        int selected = -1, chosen_fill = 0, chosen_degree = 0;
        for (int v = 0; v < network->count; ++v)
            if (remaining & (1u << v)) {
                unsigned neighbors = graph.neighbors[v];
                int fill = 0, degree = population(neighbors);
                for (int a = 0; a < network->count; ++a)
                    if (neighbors & (1u << a))
                        for (int b = a + 1; b < network->count; ++b)
                            if ((neighbors & (1u << b)) && !(graph.neighbors[a] & (1u << b)))
                                ++fill;
                int better = selected < 0;
                if (!better)
                    better =
                        given ? rank[v] < rank[selected]
                              : fill < chosen_fill || (fill == chosen_fill &&
                                                       (degree < chosen_degree ||
                                                        (degree == chosen_degree && v < selected)));
                if (better) {
                    selected = v;
                    chosen_fill = fill;
                    chosen_degree = degree;
                }
            }
        unsigned neighbors = graph.neighbors[selected];
        Step *step = &out.steps[out.count++];
        step->variable = selected;
        step->fill = chosen_fill;
        for (int v = 0; v < network->count; ++v)
            if ((neighbors | (1u << selected)) & (1u << v))
                step->scope.values[step->scope.count++] = v;
        step->size = entry_count(&step->scope, network);
        if (step->size > out.maximum)
            out.maximum = step->size;
        out.total += step->size;
        for (int v = 0; v < network->count; ++v) {
            if (neighbors & (1u << v))
                graph.neighbors[v] |= neighbors & ~(1u << v);
            graph.neighbors[v] &= ~(1u << selected);
        }
        graph.neighbors[selected] = 0;
        graph.present &= ~(1u << selected);
        remaining &= ~(1u << selected);
    }
    return out;
}
Execution execute(const Factors *initial, const Plan *plan, const Network *network, int maximize) {
    Execution out = {0};
    Factors factors = *initial;
    for (int i = 0; i < plan->count; ++i) {
        int variable = plan->steps[i].variable;
        Factors selected = {0}, remaining = {0};
        for (int j = 0; j < factors.count; ++j) {
            Factor factor = factors.values[j];
            if (contains(&factor.variables, variable))
                selected.values[selected.count++] = factor;
            else
                remaining.values[remaining.count++] = factor;
        }
        Factor product = multiply(&selected, network);
        remaining.values[remaining.count++] = factor_eliminate(&product, variable, maximize);
        if (maximize) {
            out.variables[out.count] = variable;
            out.products[out.count++] = product;
        }
        factors = remaining;
    }
    out.final = multiply(&factors, network);
    return out;
}
Assignment traceback(const Execution *execution, const Network *network) {
    Assignment out = {0};
    for (int i = execution->count - 1; i >= 0; --i) {
        int variable = execution->variables[i], selected = 0;
        double best = -1;
        for (int state = 0; state < network->sizes[variable]; ++state) {
            out.values[variable] = state;
            double value = factor_value(&execution->products[i], &out);
            if (value > best) {
                best = value;
                selected = state;
            }
        }
        out.values[variable] = selected;
    }
    return out;
}
