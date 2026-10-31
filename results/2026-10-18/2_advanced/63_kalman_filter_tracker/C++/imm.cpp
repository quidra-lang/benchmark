#include "tracker.hpp"
IMM::IMM(const Params &p, Position measurement)
    : models{Kalman(false, p.imm_q[0], p, measurement), Kalman(false, p.imm_q[1], p, measurement)},
      probabilities(p.imm_initial), transition(p.transition) {}
void IMM::step(double interval, std::optional<Position> measurement) {
    std::array<double, 2> predicted{}, likelihood{1, 1};
    for (int j = 0; j < 2; ++j)
        predicted[j] = transition[0][j] * probabilities[0] + transition[1][j] * probabilities[1];
    std::array<Vector, 2> old_x{models[0].x, models[1].x};
    std::array<Matrix, 2> old_p{models[0].P, models[1].P};
    for (int j = 0; j < 2; ++j) {
        double w0 = transition[0][j] * probabilities[0] / predicted[j],
               w1 = transition[1][j] * probabilities[1] / predicted[j];
        Vector mixed(4);
        for (int r = 0; r < 4; ++r)
            mixed[r] = w0 * old_x[0][r] + w1 * old_x[1][r];
        Matrix covariance = zeros(4);
        for (int r = 0; r < 4; ++r)
            for (int s = 0; s < 4; ++s)
                covariance[r][s] =
                    w0 * (old_p[0][r][s] + (old_x[0][r] - mixed[r]) * (old_x[0][s] - mixed[s])) +
                    w1 * (old_p[1][r][s] + (old_x[1][r] - mixed[r]) * (old_x[1][s] - mixed[s]));
        models[j].x = mixed;
        models[j].P = covariance;
        models[j].predict(interval);
        if (measurement) {
            Innovation innovation = models[j].innovation(*measurement);
            models[j].update(innovation);
            likelihood[j] = std::exp(-innovation.distance / 2) /
                            (2 * std::acos(-1.0) * std::sqrt(determinant2(innovation.covariance)));
        }
    }
    double denominator = likelihood[0] * predicted[0] + likelihood[1] * predicted[1];
    for (int j = 0; j < 2; ++j)
        probabilities[j] = likelihood[j] * predicted[j] / denominator;
}
Estimate IMM::estimate() const {
    Estimate out{};
    for (int r = 0; r < 4; ++r)
        out[r] = probabilities[0] * models[0].x[r] + probabilities[1] * models[1].x[r];
    return out;
}
