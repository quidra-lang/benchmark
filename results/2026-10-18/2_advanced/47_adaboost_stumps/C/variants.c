#include "boosting.h"
static double sum(const double *values, int n) {
    double out = 0;
    for (int i = 0; i < n; ++i)
        out += values[i];
    return out;
}
Model *variant_train(const Rows *rows, const Params *p, const char *variant) {
    if (strcmp(variant, "discrete") == 0)
        return discrete(rows, p, p->rounds, 1, NULL);
    Search *search = prepare(rows, strcmp(variant, "real") == 0 ? p->bins : 0);
    Model *out = calloc(1, sizeof *out);
    out->variant = variant;
    out->stop = "completed";
    for (int j = 0; j < rows->d; ++j)
        memcpy(out->cuts[j], search->features[j].cuts, sizeof out->cuts[j]);
    double weights[400], score[400] = {0}, probability[400], targets[400];
    for (int i = 0; i < rows->n; ++i) {
        weights[i] = 1.0 / rows->n;
        probability[i] = 0.5;
    }
    double bound = 1;
    for (int t = 0; t < p->rounds; ++t) {
        Round round = {0};
        if (strcmp(variant, "real") == 0) {
            const RealCandidate candidate = real_stump(rows, search, weights, p->bins, p->smoothing);
            if (candidate.z >= 1 - p->convergence) {
                out->stop = "converged";
                break;
            }
            round.stump = candidate.stump;
            round.z = candidate.z;
            bound = bound * candidate.z;
            round.bound = bound;
            memcpy(round.weights, weights, (size_t)rows->n * sizeof(double));
        } else {
            if (strcmp(variant, "gentle") == 0)
                for (int i = 0; i < rows->n; ++i)
                    targets[i] = rows->rows[i].label;
            else {
                double q[400];
                for (int i = 0; i < rows->n; ++i) {
                    q[i] = probability[i] * (1 - probability[i]);
                    const double z = ((rows->rows[i].label == 1 ? 1 : 0) - probability[i]) / q[i];
                    targets[i] = z > p->clip ? p->clip : z < -p->clip ? -p->clip : z;
                }
                const double total = sum(q, rows->n);
                for (int i = 0; i < rows->n; ++i)
                    weights[i] = q[i] / total;
            }
            const Candidate candidate = regression_stump(rows, search, targets, weights);
            round.stump = candidate.stump;
            round.error = candidate.error;
            memcpy(round.weights, weights, (size_t)rows->n * sizeof(double));
            if (strcmp(variant, "logit") == 0)
                for (int b = 0; b < 2; ++b)
                    round.stump.values[b] /= 2;
        }
        if (strcmp(variant, "logit") == 0) {
            double loss = 0;
            for (int i = 0; i < rows->n; ++i) {
                score[i] = score[i] + stump_output(&round.stump, rows->rows[i].values);
                probability[i] = 1 / (1 + exp(-2 * score[i]));
                loss += log(1 + exp(-2 * rows->rows[i].label * score[i]));
            }
            round.loss = loss / rows->n;
        } else {
            for (int i = 0; i < rows->n; ++i)
                weights[i] =
                    weights[i] * exp(-rows->rows[i].label * stump_output(&round.stump, rows->rows[i].values));
            const double total = sum(weights, rows->n);
            for (int i = 0; i < rows->n; ++i)
                weights[i] /= total;
        }
        out->rounds[out->n++] = round;
    }
    free(search);
    return out;
}
