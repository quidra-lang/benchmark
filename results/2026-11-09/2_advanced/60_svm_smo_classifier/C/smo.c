#include "classifier.h"
typedef struct {
    Model model;
    const Params *params;
    double errors[200];
} Trainer;
static bool nonbound(const Model *model, int i) {
    return model->alpha[i] > 0 && model->alpha[i] < model->c;
}
static double snap(double value, double c) {
    return value < 0.00000001 ? 0 : value > c - 0.00000001 ? c : value;
}
static bool take(Trainer *trainer, int i1, int i2) {
    if (i1 == i2)
        return false;
    Model *m = &trainer->model;
    int n = m->count, y1 = m->data[i1].label, y2 = m->data[i2].label;
    double alpha1 = m->alpha[i1], alpha2 = m->alpha[i2], e1 = trainer->errors[i1],
           e2 = trainer->errors[i2];
    double lo = y1 != y2 ? fmax(0, alpha2 - alpha1) : fmax(0, alpha2 + alpha1 - m->c),
           hi = y1 != y2 ? fmin(m->c, m->c + alpha2 - alpha1) : fmin(m->c, alpha2 + alpha1);
    if (lo == hi)
        return false;
    double k11 = m->matrix[i1 * n + i1], k12 = m->matrix[i1 * n + i2], k22 = m->matrix[i2 * n + i2],
           eta = k11 + k22 - 2 * k12;
    if (eta <= 0)
        return false;
    double a2 = alpha2 + y2 * (e1 - e2) / eta;
    int clipping = 0;
    if (a2 < lo) {
        a2 = lo;
        clipping = 1;
    } else if (a2 > hi) {
        a2 = hi;
        clipping = 2;
    }
    a2 = snap(a2, m->c);
    if (fabs(a2 - alpha2) < trainer->params->epsilon * (a2 + alpha2 + trainer->params->epsilon))
        return false;
    double a1 = snap(alpha1 + y1 * y2 * (alpha2 - a2), m->c), t1 = y1 * (a1 - alpha1),
           t2 = y2 * (a2 - alpha2), b1 = e1 + t1 * k11 + t2 * k12 + m->b,
           b2 = e2 + t1 * k12 + t2 * k22 + m->b,
           threshold = a1 > 0 && a1 < m->c   ? b1
                       : a2 > 0 && a2 < m->c ? b2
                                             : (b1 + b2) / 2,
           delta = threshold - m->b;
    for (int i = 0; i < n; ++i)
        trainer->errors[i] =
            trainer->errors[i] + (t1 * m->matrix[i1 * n + i] + t2 * m->matrix[i2 * n + i] - delta);
    if (a1 > 0 && a1 < m->c)
        trainer->errors[i1] = 0;
    if (a2 > 0 && a2 < m->c)
        trainer->errors[i2] = 0;
    m->alpha[i1] = a1;
    m->alpha[i2] = a2;
    m->b = threshold;
    ++m->steps;
    ++m->clipping[clipping];
    return true;
}
static int examine(Trainer *trainer, int i2) {
    Model *m = &trainer->model;
    ++m->examined;
    double r2 = trainer->errors[i2] * m->data[i2].label;
    if (!((r2 < -trainer->params->tolerance && m->alpha[i2] < m->c) ||
          (r2 > trainer->params->tolerance && m->alpha[i2] > 0)))
        return 0;
    int best = -1;
    double distance = -1;
    for (int i = 0; i < m->count; ++i)
        if (i != i2 && nonbound(m, i)) {
            double value = fabs(trainer->errors[i] - trainer->errors[i2]);
            if (value > distance) {
                best = i;
                distance = value;
            }
        }
    if (best >= 0 && take(trainer, best, i2)) {
        ++m->choices[0];
        return 1;
    }
    for (int i = 0; i < m->count; ++i)
        if (nonbound(m, i) && take(trainer, i, i2)) {
            ++m->choices[1];
            return 1;
        }
    for (int i = 0; i < m->count; ++i)
        if (take(trainer, i, i2)) {
            ++m->choices[2];
            return 1;
        }
    return 0;
}
Model train(const Example *data, int count, Kernel kernel, const double *matrix, double c,
            const Params *params) {
    Trainer trainer = {0};
    trainer.params = params;
    Model *model = &trainer.model;
    model->data = data;
    model->count = count;
    model->kernel = kernel;
    model->matrix = matrix;
    model->c = c;
    for (int i = 0; i < count; ++i)
        trainer.errors[i] = -data[i].label;
    bool all = true;
    while (true) {
        int before = model->examined, changed = 0;
        for (int i = 0; i < count; ++i)
            if (all || nonbound(model, i))
                changed += examine(&trainer, i);
        if (all)
            ++model->full;
        else
            ++model->nonbound;
        if (model->pass_count == model->pass_capacity) {
            model->pass_capacity = model->pass_capacity ? 2 * model->pass_capacity : 16;
            Pass *passes = realloc(model->passes, (size_t)model->pass_capacity * sizeof(Pass));
            if (!passes)
                exit(EXIT_FAILURE);
            model->passes = passes;
        }
        Pass pass = {all, model->examined - before, changed, NULL};
        if (all) {
            pass.alpha = malloc((size_t)count * sizeof(double));
            if (!pass.alpha)
                exit(EXIT_FAILURE);
            memcpy(pass.alpha, model->alpha, (size_t)count * sizeof(double));
        }
        model->passes[model->pass_count++] = pass;
        if (all && changed == 0) {
            model->converged = true;
            break;
        }
        if (model->pass_count == params->max_passes)
            break;
        if (all)
            all = false;
        else if (changed == 0)
            all = true;
    }
    return trainer.model;
}
void free_model(Model *model) {
    for (int i = 0; i < model->pass_count; ++i)
        free(model->passes[i].alpha);
    free(model->passes);
}
double decision(const Model *model, const double *point) {
    double out = 0;
    for (int i = 0; i < model->count; ++i)
        if (model->alpha[i] > 0)
            out += model->alpha[i] * model->data[i].label *
                   kernel_value(model->kernel, model->data[i].point, point);
    return out - model->b;
}
void training_decisions(const Model *model, double *out) {
    for (int i = 0; i < model->count; ++i) {
        double value = 0;
        for (int j = 0; j < model->count; ++j)
            if (model->alpha[j] > 0)
                value +=
                    model->alpha[j] * model->data[j].label * model->matrix[i * model->count + j];
        out[i] = value - model->b;
    }
}
