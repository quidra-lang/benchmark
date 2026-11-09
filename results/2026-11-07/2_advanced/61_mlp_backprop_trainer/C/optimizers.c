#include "trainer.h"
void optimizer_init(Optimizer *optimizer) {
    memset(optimizer, 0, sizeof(*optimizer));
    optimizer->pi1 = optimizer->pi2 = 1;
}
void update(Optimizer *optimizer, double *weights, const double *gradient, int count,
            const Run *run, double eta) {
    bool adam = strcmp(run->optimizer, "ADAM") == 0;
    if (adam) {
        optimizer->pi1 = optimizer->pi1 * run->beta1;
        optimizer->pi2 = optimizer->pi2 * run->beta2;
    }
    for (int p = 0; p < count; ++p) {
        if (strcmp(run->optimizer, "SGD") == 0)
            weights[p] = weights[p] - eta * gradient[p];
        else if (strcmp(run->optimizer, "MOMENTUM") == 0) {
            optimizer->first[p] = run->mu * optimizer->first[p] + gradient[p];
            weights[p] = weights[p] - eta * optimizer->first[p];
        } else {
            optimizer->first[p] = run->beta1 * optimizer->first[p] + (1 - run->beta1) * gradient[p];
            optimizer->second[p] =
                run->beta2 * optimizer->second[p] + (1 - run->beta2) * gradient[p] * gradient[p];
            double m = optimizer->first[p] / (1 - optimizer->pi1),
                   v = optimizer->second[p] / (1 - optimizer->pi2);
            weights[p] = weights[p] - eta * m / (sqrt(v) + run->epsilon);
        }
    }
}
double learning_rate(const Run *run, const Params *params, int epoch) {
    double out = run->eta;
    for (int i = 0; i < (epoch - 1) / params->lr_step; ++i)
        out *= params->gamma;
    return out;
}
