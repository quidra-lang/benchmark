#include "hmm.h"
static Model smoothed(Model out, double *initial, double transition[4][4], double emissions[4][8],
                      double alpha, const char *name) {
    out.name = name;
    for (int i = 0; i < out.k; ++i) {
        initial[i] += alpha;
        for (int j = 0; j < out.k; ++j)
            transition[i][j] += alpha;
        for (int j = 0; j < out.m; ++j)
            emissions[i][j] += alpha;
        normalize(transition[i], out.k);
        normalize(emissions[i], out.m);
    }
    normalize(initial, out.k);
    memcpy(out.initial, initial, sizeof(out.initial));
    memcpy(out.transition, transition, sizeof(out.transition));
    memcpy(out.emission, emissions, sizeof(out.emission));
    return out;
}
Model baum_welch(Model model, const Path *observations, int count, double alpha) {
    double initial[4] = {0}, transition[4][4] = {0}, emissions[4][8] = {0};
    for (int sequence = 0; sequence < count; ++sequence) {
        void *mark = allocation_mark();
        Path observation = observations[sequence];
        FB fb = forward_backward(model, observation);
        for (int i = 0; i < model.k; ++i)
            initial[i] += fb.posterior[0][i];
        for (int t = 0; t < observation.count; ++t)
            for (int i = 0; i < model.k; ++i) {
                if (observation.data[t] >= 0)
                    emissions[i][observation.data[t]] += fb.posterior[t][i];
                if (t + 1 < observation.count)
                    for (int j = 0; j < model.k; ++j)
                        transition[i][j] += transition_posterior(model, fb, t, i, j);
            }
        release_to(mark);
    }
    return smoothed(model, initial, transition, emissions, alpha, "BAUM_WELCH");
}
Model counting(Model model, const Pair *pairs, int count, double alpha, const char *name) {
    double initial[4] = {0}, transition[4][4] = {0}, emissions[4][8] = {0};
    for (int pair_index = 0; pair_index < count; ++pair_index) {
        Pair pair = pairs[pair_index];
        ++initial[pair.path.data[0]];
        for (int t = 0; t < pair.path.count; ++t) {
            int i = pair.path.data[t];
            if (pair.observation.data[t] >= 0)
                ++emissions[i][pair.observation.data[t]];
            if (t + 1 < pair.path.count)
                ++transition[i][pair.path.data[t + 1]];
        }
    }
    return smoothed(model, initial, transition, emissions, alpha, name);
}
double total_loglik(Model model, const Path *observations, int count) {
    double sum = 0;
    for (int i = 0; i < count; ++i) {
        void *mark = allocation_mark();
        sum += forward_backward(model, observations[i]).loglik;
        release_to(mark);
    }
    return sum;
}
