#include "tracker.hpp"
Matrix transition(bool ca, double t) {
    Matrix out = identity(ca ? 6 : 4);
    out[0][2] = out[1][3] = t;
    if (ca) {
        out[0][4] = out[1][5] = t * t / 2;
        out[2][4] = out[3][5] = t;
    }
    return out;
}
Matrix process_noise(bool ca, double t, double q) {
    Matrix out = zeros(ca ? 6 : 4);
    for (int axis = 0; axis < 2; ++axis) {
        auto set = [&](int i, int j, double v) {
            out[i + axis][j + axis] = v;
            out[j + axis][i + axis] = v;
        };
        if (ca) {
            set(0, 0, q * t * t * t * t * t / 20);
            set(0, 2, q * t * t * t * t / 8);
            set(0, 4, q * t * t * t / 6);
            set(2, 2, q * t * t * t / 3);
            set(2, 4, q * t * t / 2);
            set(4, 4, q * t);
        } else {
            set(0, 0, q * t * t * t / 3);
            set(0, 2, q * t * t / 2);
            set(2, 2, q * t);
        }
    }
    return out;
}
Kalman::Kalman(bool ca, double q, const Params &p, Position measurement)
    : ca(ca), q(q), x(ca ? 6 : 4, 0), H(zeros(2, ca ? 6 : 4)),
      R(diagonal({p.sigma * p.sigma, p.sigma * p.sigma})) {
    x[0] = measurement[0];
    x[1] = measurement[1];
    Vector variances{p.sigma * p.sigma, p.sigma * p.sigma, p.velocity, p.velocity};
    if (ca) {
        variances.push_back(p.acceleration);
        variances.push_back(p.acceleration);
    }
    P = diagonal(variances);
    H[0][0] = H[1][1] = 1;
}
void Kalman::predict(double interval) {
    F = transition(ca, interval);
    x = product(F, x);
    P = add(product(product(F, P), transpose(F)), process_noise(ca, interval, q));
    xp = x;
    Pp = P;
}
Innovation Kalman::innovation(Position measurement) const {
    Vector predicted = product(H, x);
    Innovation out;
    out.residual = {measurement[0] - predicted[0], measurement[1] - predicted[1]};
    out.covariance = add(product(product(H, P), transpose(H)), R);
    out.precision = inverse(out.covariance);
    out.distance = quadratic2(out.residual, out.precision);
    return out;
}
double Kalman::update(const Innovation &innovation) {
    Matrix gain = product(product(P, transpose(H)), innovation.precision),
           correction = subtract(identity(int(x.size())), product(gain, H));
    x = add(x, product(gain, Vector{innovation.residual[0], innovation.residual[1]}));
    P = add(product(product(correction, P), transpose(correction)),
            product(product(gain, R), transpose(gain)));
    return -std::log(2 * std::acos(-1.0)) - std::log(determinant2(innovation.covariance)) / 2 -
           innovation.distance / 2;
}
std::vector<Vector> smooth(const std::vector<History> &history) {
    std::vector<Vector> out(history.size());
    out.back() = history.back().x;
    for (int i = int(history.size()) - 2; i >= 0; --i) {
        Matrix gain =
            product(product(history[i].P, transpose(history[i + 1].F)), inverse(history[i + 1].Pp));
        out[i] = add(history[i].x, product(gain, subtract(out[i + 1], history[i + 1].xp)));
    }
    return out;
}
