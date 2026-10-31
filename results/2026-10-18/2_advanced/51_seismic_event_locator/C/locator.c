#include "seismic.h"
typedef struct {
    double data[4][4];
} Matrix;
double distance(Solution q, const Station *s) {
    double x = q.data[0] - (double)s->x, y = q.data[1] - (double)s->y, z = q.data[2] + (double)s->elevation;
    return sqrt(x * x + y * y + z * z);
}
void residuals(Solution q, Observations obs, const Station *stations, double velocity, double *result) {
    for (int j = 0; j < obs.count; ++j)
        result[j] = obs.data[j].time - q.data[3] - distance(q, &stations[obs.data[j].station]) / velocity;
}
double rms(Solution q, Observations obs, const Station *stations, double velocity) {
    double values[12], sum = 0;
    residuals(q, obs, stations, velocity, values);
    for (int j = 0; j < obs.count; ++j)
        sum += values[j] * values[j];
    return sqrt(sum / obs.count);
}
static Matrix cholesky(Matrix matrix) {
    Matrix lower = {0};
    for (int a = 0; a < 4; ++a)
        for (int b = 0; b <= a; ++b) {
            double sum = 0;
            for (int j = 0; j < b; ++j)
                sum += lower.data[a][j] * lower.data[b][j];
            lower.data[a][b] =
                a == b ? sqrt(matrix.data[a][a] - sum) : (matrix.data[a][b] - sum) / lower.data[b][b];
        }
    return lower;
}
static Solution solve(Matrix lower, Solution right) {
    Solution forward = {0}, result = {0};
    for (int a = 0; a < 4; ++a) {
        double sum = 0;
        for (int j = 0; j < a; ++j)
            sum += lower.data[a][j] * forward.data[j];
        forward.data[a] = (right.data[a] - sum) / lower.data[a][a];
    }
    for (int a = 3; a >= 0; --a) {
        double sum = 0;
        for (int j = a + 1; j < 4; ++j)
            sum += lower.data[j][a] * result.data[j];
        result.data[a] = (forward.data[a] - sum) / lower.data[a][a];
    }
    return result;
}
static Matrix normals(Solution q, Observations obs, const Station *stations, double velocity,
                      Solution *right) {
    Matrix matrix = {0};
    *right = (Solution){0};
    for (int j = 0; j < obs.count; ++j) {
        const Station *s = &stations[obs.data[j].station];
        double d = distance(q, s), r = obs.data[j].time - q.data[3] - d / velocity;
        double g[] = {(q.data[0] - s->x) / (velocity * d), (q.data[1] - s->y) / (velocity * d),
                      (q.data[2] + s->elevation) / (velocity * d), 1};
        for (int a = 0; a < 4; ++a) {
            right->data[a] += g[a] * r;
            for (int b = 0; b < 4; ++b)
                matrix.data[a][b] += g[a] * g[b];
        }
    }
    return matrix;
}
Run geiger(Solution q, Observations obs, const Station *stations, double velocity) {
    Run out = {0};
    for (int iteration = 0; iteration < 8; ++iteration) {
        Solution right;
        Matrix matrix = normals(q, obs, stations, velocity, &right);
        Solution delta = solve(cholesky(matrix), right);
        for (int a = 0; a < 4; ++a)
            q.data[a] += delta.data[a];
        if (q.data[2] < 0)
            q.data[2] = 0;
        out.trace[iteration] = (Iteration){q, rms(q, obs, stations, velocity)};
    }
    out.solution = q;
    residuals(q, obs, stations, velocity, out.residual);
    out.rms = rms(q, obs, stations, velocity);
    return out;
}
Run locate(Observations obs, const Station *stations, const Params *p) {
    double best = INFINITY;
    Solution initial = {0};
    int depths = (int)((p->gz[1] - p->gz[0]) / p->gz[2] + 1);
    double *profile = allocate(depths, sizeof(double));
    for (int i = 0; i < depths; ++i)
        profile[i] = INFINITY;
    for (I x = p->gx[0]; x <= p->gx[1]; x += p->gx[2])
        for (I y = p->gy[0]; y <= p->gy[1]; y += p->gy[2])
            for (I z = p->gz[0]; z <= p->gz[1]; z += p->gz[2]) {
                Solution q = {{(double)x, (double)y, (double)z, 0}};
                double delta[12], total = 0;
                for (int j = 0; j < obs.count; ++j) {
                    delta[j] = obs.data[j].time - distance(q, &stations[obs.data[j].station]) / p->velocity;
                    total += delta[j];
                }
                q.data[3] = total / obs.count;
                double error = 0;
                for (int j = 0; j < obs.count; ++j)
                    error += (delta[j] - q.data[3]) * (delta[j] - q.data[3]);
                if (error < best) {
                    best = error;
                    initial = q;
                }
                int index = (int)((z - p->gz[0]) / p->gz[2]);
                if (error < profile[index])
                    profile[index] = error;
            }
    Run out = geiger(initial, obs, stations, p->velocity);
    out.grid = initial;
    out.grid_rms = sqrt(best / obs.count);
    out.profile = profile;
    out.depths = depths;
    for (int i = 0; i < depths; ++i)
        profile[i] = sqrt(profile[i] / obs.count);
    return out;
}
Ellipse ellipse(Solution q, Observations obs, const Station *stations, double velocity) {
    Solution right;
    Matrix lower = cholesky(normals(q, obs, stations, velocity, &right)), covariance = {0};
    double values[12], sum = 0;
    residuals(q, obs, stations, velocity, values);
    for (int j = 0; j < obs.count; ++j)
        sum += values[j] * values[j];
    double variance = sum / (obs.count - 4);
    for (int column = 0; column < 4; ++column) {
        Solution unit = {0};
        unit.data[column] = 1;
        Solution solution = solve(lower, unit);
        for (int row = 0; row < 4; ++row)
            covariance.data[row][column] = variance * solution.data[row];
    }
    double xx = covariance.data[0][0], yy = covariance.data[1][1], xy = covariance.data[0][1],
           mu = (xx + yy) / 2, rho = sqrt((xx - yy) * (xx - yy) / 4 + xy * xy);
    double az = 90 - atan2(2 * xy, xx - yy) / 2 * 180 / 3.141592653589793;
    if (az >= 180)
        az -= 180;
    if (az < 0)
        az += 180;
    return (Ellipse){sqrt(mu + rho), sqrt(mu - rho), az, sqrt(covariance.data[2][2]),
                     sqrt(covariance.data[3][3])};
}
