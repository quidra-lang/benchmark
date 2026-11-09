#include "bayes.hpp"
I entry_count(const Vars &variables, const Vars &sizes) {
    I out = 1;
    for (int variable : variables)
        out *= sizes[variable];
    return out;
}
Assignment decode(I index, const Vars &variables, const Vars &sizes, Assignment initial) {
    for (auto at = variables.rbegin(); at != variables.rend(); ++at) {
        initial[*at] = int(index % sizes[*at]);
        index /= sizes[*at];
    }
    return initial;
}
int evidence_state(const Evidence &evidence, int variable) {
    for (const auto &entry : evidence)
        if (entry.first == variable)
            return entry.second;
    return -1;
}
double Factor::value(const Assignment &assignment) const {
    return values[parent_row(variables, assignment, *sizes)];
}
Factor Factor::reduced(const Evidence &evidence) const {
    Vars remaining;
    for (int variable : variables)
        if (evidence_state(evidence, variable) < 0)
            remaining.push_back(variable);
    std::vector<double> out;
    for (I index = 0; index < entry_count(remaining, *sizes); ++index) {
        Assignment assignment = decode(index, remaining, *sizes);
        for (const auto &entry : evidence)
            assignment[entry.first] = entry.second;
        out.push_back(value(assignment));
    }
    return {remaining, out, sizes};
}
Factor Factor::multiplied(const Factor &other) const {
    std::set<int> scope(variables.begin(), variables.end());
    scope.insert(other.variables.begin(), other.variables.end());
    Vars merged(scope.begin(), scope.end());
    std::vector<double> out;
    for (I index = 0; index < entry_count(merged, *sizes); ++index) {
        Assignment assignment = decode(index, merged, *sizes);
        out.push_back(value(assignment) * other.value(assignment));
    }
    return {merged, out, sizes};
}
Factor Factor::eliminate(int variable, bool maximize) const {
    Vars remaining;
    for (int item : variables)
        if (item != variable)
            remaining.push_back(item);
    std::vector<double> out;
    for (I index = 0; index < entry_count(remaining, *sizes); ++index) {
        Assignment assignment = decode(index, remaining, *sizes);
        double value = 0;
        for (int state = 0; state < (*sizes)[variable]; ++state) {
            assignment[variable] = state;
            double candidate = this->value(assignment);
            if (maximize) {
                if (state == 0 || candidate > value)
                    value = candidate;
            } else
                value += candidate;
        }
        out.push_back(value);
    }
    return {remaining, out, sizes};
}
Factor cpt_factor(int variable, const Vars &parents, const CPT &cpt, const Vars &sizes) {
    Vars variables = parents;
    variables.push_back(variable);
    std::sort(variables.begin(), variables.end());
    std::vector<double> values;
    for (I index = 0; index < entry_count(variables, sizes); ++index) {
        Assignment assignment = decode(index, variables, sizes);
        values.push_back(cpt[parent_row(parents, assignment, sizes)][assignment[variable]]);
    }
    return {variables, values, &sizes};
}
Factor multiply(const std::vector<Factor> &factors, const Vars &sizes) {
    if (factors.empty())
        return {{}, {1}, &sizes};
    Factor out = factors[0];
    for (int i = 1; i < int(factors.size()); ++i)
        out = out.multiplied(factors[i]);
    return out;
}
