#include "epidemic.h"
State initial_state(const Model *model) {
    State out = {0};
    if (model->kind == K_GENERATION) {
        out.count = 3;
        out.values[0] = 1;
    } else if (model->kind == K_SIR) {
        out.count = 4;
        out.values[0] = model->population - model->e0 - model->i0;
        out.values[1] = model->e0 + model->i0;
    } else if (model->kind == K_SEIRD) {
        out.count = 6;
        out.values[0] = model->population - model->e0 - model->i0;
        out.values[1] = model->e0;
        out.values[2] = model->i0;
    } else {
        out.count = 6 * model->group_count;
        for (int g = 0; g < model->group_count; ++g) {
            double e = model->e0 * (double)model->groups[g].population / model->population,
                   i = model->i0 * (double)model->groups[g].population / model->population;
            out.values[6 * g] = (double)model->groups[g].population - e - i;
            out.values[6 * g + 1] = e;
            out.values[6 * g + 2] = i;
        }
    }
    return out;
}
State rates(const Model *model, State state, double multiplier) {
    State out = {0};
    out.count = state.count;
    const double *y = state.values;
    double *r = out.values, beta = model->beta, gamma = model->gamma, sigma = model->sigma;
    if (model->kind == K_GENERATION) {
        r[0] = -sigma * y[0];
        r[1] = sigma * y[0] - gamma * y[1];
        r[2] = gamma * y[1];
    } else if (model->kind == K_SIR) {
        double flow = beta * multiplier * y[0] * y[1] / model->population;
        r[0] = -flow;
        r[1] = flow - gamma * y[1];
        r[2] = gamma * y[1];
        r[3] = flow;
    } else if (model->kind == K_SEIRD) {
        double flow = beta * multiplier * y[0] * y[2] / model->population;
        r[0] = -flow;
        r[1] = flow - sigma * y[1];
        r[2] = sigma * y[1] - gamma * y[2];
        r[3] = (1 - model->fatality) * gamma * y[2];
        r[4] = model->fatality * gamma * y[2];
        r[5] = sigma * y[1];
    } else
        for (int g = 0; g < model->group_count; ++g) {
            double sum = 0;
            for (int h = 0; h < model->group_count; ++h)
                sum += model->contacts[g][h] * y[6 * h + 2] / (double)model->groups[h].population;
            double lambda = beta * multiplier * sum, flow = lambda * y[6 * g], e = y[6 * g + 1],
                   i = y[6 * g + 2];
            r[6 * g] = -flow;
            r[6 * g + 1] = flow - sigma * e;
            r[6 * g + 2] = sigma * e - gamma * i;
            r[6 * g + 3] = (1 - model->groups[g].fatality) * gamma * i;
            r[6 * g + 4] = model->groups[g].fatality * gamma * i;
            r[6 * g + 5] = sigma * e;
        }
    return out;
}
void reset(const Model *model, State *state) {
    if (model->kind == K_GENERATION)
        state->values[2] = 0;
    else if (model->kind == K_SIR)
        state->values[3] = 0;
    else if (model->kind == K_SEIRD)
        state->values[5] = 0;
    else
        for (int g = 0; g < model->group_count; ++g)
            state->values[6 * g + 5] = 0;
}
