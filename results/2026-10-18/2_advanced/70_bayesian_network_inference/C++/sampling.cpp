#include "bayes.hpp"
double Minstd::uniform() {
    state = (48271 * state) % 2147483647;
    return double(state) / 2147483647;
}
int choose(const std::vector<double> &probabilities, Minstd &random) {
    double uniform = random.uniform(), cumulative = 0;
    for (int state = 0; state < int(probabilities.size()); ++state) {
        cumulative += probabilities[state];
        if (uniform < cumulative)
            return state;
    }
    return int(probabilities.size()) - 1;
}
std::pair<Assignment, double> weighted_sample(const Vars &topological,
                                              const std::vector<Vars> &parents,
                                              const std::vector<CPT> &cpts, const Vars &sizes,
                                              const Evidence &evidence, Minstd &random) {
    Assignment assignment{};
    double weight = 1;
    for (int variable : topological) {
        const std::vector<double> &probabilities =
            cpts[variable][parent_row(parents[variable], assignment, sizes)];
        int observed = evidence_state(evidence, variable);
        if (observed >= 0) {
            assignment[variable] = observed;
            weight *= probabilities[observed];
        } else
            assignment[variable] = choose(probabilities, random);
    }
    return {assignment, weight};
}
