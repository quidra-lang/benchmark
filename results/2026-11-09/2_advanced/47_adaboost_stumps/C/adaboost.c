#include "boosting.h"
static double sum(const double *values, int n) {
    double out = 0;
    for (int i = 0; i < n; ++i)
        out += values[i];
    return out;
}
Model *discrete(const Rows *rows, const Params *p, int maximum, double shrinkage,
                const double *initial_weights) {
    (void)p;
    double weights[400];
    for (int i = 0; i < rows->n; ++i)
        weights[i] = initial_weights ? initial_weights[i] : 1.0 / rows->n;
    Search *search = prepare(rows, 0);
    Model *out = calloc(1, sizeof *out);
    out->variant = "discrete";
    out->stop = "completed";
    double bound = 1;
    for (int t = 0; t < maximum; ++t) {
        const Candidate candidate = discrete_stump(rows, search, weights);
        const double e = candidate.error;
        if (e >= 0.5) {
            out->stop = "weak";
            break;
        }
        const double alpha = e <= 0.0000000001 ? 1 : shrinkage * (0.5 * log((1 - e) / e));
        Round *round = &out->rounds[out->n++];
        round->stump = candidate.stump;
        for (int b = 0; b < 2; ++b)
            round->stump.values[b] *= alpha;
        memcpy(round->weights, weights, (size_t)rows->n * sizeof(double));
        round->polarity = candidate.polarity;
        round->error = e;
        round->alpha = alpha;
        for (int i = 0; i < rows->n; ++i) {
            const int decision = (int)stump_output(&candidate.stump, rows->rows[i].values);
            weights[i] = weights[i] * exp(decision == rows->rows[i].label ? -alpha : alpha);
        }
        round->z = sum(weights, rows->n);
        for (int i = 0; i < rows->n; ++i)
            weights[i] /= round->z;
        bound = bound * round->z;
        round->bound = bound;
        if (e <= 0.0000000001) {
            out->stop = "perfect";
            break;
        }
    }
    free(search);
    return out;
}
Model *samme(const Rows *rows, const Params *p) {
    Search *search = prepare(rows, 0);
    double weights[400];
    for (int i = 0; i < rows->n; ++i)
        weights[i] = 1.0 / rows->n;
    Model *out = calloc(1, sizeof *out);
    out->variant = "samme";
    out->stop = "completed";
    for (int t = 0; t < p->samme_rounds; ++t) {
        const Candidate candidate = multiclass_stump(rows, search, weights, p->classes);
        const double e = candidate.error;
        if (e >= (double)(p->classes - 1) / p->classes) {
            out->stop = "weak";
            break;
        }
        const double alpha = e <= 0.0000000001 ? 1 : log((1 - e) / e) + log((double)(p->classes - 1));
        for (int i = 0; i < rows->n; ++i)
            if ((int)stump_output(&candidate.stump, rows->rows[i].values) != rows->rows[i].label)
                weights[i] = weights[i] * exp(alpha);
        const double normalizer = sum(weights, rows->n);
        for (int i = 0; i < rows->n; ++i)
            weights[i] /= normalizer;
        Round *round = &out->rounds[out->n++];
        round->stump = candidate.stump;
        round->error = e;
        round->alpha = alpha;
        if (e <= 0.0000000001) {
            out->stop = "perfect";
            break;
        }
    }
    free(search);
    return out;
}
