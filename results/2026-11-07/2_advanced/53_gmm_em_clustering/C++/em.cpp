#include "mixture.hpp"
Model adjust(Model initial, Type type) {
    initial.type = type;
    if (type == Type::TIED) {
        Cov shared{};
        for (const auto &component : initial.components)
            for (int j = 0; j < 3; ++j)
                shared[j] += component.weight * component.cov[j];
        for (auto &component : initial.components)
            component.cov = shared;
    } else
        for (auto &component : initial.components) {
            if (type == Type::DIAG)
                component.cov[1] = 0;
            else if (type == Type::SPHERICAL) {
                const double variance = (component.cov[0] + component.cov[2]) / 2;
                component.cov = {variance, 0, variance};
            }
        }
    return initial;
}
Expectation expectation(const std::vector<Point> &points, const Model &model) {
    Expectation out;
    const int k = model.components.size();
    for (const Point &point : points) {
        Record record;
        double maximum = -std::numeric_limits<double>::infinity();
        for (int j = 0; j < k; ++j) {
            record.scores[j] = weighted_log(point.xy, model.components[j]);
            maximum = std::max(maximum, record.scores[j]);
        }
        double sum = 0;
        for (int j = 0; j < k; ++j) {
            record.responsibility[j] = std::exp(record.scores[j] - maximum);
            sum += record.responsibility[j];
        }
        for (int j = 0; j < k; ++j)
            record.responsibility[j] /= sum;
        record.log_density = maximum + std::log(sum);
        out.loglik += record.log_density;
        out.records.push_back(record);
    }
    return out;
}
static Model update(const std::vector<Point> &points, const Expectation &e, int k, Type type,
                    double epsilon) {
    Model out;
    out.type = type;
    out.components.resize(k);
    Values counts(k);
    std::vector<Cov> scatter(k);
    for (int j = 0; j < k; ++j) {
        Component &component = out.components[j];
        for (int i = 0; i < int(points.size()); ++i)
            counts[j] += e.records[i].responsibility[j];
        component.weight = counts[j] / points.size();
        for (int axis = 0; axis < 2; ++axis) {
            double sum = 0;
            for (int i = 0; i < int(points.size()); ++i)
                sum += e.records[i].responsibility[j] * points[i].xy[axis];
            component.mean[axis] = sum / counts[j];
        }
        for (int i = 0; i < int(points.size()); ++i) {
            const double r = e.records[i].responsibility[j], dx = points[i].xy[0] - component.mean[0],
                         dy = points[i].xy[1] - component.mean[1];
            scatter[j][0] += r * dx * dx;
            scatter[j][1] += r * dx * dy;
            scatter[j][2] += r * dy * dy;
        }
    }
    if (type == Type::TIED) {
        Cov shared{};
        for (int axis = 0; axis < 3; ++axis) {
            for (int j = 0; j < k; ++j)
                shared[axis] += scatter[j][axis];
            shared[axis] /= points.size();
            if (axis != 1)
                shared[axis] += epsilon;
        }
        for (auto &component : out.components)
            component.cov = shared;
    } else
        for (int j = 0; j < k; ++j) {
            const double a = scatter[j][0] / counts[j], b = scatter[j][1] / counts[j],
                         c = scatter[j][2] / counts[j];
            const double variance = (a + c) / 2 + epsilon;
            out.components[j].cov = type == Type::SPHERICAL
                                        ? Cov{variance, 0, variance}
                                        : Cov{a + epsilon, type == Type::FULL ? b : 0, c + epsilon};
        }
    return out;
}
Fit run_em(const std::vector<Point> &points, Model initial, Type type, const Params &p) {
    Fit out;
    out.model = adjust(std::move(initial), type);
    out.e = expectation(points, out.model);
    out.trace.push_back(out.e.loglik);
    const int k = out.model.components.size();
    for (int t = 1; t <= p.iterations; ++t) {
        out.model = update(points, out.e, k, type, p.epsilon);
        out.e = expectation(points, out.model);
        out.trace.push_back(out.e.loglik);
    }
    for (int t = 0; t <= p.iterations; ++t) {
        bool settled = true;
        for (int s = t; s <= p.iterations; ++s)
            if (std::abs(out.trace[s] - out.e.loglik) > p.tolerance)
                settled = false;
        if (settled) {
            out.settled = t;
            break;
        }
    }
    for (int t = 1; t <= p.iterations; ++t) {
        if (out.trace[t] - out.trace[t - 1] > out.trace[out.largest] - out.trace[out.largest - 1])
            out.largest = t;
        if (out.trace[t] < out.trace[t - 1] - 0.000001 * std::abs(out.trace[t - 1]))
            out.violations.push_back(t);
    }
    return out;
}
