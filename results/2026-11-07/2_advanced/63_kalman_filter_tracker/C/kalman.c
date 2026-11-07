#include "tracker.h"
Matrix transition(bool ca, double t) {
    Matrix out = identity(ca ? 6 : 4);
    out.values[0][2] = out.values[1][3] = t;
    if (ca) {
        out.values[0][4] = out.values[1][5] = t * t / 2;
        out.values[2][4] = out.values[3][5] = t;
    }
    return out;
}
static void entry(Matrix *a, int axis, int i, int j, double value) {
    a->values[i + axis][j + axis] = value;
    a->values[j + axis][i + axis] = value;
}
Matrix process_noise(bool ca, double t, double q) {
    Matrix out = zeros(ca ? 6 : 4, ca ? 6 : 4);
    for (int axis = 0; axis < 2; ++axis) {
        if (ca) {
            entry(&out, axis, 0, 0, q * t * t * t * t * t / 20);
            entry(&out, axis, 0, 2, q * t * t * t * t / 8);
            entry(&out, axis, 0, 4, q * t * t * t / 6);
            entry(&out, axis, 2, 2, q * t * t * t / 3);
            entry(&out, axis, 2, 4, q * t * t / 2);
            entry(&out, axis, 4, 4, q * t);
        } else {
            entry(&out, axis, 0, 0, q * t * t * t / 3);
            entry(&out, axis, 0, 2, q * t * t / 2);
            entry(&out, axis, 2, 2, q * t);
        }
    }
    return out;
}
Kalman kalman(bool ca, double q, const Params *p, Position measurement) {
    Kalman out = {0};
    out.ca = ca;
    out.q = q;
    out.x.count = ca ? 6 : 4;
    out.x.values[0] = measurement.x;
    out.x.values[1] = measurement.y;
    Vector variances = {ca ? 6 : 4,
                        {p->sigma * p->sigma, p->sigma * p->sigma, p->velocity, p->velocity,
                         p->acceleration, p->acceleration}};
    out.P = diagonal(variances);
    out.H = zeros(2, out.x.count);
    out.H.values[0][0] = out.H.values[1][1] = 1;
    Vector noise = {2, {p->sigma * p->sigma, p->sigma * p->sigma}};
    out.R = diagonal(noise);
    return out;
}
void predict(Kalman *filter, double interval) {
    filter->F = transition(filter->ca, interval);
    filter->x = matrix_vector(filter->F, filter->x);
    filter->P =
        matrix_add(matrix_product(matrix_product(filter->F, filter->P), transpose(filter->F)),
                   process_noise(filter->ca, interval, filter->q));
    filter->xp = filter->x;
    filter->Pp = filter->P;
}
Innovation innovation(const Kalman *filter, Position measurement) {
    Vector expected = matrix_vector(filter->H, filter->x);
    Innovation out = {0};
    out.residual =
        (Position){measurement.x - expected.values[0], measurement.y - expected.values[1]};
    out.covariance = matrix_add(
        matrix_product(matrix_product(filter->H, filter->P), transpose(filter->H)), filter->R);
    out.precision = inverse(out.covariance);
    out.distance = quadratic2(out.residual, out.precision);
    return out;
}
double update(Kalman *filter, Innovation observation) {
    Matrix gain = matrix_product(matrix_product(filter->P, transpose(filter->H)),
                                 observation.precision),
           correction = matrix_subtract(identity(filter->x.count), matrix_product(gain, filter->H));
    Vector residual = {2, {observation.residual.x, observation.residual.y}};
    filter->x = vector_add(filter->x, matrix_vector(gain, residual));
    filter->P =
        matrix_add(matrix_product(matrix_product(correction, filter->P), transpose(correction)),
                   matrix_product(matrix_product(gain, filter->R), transpose(gain)));
    return -log(2 * acos(-1.0)) - log(determinant2(observation.covariance)) / 2 -
           observation.distance / 2;
}
Vector *smooth(const History *history, int count) {
    Vector *out = allocate((size_t)count, sizeof(Vector));
    out[count - 1] = history[count - 1].x;
    for (int i = count - 2; i >= 0; --i) {
        Matrix gain = matrix_product(matrix_product(history[i].P, transpose(history[i + 1].F)),
                                     inverse(history[i + 1].Pp));
        out[i] = vector_add(history[i].x,
                            matrix_vector(gain, vector_subtract(out[i + 1], history[i + 1].xp)));
    }
    return out;
}
