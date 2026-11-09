#include "hmm.hpp"
static Model smoothed(Model out, StateValues initial, Matrix transition, Emissions emissions, double alpha,
                      const std::string &name) {
    out.name = name;
    for (int i = 0; i < out.k(); ++i) {
        initial[i] += alpha;
        for (int j = 0; j < out.k(); ++j)
            transition[i][j] += alpha;
        for (int j = 0; j < out.m(); ++j)
            emissions[i][j] += alpha;
        normalize(transition[i].data(), out.k());
        normalize(emissions[i].data(), out.m());
    }
    normalize(initial.data(), out.k());
    out.initial = initial;
    out.transition = transition;
    out.emission = emissions;
    return out;
}
Model baum_welch(const Model &model, const std::vector<Path> &observations, double alpha) {
    StateValues initial{};
    Matrix transition{};
    Emissions emissions{};
    for (const Path &observation : observations) {
        const FB fb = forward_backward(model, observation);
        for (int i = 0; i < model.k(); ++i)
            initial[i] += fb.posterior[0][i];
        for (int t = 0; t < int(observation.size()); ++t)
            for (int i = 0; i < model.k(); ++i) {
                if (observation[t] >= 0)
                    emissions[i][observation[t]] += fb.posterior[t][i];
                if (t + 1 < int(observation.size()))
                    for (int j = 0; j < model.k(); ++j)
                        transition[i][j] += transition_posterior(model, fb, t, i, j);
            }
    }
    return smoothed(model, initial, transition, emissions, alpha, "BAUM_WELCH");
}
Model counting(const Model &model, const std::vector<Pair> &pairs, double alpha, const std::string &name) {
    StateValues initial{};
    Matrix transition{};
    Emissions emissions{};
    for (const Pair &pair : pairs) {
        ++initial[pair.path[0]];
        for (int t = 0; t < int(pair.path.size()); ++t) {
            const int i = pair.path[t];
            if (pair.observation[t] >= 0)
                ++emissions[i][pair.observation[t]];
            if (t + 1 < int(pair.path.size()))
                ++transition[i][pair.path[t + 1]];
        }
    }
    return smoothed(model, initial, transition, emissions, alpha, name);
}
double total_loglik(const Model &model, const std::vector<Path> &observations) {
    double sum = 0;
    for (const Path &observation : observations)
        sum += forward_backward(model, observation).loglik;
    return sum;
}
