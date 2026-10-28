#include "hmm.hpp"
double Generator::uniform() {
    state = (48271 * state) % 2147483647;
    return double(state) / 2147483647;
}
int draw(const double *weights, int count, Generator &generator) {
    double total = 0;
    for (int i = 0; i < count; ++i)
        total += weights[i];
    const double threshold = generator.uniform() * total;
    double cumulative = 0;
    for (int i = 0; i < count; ++i) {
        cumulative += weights[i];
        if (threshold < cumulative)
            return i;
    }
    return count - 1;
}
Pair synthetic(const Model &model, int length, Generator &generator) {
    Pair out;
    for (int t = 0; t < length; ++t) {
        const int state = draw(t == 0 ? model.initial.data() : model.transition[out.path.back()].data(),
                               model.k(), generator);
        const int symbol = draw(model.emission[state].data(), model.m(), generator);
        out.path.push_back(state);
        out.observation.push_back(symbol);
    }
    return out;
}
Path posterior_sample(const Model &model, const FB &fb, Generator &generator) {
    Path out(fb.forward.size());
    out.back() = draw(fb.forward.back().data(), model.k(), generator);
    for (int t = int(out.size()) - 2; t >= 0; --t) {
        StateValues weights{};
        for (int i = 0; i < model.k(); ++i)
            weights[i] = fb.forward[t][i] * model.transition[i][out[t + 1]];
        out[t] = draw(weights.data(), model.k(), generator);
    }
    return out;
}
