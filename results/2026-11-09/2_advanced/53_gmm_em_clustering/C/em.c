#include "mixture.h"
Model adjust(Model initial, Type type) {
    initial.type = type;
    if (type == TIED) {
        Cov shared = {0};
        for (int k = 0; k < initial.k; ++k) {
            Component component = initial.components[k];
            shared.a += component.weight * component.cov.a;
            shared.b += component.weight * component.cov.b;
            shared.c += component.weight * component.cov.c;
        }
        for (int k = 0; k < initial.k; ++k)
            initial.components[k].cov = shared;
    } else
        for (int k = 0; k < initial.k; ++k) {
            Component *component = &initial.components[k];
            if (type == DIAG)
                component->cov.b = 0;
            else if (type == SPHERICAL) {
                double variance = (component->cov.a + component->cov.c) / 2;
                component->cov = (Cov){variance, 0, variance};
            }
        }
    return initial;
}
void expectation(const Point *points, int count, Model model, Expectation *out) {
    out->loglik = 0;
    for (int i = 0; i < count; ++i) {
        Record *record = &out->records[i];
        double maximum = -INFINITY;
        for (int k = 0; k < model.k; ++k) {
            record->scores[k] = weighted_log(points[i].xy, model.components[k]);
            if (record->scores[k] > maximum)
                maximum = record->scores[k];
        }
        double sum = 0;
        for (int k = 0; k < model.k; ++k) {
            record->responsibility[k] = exp(record->scores[k] - maximum);
            sum += record->responsibility[k];
        }
        for (int k = 0; k < model.k; ++k)
            record->responsibility[k] /= sum;
        record->log_density = maximum + log(sum);
        out->loglik += record->log_density;
    }
}
static Model update(const Point *points, int count, const Expectation *e, int k, Type type, double epsilon) {
    Model out = {.k = k, .type = type};
    double counts[4] = {0};
    Cov scatter[4] = {0};
    for (int j = 0; j < k; ++j) {
        Component *component = &out.components[j];
        for (int i = 0; i < count; ++i)
            counts[j] += e->records[i].responsibility[j];
        component->weight = counts[j] / count;
        for (int i = 0; i < count; ++i) {
            component->mean.x += e->records[i].responsibility[j] * points[i].xy.x;
            component->mean.y += e->records[i].responsibility[j] * points[i].xy.y;
        }
        component->mean.x /= counts[j];
        component->mean.y /= counts[j];
        for (int i = 0; i < count; ++i) {
            double r = e->records[i].responsibility[j], dx = points[i].xy.x - component->mean.x,
                   dy = points[i].xy.y - component->mean.y;
            scatter[j].a += r * dx * dx;
            scatter[j].b += r * dx * dy;
            scatter[j].c += r * dy * dy;
        }
    }
    if (type == TIED) {
        Cov shared = {0};
        for (int j = 0; j < k; ++j) {
            shared.a += scatter[j].a;
            shared.b += scatter[j].b;
            shared.c += scatter[j].c;
        }
        shared.a = shared.a / count + epsilon;
        shared.b /= count;
        shared.c = shared.c / count + epsilon;
        for (int j = 0; j < k; ++j)
            out.components[j].cov = shared;
    } else
        for (int j = 0; j < k; ++j) {
            double a = scatter[j].a / counts[j], b = scatter[j].b / counts[j], c = scatter[j].c / counts[j],
                   variance = (a + c) / 2 + epsilon;
            out.components[j].cov = type == SPHERICAL ? (Cov){variance, 0, variance}
                                                      : (Cov){a + epsilon, type == FULL ? b : 0, c + epsilon};
        }
    return out;
}
void run_em(const Point *points, int count, Model initial, Type type, const Params *p, Fit *out) {
    out->model = adjust(initial, type);
    expectation(points, count, out->model, &out->e);
    out->trace[0] = out->e.loglik;
    out->violation_count = 0;
    out->largest = 1;
    for (int t = 1; t <= p->iterations; ++t) {
        out->model = update(points, count, &out->e, initial.k, type, p->epsilon);
        expectation(points, count, out->model, &out->e);
        out->trace[t] = out->e.loglik;
    }
    for (int t = 0; t <= p->iterations; ++t) {
        bool settled = true;
        for (int s = t; s <= p->iterations; ++s)
            if (fabs(out->trace[s] - out->e.loglik) > p->tolerance)
                settled = false;
        if (settled) {
            out->settled = t;
            break;
        }
    }
    for (int t = 1; t <= p->iterations; ++t) {
        if (out->trace[t] - out->trace[t - 1] > out->trace[out->largest] - out->trace[out->largest - 1])
            out->largest = t;
        if (out->trace[t] < out->trace[t - 1] - 0.000001 * fabs(out->trace[t - 1]))
            out->violations[out->violation_count++] = t;
    }
}
