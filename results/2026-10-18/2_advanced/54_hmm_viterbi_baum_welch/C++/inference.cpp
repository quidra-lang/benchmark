#include "hmm.hpp"
int maximum(const double *values, int count) {
    int chosen = 0;
    for (int i = 1; i < count; ++i)
        if (values[i] > values[chosen])
            chosen = i;
    return chosen;
}
double emission(const Model &model, int observation, int state) {
    return observation < 0 ? 1 : model.emission[state][observation];
}
FB forward_backward(const Model &model, const Path &observation) {
    const int length = observation.size(), k = model.k();
    FB out;
    out.forward.resize(length);
    out.backward.resize(length);
    out.posterior.resize(length);
    out.emissions.resize(length);
    out.scales.resize(length);
    for (int t = 0; t < length; ++t) {
        for (int j = 0; j < k; ++j) {
            out.emissions[t][j] = emission(model, observation[t], j);
            double value = model.initial[j];
            if (t) {
                value = 0;
                for (int i = 0; i < k; ++i)
                    value += out.forward[t - 1][i] * model.transition[i][j];
            }
            out.forward[t][j] = value * out.emissions[t][j];
            out.scales[t] += out.forward[t][j];
        }
        for (int j = 0; j < k; ++j)
            out.forward[t][j] /= out.scales[t];
        out.loglik += std::log(out.scales[t]);
    }
    for (int i = 0; i < k; ++i)
        out.backward[length - 1][i] = 1;
    for (int t = length - 2; t >= 0; --t)
        for (int i = 0; i < k; ++i) {
            double sum = 0;
            for (int j = 0; j < k; ++j)
                sum += model.transition[i][j] * out.emissions[t + 1][j] * out.backward[t + 1][j];
            out.backward[t][i] = sum / out.scales[t + 1];
        }
    for (int t = 0; t < length; ++t)
        for (int i = 0; i < k; ++i)
            out.posterior[t][i] = out.forward[t][i] * out.backward[t][i];
    return out;
}
double transition_posterior(const Model &model, const FB &fb, int t, int i, int j) {
    return fb.forward[t][i] * model.transition[i][j] * fb.emissions[t + 1][j] * fb.backward[t + 1][j] /
           fb.scales[t + 1];
}
Viterbi viterbi(const Model &model, const Path &observation) {
    const int k = model.k(), length = observation.size();
    Matrix transitions{};
    for (int i = 0; i < k; ++i)
        for (int j = 0; j < k; ++j)
            transitions[i][j] = std::log(model.transition[i][j]);
    std::vector<std::array<int, 4>> predecessors(length);
    StateValues scores{};
    for (int j = 0; j < k; ++j)
        scores[j] = std::log(model.initial[j]) +
                    (observation[0] < 0 ? 0 : std::log(model.emission[j][observation[0]]));
    for (int t = 1; t < length; ++t) {
        StateValues next{};
        for (int j = 0; j < k; ++j) {
            StateValues candidates{};
            for (int i = 0; i < k; ++i)
                candidates[i] = scores[i] + transitions[i][j];
            const int previous = maximum(candidates.data(), k);
            predecessors[t][j] = previous;
            next[j] =
                candidates[previous] + (observation[t] < 0 ? 0 : std::log(model.emission[j][observation[t]]));
        }
        scores = next;
    }
    Viterbi out;
    out.path.resize(length);
    out.path.back() = maximum(scores.data(), k);
    out.logprob = scores[out.path.back()];
    for (int t = length - 1; t > 0; --t)
        out.path[t - 1] = predecessors[t][out.path[t]];
    return out;
}
Decoding decode(const Model &model, const Path &observation) {
    Decoding out;
    out.fb = forward_backward(model, observation);
    out.viterbi = viterbi(model, observation);
    for (const auto &probabilities : out.fb.posterior) {
        int state = maximum(probabilities.data(), model.k());
        out.posterior.push_back(state);
        out.confidence.push_back(probabilities[state]);
    }
    return out;
}
