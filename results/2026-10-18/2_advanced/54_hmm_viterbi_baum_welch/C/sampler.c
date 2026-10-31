#include "hmm.h"
static double uniform(Generator *generator) {
    generator->state = (48271 * generator->state) % 2147483647;
    return (double)generator->state / 2147483647;
}
int draw(const double *weights, int count, Generator *generator) {
    double total = 0;
    for (int i = 0; i < count; ++i)
        total += weights[i];
    double threshold = uniform(generator) * total, cumulative = 0;
    for (int i = 0; i < count; ++i) {
        cumulative += weights[i];
        if (threshold < cumulative)
            return i;
    }
    return count - 1;
}
Pair synthetic(Model model, int length, Generator *generator) {
    Pair out = {path_new(length), path_new(length)};
    for (int t = 0; t < length; ++t) {
        int state = draw(t == 0 ? model.initial : model.transition[out.path.data[t - 1]], model.k, generator);
        int symbol = draw(model.emission[state], model.m, generator);
        out.path.data[t] = state;
        out.observation.data[t] = symbol;
    }
    return out;
}
Path posterior_sample(Model model, FB fb, Generator *generator) {
    Path out = path_new(fb.length);
    out.data[fb.length - 1] = draw(fb.forward[fb.length - 1], model.k, generator);
    for (int t = fb.length - 2; t >= 0; --t) {
        double weights[4] = {0};
        for (int i = 0; i < model.k; ++i)
            weights[i] = fb.forward[t][i] * model.transition[i][out.data[t + 1]];
        out.data[t] = draw(weights, model.k, generator);
    }
    return out;
}
