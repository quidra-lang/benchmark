#include "survival.hpp"
CoxEvaluation cox_evaluate(const Subjects &subjects, const std::vector<Vector> &design, int size,
                           const Vector &beta) {
    CoxEvaluation out;
    out.theta.resize(subjects.size());
    out.risks.resize(subjects.size());
    for (std::size_t j = 0; j < subjects.size(); ++j) {
        double theta = 0;
        for (int c = 0; c < size; ++c)
            theta += beta[c] * design[j][c];
        out.theta[j] = theta;
        out.risks[j] = std::exp(theta);
    }
    std::vector<int> order(subjects.size());
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        return subjects[a].time != subjects[b].time ? subjects[a].time > subjects[b].time
                                                    : subjects[a].id < subjects[b].id;
    });
    double s0 = 0;
    Vector s1{};
    Matrix s2{};
    std::size_t first = 0;
    while (first < order.size()) {
        const int time = subjects[order[first]].time;
        std::size_t last = first;
        while (last < order.size() && subjects[order[last]].time == time) {
            const int j = order[last];
            s0 += out.risks[j];
            for (int c = 0; c < size; ++c) {
                s1[c] += out.risks[j] * design[j][c];
                for (int d = 0; d < size; ++d)
                    s2[c][d] += out.risks[j] * design[j][c] * design[j][d];
            }
            ++last;
        }
        int events = 0;
        double theta_sum = 0;
        Vector x_sum{};
        for (std::size_t position = first; position < last; ++position) {
            const int i = order[position];
            if (!subjects[i].event)
                continue;
            ++events;
            theta_sum += out.theta[i];
            for (int c = 0; c < size; ++c)
                x_sum[c] += design[i][c];
        }
        if (events) {
            out.loglik += theta_sum - events * std::log(s0);
            for (int c = 0; c < size; ++c) {
                out.score[c] += x_sum[c] - events * s1[c] / s0;
                for (int d = 0; d < size; ++d)
                    out.information[c][d] += events * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0));
            }
            out.times.push_back({time, events, s0, s1});
        }
        first = last;
    }
    return out;
}
CoxFit cox_fit(const Subjects &subjects, const std::vector<Vector> &design, int size) {
    CoxFit out;
    out.initial = cox_evaluate(subjects, design, size, out.beta);
    CoxEvaluation current = out.initial;
    for (int iteration = 0; iteration < 25; ++iteration) {
        const Vector delta = solve(current.information, current.score, size);
        for (int c = 0; c < size; ++c)
            out.beta[c] = out.beta[c] + delta[c];
        out.iterations.push_back({current.loglik, out.beta});
        current = cox_evaluate(subjects, design, size, out.beta);
    }
    out.final = std::move(current);
    return out;
}
