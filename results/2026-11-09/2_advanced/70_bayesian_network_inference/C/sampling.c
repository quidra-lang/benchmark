#include "bayes.h"
double uniform(Minstd *random) {
    random->state = (48271 * random->state) % 2147483647;
    return (double)random->state / 2147483647;
}
int choose(const double *probabilities, int count, Minstd *random) {
    double value = uniform(random), cumulative = 0;
    for (int state = 0; state < count; ++state) {
        cumulative += probabilities[state];
        if (value < cumulative)
            return state;
    }
    return count - 1;
}
Weighted weighted_sample(const Vars *topological, const Network *network, const CPT cpts[15],
                         const Evidence *evidence, Minstd *random) {
    Weighted out = {0};
    out.weight = 1;
    for (int i = 0; i < topological->count; ++i) {
        int variable = topological->values[i];
        const double *probabilities =
            cpts[variable]
                .values[parent_row(&network->parents[variable], &out.assignment, network)];
        int state = evidence_state(evidence, variable);
        if (state >= 0) {
            out.assignment.values[variable] = state;
            out.weight *= probabilities[state];
        } else
            out.assignment.values[variable] =
                choose(probabilities, network->sizes[variable], random);
    }
    return out;
}
