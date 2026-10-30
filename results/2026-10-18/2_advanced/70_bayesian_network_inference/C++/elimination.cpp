#include "bayes.hpp"
Graph interaction_graph(const std::vector<Factor> &factors) {
    Graph graph;
    for (const Factor &factor : factors)
        for (int a : factor.variables) {
            graph.present[a] = true;
            for (int b : factor.variables)
                if (a != b)
                    graph.adjacent[a][b] = true;
        }
    return graph;
}
Plan make_plan(const std::vector<Factor> &factors, const Vars &eliminate, bool given,
               const Vars &order, const Vars &sizes) {
    Graph graph = interaction_graph(factors);
    std::set<int> remaining(eliminate.begin(), eliminate.end());
    std::array<int, 15> rank{};
    for (int i = 0; i < int(order.size()); ++i)
        rank[order[i]] = i;
    Plan out;
    while (!remaining.empty()) {
        int selected = -1, chosen_fill = 0, chosen_degree = 0;
        std::array<Vars, 15> neighbors;
        std::array<int, 15> fill{};
        for (int v : remaining) {
            for (int i = 0; i < int(sizes.size()); ++i)
                if (graph.adjacent[v][i])
                    neighbors[v].push_back(i);
            for (int i = 0; i < int(neighbors[v].size()); ++i)
                for (int j = i + 1; j < int(neighbors[v].size()); ++j)
                    fill[v] += !graph.adjacent[neighbors[v][i]][neighbors[v][j]];
            int degree = int(neighbors[v].size());
            if (selected < 0 || (given ? rank[v] < rank[selected]
                                       : std::tie(fill[v], degree, v) <
                                             std::tie(chosen_fill, chosen_degree, selected))) {
                selected = v;
                chosen_fill = fill[v];
                chosen_degree = degree;
            }
        }
        Vars scope = neighbors[selected];
        scope.push_back(selected);
        std::sort(scope.begin(), scope.end());
        I count = entry_count(scope, sizes);
        out.steps.push_back({selected, chosen_fill, scope, count});
        out.maximum = std::max(out.maximum, count);
        out.total += count;
        for (int a : neighbors[selected])
            for (int b : neighbors[selected])
                if (a != b)
                    graph.adjacent[a][b] = true;
        for (int i = 0; i < int(sizes.size()); ++i)
            graph.adjacent[i][selected] = graph.adjacent[selected][i] = false;
        graph.present[selected] = false;
        remaining.erase(selected);
    }
    return out;
}
Execution execute(const std::vector<Factor> &initial, const Plan &plan, const Vars &sizes,
                  bool maximize) {
    std::vector<Factor> factors = initial;
    Execution out{Factor{{}, {1}, &sizes}, {}};
    for (const Step &step : plan.steps) {
        std::vector<Factor> selected, remaining;
        for (const Factor &factor : factors) {
            if (std::find(factor.variables.begin(), factor.variables.end(), step.variable) !=
                factor.variables.end())
                selected.push_back(factor);
            else
                remaining.push_back(factor);
        }
        Factor product = multiply(selected, sizes);
        remaining.push_back(product.eliminate(step.variable, maximize));
        if (maximize)
            out.products.push_back({step.variable, product});
        factors = std::move(remaining);
    }
    out.final = multiply(factors, sizes);
    return out;
}
Assignment traceback(const Execution &execution, const Vars &sizes) {
    Assignment out{};
    for (auto at = execution.products.rbegin(); at != execution.products.rend(); ++at) {
        int variable = at->first;
        double best = -1;
        int selected = 0;
        for (int state = 0; state < sizes[variable]; ++state) {
            out[variable] = state;
            double value = at->second.value(out);
            if (value > best) {
                best = value;
                selected = state;
            }
        }
        out[variable] = selected;
    }
    return out;
}
