#include "seismic.hpp"
double distance(const Solution &q, const Station &s) {
    const double x = q[0] - s.x, y = q[1] - s.y, z = q[2] + s.elevation;
    return std::sqrt(x * x + y * y + z * z);
}
Values residuals(const Solution &q, const Observations &obs, const std::vector<Station> &stations,
                 double velocity) {
    Values out;
    for (const auto &observation : obs)
        out.push_back(observation.time - q[3] - distance(q, stations[observation.station]) / velocity);
    return out;
}
double rms(const Solution &q, const Observations &obs, const std::vector<Station> &stations,
           double velocity) {
    double sum = 0;
    for (double r : residuals(q, obs, stations, velocity))
        sum += r * r;
    return std::sqrt(sum / obs.size());
}
static Matrix cholesky(const Matrix &matrix) {
    Matrix lower{};
    for (int a = 0; a < 4; ++a)
        for (int b = 0; b <= a; ++b) {
            double sum = 0;
            for (int j = 0; j < b; ++j)
                sum += lower[a][j] * lower[b][j];
            lower[a][b] = a == b ? std::sqrt(matrix[a][a] - sum) : (matrix[a][b] - sum) / lower[b][b];
        }
    return lower;
}
static Solution solve(const Matrix &lower, const Solution &right) {
    Solution forward{}, solution{};
    for (int a = 0; a < 4; ++a) {
        double sum = 0;
        for (int j = 0; j < a; ++j)
            sum += lower[a][j] * forward[j];
        forward[a] = (right[a] - sum) / lower[a][a];
    }
    for (int a = 3; a >= 0; --a) {
        double sum = 0;
        for (int j = a + 1; j < 4; ++j)
            sum += lower[j][a] * solution[j];
        solution[a] = (forward[a] - sum) / lower[a][a];
    }
    return solution;
}
static std::pair<Matrix, Solution> normals(const Solution &q, const Observations &obs,
                                           const std::vector<Station> &stations, double velocity) {
    Matrix matrix{};
    Solution right{};
    for (const auto &observation : obs) {
        const Station &s = stations[observation.station];
        const double d = distance(q, s), r = observation.time - q[3] - d / velocity;
        const Solution g = {(q[0] - s.x) / (velocity * d), (q[1] - s.y) / (velocity * d),
                            (q[2] + s.elevation) / (velocity * d), 1};
        for (int a = 0; a < 4; ++a) {
            right[a] += g[a] * r;
            for (int b = 0; b < 4; ++b)
                matrix[a][b] += g[a] * g[b];
        }
    }
    return {matrix, right};
}
Run geiger(Solution q, const Observations &obs, const std::vector<Station> &stations, double velocity) {
    Run out;
    for (int iteration = 0; iteration < 8; ++iteration) {
        const auto normal = normals(q, obs, stations, velocity);
        const Solution delta = solve(cholesky(normal.first), normal.second);
        for (int a = 0; a < 4; ++a)
            q[a] += delta[a];
        q[2] = std::max(0.0, q[2]);
        out.trace[iteration] = {q, rms(q, obs, stations, velocity)};
    }
    out.solution = q;
    out.residual = residuals(q, obs, stations, velocity);
    out.rms = rms(q, obs, stations, velocity);
    return out;
}
Run locate(const Observations &obs, const std::vector<Station> &stations, const Params &p) {
    double best = std::numeric_limits<double>::infinity();
    Solution initial{};
    Values profile((p.gz[1] - p.gz[0]) / p.gz[2] + 1, best);
    for (I x = p.gx[0]; x <= p.gx[1]; x += p.gx[2])
        for (I y = p.gy[0]; y <= p.gy[1]; y += p.gy[2])
            for (I z = p.gz[0]; z <= p.gz[1]; z += p.gz[2]) {
                Solution q = {double(x), double(y), double(z), 0};
                Values delta;
                double total = 0;
                for (const auto &observation : obs) {
                    const double value =
                        observation.time - distance(q, stations[observation.station]) / p.velocity;
                    delta.push_back(value);
                    total += value;
                }
                q[3] = total / obs.size();
                double error = 0;
                for (double value : delta)
                    error += (value - q[3]) * (value - q[3]);
                if (error < best) {
                    best = error;
                    initial = q;
                }
                const int depth = (z - p.gz[0]) / p.gz[2];
                profile[depth] = std::min(profile[depth], error);
            }
    Run out = geiger(initial, obs, stations, p.velocity);
    out.grid = initial;
    out.grid_rms = std::sqrt(best / obs.size());
    for (double value : profile)
        out.profile.push_back(std::sqrt(value / obs.size()));
    return out;
}
Ellipse ellipse(const Solution &q, const Observations &obs, const std::vector<Station> &stations,
                double velocity) {
    const Matrix lower = cholesky(normals(q, obs, stations, velocity).first);
    Matrix covariance{};
    double sum = 0;
    for (double r : residuals(q, obs, stations, velocity))
        sum += r * r;
    const double variance = sum / (obs.size() - 4);
    for (int column = 0; column < 4; ++column) {
        Solution unit{};
        unit[column] = 1;
        const Solution values = solve(lower, unit);
        for (int row = 0; row < 4; ++row)
            covariance[row][column] = variance * values[row];
    }
    const double xx = covariance[0][0], yy = covariance[1][1], xy = covariance[0][1], mu = (xx + yy) / 2,
                 rho = std::sqrt((xx - yy) * (xx - yy) / 4 + xy * xy);
    double az = 90 - std::atan2(2 * xy, xx - yy) / 2 * 180 / pi;
    if (az >= 180)
        az -= 180;
    if (az < 0)
        az += 180;
    return {std::sqrt(mu + rho), std::sqrt(mu - rho), az, std::sqrt(covariance[2][2]),
            std::sqrt(covariance[3][3])};
}
