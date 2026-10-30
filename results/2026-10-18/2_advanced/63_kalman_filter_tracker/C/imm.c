#include "tracker.h"
IMM imm(const Params *p, Position measurement) {
    IMM out = {0};
    for (int j = 0; j < 2; ++j) {
        out.models[j] = kalman(false, p->imm_q[j], p, measurement);
        out.probabilities[j] = p->imm_initial[j];
    }
    memcpy(out.transition, p->transition, sizeof(out.transition));
    return out;
}
void imm_step(IMM *filter, double interval, const Position *measurement) {
    double predicted[2], likelihood[2] = {1, 1};
    Vector old_x[2] = {filter->models[0].x, filter->models[1].x};
    Matrix old_p[2] = {filter->models[0].P, filter->models[1].P};
    for (int j = 0; j < 2; ++j)
        predicted[j] = filter->transition[0][j] * filter->probabilities[0] +
                       filter->transition[1][j] * filter->probabilities[1];
    for (int j = 0; j < 2; ++j) {
        double w0 = filter->transition[0][j] * filter->probabilities[0] / predicted[j],
               w1 = filter->transition[1][j] * filter->probabilities[1] / predicted[j];
        Vector mixed = {4, {0}};
        for (int r = 0; r < 4; ++r)
            mixed.values[r] = w0 * old_x[0].values[r] + w1 * old_x[1].values[r];
        Matrix covariance = zeros(4, 4);
        for (int r = 0; r < 4; ++r)
            for (int s = 0; s < 4; ++s)
                covariance.values[r][s] =
                    w0 * (old_p[0].values[r][s] + (old_x[0].values[r] - mixed.values[r]) *
                                                      (old_x[0].values[s] - mixed.values[s])) +
                    w1 * (old_p[1].values[r][s] + (old_x[1].values[r] - mixed.values[r]) *
                                                      (old_x[1].values[s] - mixed.values[s]));
        filter->models[j].x = mixed;
        filter->models[j].P = covariance;
        predict(&filter->models[j], interval);
        if (measurement) {
            Innovation observation = innovation(&filter->models[j], *measurement);
            update(&filter->models[j], observation);
            likelihood[j] = exp(-observation.distance / 2) /
                            (2 * acos(-1.0) * sqrt(determinant2(observation.covariance)));
        }
    }
    double denominator = likelihood[0] * predicted[0] + likelihood[1] * predicted[1];
    for (int j = 0; j < 2; ++j)
        filter->probabilities[j] = likelihood[j] * predicted[j] / denominator;
}
Vector imm_estimate(const IMM *filter) {
    Vector out = {4, {0}};
    for (int r = 0; r < 4; ++r)
        out.values[r] = filter->probabilities[0] * filter->models[0].x.values[r] +
                        filter->probabilities[1] * filter->models[1].x.values[r];
    return out;
}
