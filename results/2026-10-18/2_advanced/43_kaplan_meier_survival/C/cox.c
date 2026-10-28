#include "survival.h"
CoxEvaluation cox_evaluate(const Subjects *subjects, const Vector *design, int size, Vector beta) {
    CoxEvaluation out = {0};
    for (int j = 0; j < subjects->count; ++j) {
        double theta = 0;
        for (int c = 0; c < size; ++c)
            theta += beta.v[c] * design[j].v[c];
        out.theta[j] = theta;
        out.risks[j] = exp(theta);
    }
    int order[400];
    for (int i = 0; i < subjects->count; ++i) {
        int j = i;
        while (j > 0 && (subjects->data[i].time > subjects->data[order[j - 1]].time ||
                         (subjects->data[i].time == subjects->data[order[j - 1]].time &&
                          subjects->data[i].id < subjects->data[order[j - 1]].id))) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = i;
    }
    double s0 = 0;
    Vector s1 = {0};
    Matrix s2 = {0};
    int first = 0;
    while (first < subjects->count) {
        int time = subjects->data[order[first]].time, last = first;
        while (last < subjects->count && subjects->data[order[last]].time == time) {
            int j = order[last];
            s0 += out.risks[j];
            for (int c = 0; c < size; ++c) {
                s1.v[c] += out.risks[j] * design[j].v[c];
                for (int d = 0; d < size; ++d)
                    s2.v[c][d] += out.risks[j] * design[j].v[c] * design[j].v[d];
            }
            ++last;
        }
        int events = 0;
        double theta_sum = 0;
        Vector x_sum = {0};
        for (int position = first; position < last; ++position) {
            int i = order[position];
            if (!subjects->data[i].event)
                continue;
            ++events;
            theta_sum += out.theta[i];
            for (int c = 0; c < size; ++c)
                x_sum.v[c] += design[i].v[c];
        }
        if (events) {
            out.loglik += theta_sum - events * log(s0);
            for (int c = 0; c < size; ++c) {
                out.score.v[c] += x_sum.v[c] - events * s1.v[c] / s0;
                for (int d = 0; d < size; ++d)
                    out.information.v[c][d] += events * (s2.v[c][d] / s0 - (s1.v[c] / s0) * (s1.v[d] / s0));
            }
            out.times[out.time_count++] = (CoxTime){time, events, s0, s1};
        }
        first = last;
    }
    return out;
}
CoxFit *cox_fit(const Subjects *subjects, const Vector *design, int size) {
    CoxFit *out = calloc(1, sizeof(CoxFit));
    out->initial = cox_evaluate(subjects, design, size, out->beta);
    CoxEvaluation current = out->initial;
    for (int iteration = 0; iteration < 25; ++iteration) {
        Vector delta = solve(current.information, current.score, size);
        for (int c = 0; c < size; ++c)
            out->beta.v[c] = out->beta.v[c] + delta.v[c];
        out->iterations[iteration] = (Iteration){current.loglik, out->beta};
        current = cox_evaluate(subjects, design, size, out->beta);
    }
    out->final = current;
    return out;
}
