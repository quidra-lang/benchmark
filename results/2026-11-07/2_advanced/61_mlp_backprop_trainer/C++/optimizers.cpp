#include "trainer.hpp"
void Optimizer::update(Field &weights, const Field &gradient, const Run &run, double eta) {
    if (run.optimizer == "ADAM") {
        pi1 = pi1 * run.beta1;
        pi2 = pi2 * run.beta2;
    }
    for (int p = 0; p < int(weights.size()); ++p) {
        if (run.optimizer == "SGD")
            weights[p] = weights[p] - eta * gradient[p];
        else if (run.optimizer == "MOMENTUM") {
            first[p] = run.mu * first[p] + gradient[p];
            weights[p] = weights[p] - eta * first[p];
        } else {
            first[p] = run.beta1 * first[p] + (1 - run.beta1) * gradient[p];
            second[p] = run.beta2 * second[p] + (1 - run.beta2) * gradient[p] * gradient[p];
            const double m = first[p] / (1 - pi1), v = second[p] / (1 - pi2);
            weights[p] = weights[p] - eta * m / (std::sqrt(v) + run.epsilon);
        }
    }
}
double learning_rate(const Run &run, const Params &params, int epoch) {
    double out = run.eta;
    for (int i = 0; i < (epoch - 1) / params.lr_step; ++i)
        out *= params.gamma;
    return out;
}
