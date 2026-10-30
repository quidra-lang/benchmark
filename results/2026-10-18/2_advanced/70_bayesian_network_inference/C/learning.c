#include "bayes.h"
I parent_row(const Vars *parents, const Assignment *assignment, const Network *network) {
    I row = 0;
    for (int i = 0; i < parents->count; ++i) {
        int parent = parents->values[i];
        row = row * network->sizes[parent] + assignment->values[parent];
    }
    return row;
}
double total(const double *values, I count) {
    double result = 0;
    for (I i = 0; i < count; ++i)
        result += values[i];
    return result;
}
Counts count_samples(int variable, const Vars *parents, const Assignment *samples, int count,
                     const Network *network) {
    Counts out = {0};
    out.rows = 1;
    out.states = network->sizes[variable];
    for (int i = 0; i < parents->count; ++i)
        out.rows *= network->sizes[parents->values[i]];
    out.values = calloc((size_t)out.rows, sizeof(*out.values));
    for (int i = 0; i < count; ++i)
        ++out.values[parent_row(parents, &samples[i], network)][samples[i].values[variable]];
    return out;
}
CPT learn(const Counts *counts, double alpha) {
    CPT out = {0};
    out.rows = counts->rows;
    out.states = counts->states;
    out.values = calloc((size_t)out.rows, sizeof(*out.values));
    for (int row = 0; row < out.rows; ++row) {
        double denominator = 0;
        for (int state = 0; state < out.states; ++state) {
            out.values[row][state] = (double)counts->values[row][state] + alpha;
            denominator += out.values[row][state];
        }
        for (int state = 0; state < out.states; ++state)
            out.values[row][state] /= denominator;
    }
    return out;
}
double log_likelihood(const Counts *counts, const CPT *cpt) {
    double result = 0;
    for (int row = 0; row < counts->rows; ++row)
        for (int state = 0; state < counts->states; ++state)
            if (counts->values[row][state])
                result += (double)counts->values[row][state] * log(cpt->values[row][state]);
    return result;
}
I parameter_count(const Counts *counts) { return (I)(counts->states - 1) * counts->rows; }
double family_score(int variable, Vars parents, const Assignment *samples, int count,
                    const Network *network, double alpha) {
    parents = canonical(parents);
    Counts counts = count_samples(variable, &parents, samples, count, network);
    CPT probabilities = learn(&counts, alpha);
    double score = log_likelihood(&counts, &probabilities) -
                   (double)parameter_count(&counts) * log((double)count) / 2;
    free(counts.values);
    free(probabilities.values);
    return score;
}
