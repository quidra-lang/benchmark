#include "hmm.h"
int maximum(const double *values, int count) {
    int chosen = 0;
    for (int i = 1; i < count; ++i)
        if (values[i] > values[chosen])
            chosen = i;
    return chosen;
}
double emission(Model model, int observation, int state) {
    return observation < 0 ? 1 : model.emission[state][observation];
}
FB forward_backward(Model model, Path observation) {
    int length = observation.count, k = model.k;
    FB out = {.forward = allocate(length, sizeof(double[4])),
              .backward = allocate(length, sizeof(double[4])),
              .posterior = allocate(length, sizeof(double[4])),
              .emissions = allocate(length, sizeof(double[4])),
              .scales = allocate(length, sizeof(double)),
              .length = length};
    for (int t = 0; t < length; ++t) {
        for (int j = 0; j < k; ++j) {
            out.emissions[t][j] = emission(model, observation.data[t], j);
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
        out.loglik += log(out.scales[t]);
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
double transition_posterior(Model model, FB fb, int t, int i, int j) {
    return fb.forward[t][i] * model.transition[i][j] * fb.emissions[t + 1][j] * fb.backward[t + 1][j] /
           fb.scales[t + 1];
}
Viterbi viterbi(Model model, Path observation) {
    int k = model.k, length = observation.count;
    double transitions[4][4] = {0}, scores[4] = {0};
    int predecessors[300][4] = {0};
    for (int i = 0; i < k; ++i)
        for (int j = 0; j < k; ++j)
            transitions[i][j] = log(model.transition[i][j]);
    for (int j = 0; j < k; ++j)
        scores[j] = log(model.initial[j]) +
                    (observation.data[0] < 0 ? 0 : log(model.emission[j][observation.data[0]]));
    for (int t = 1; t < length; ++t) {
        double next[4] = {0};
        for (int j = 0; j < k; ++j) {
            double candidates[4];
            for (int i = 0; i < k; ++i)
                candidates[i] = scores[i] + transitions[i][j];
            int previous = maximum(candidates, k);
            predecessors[t][j] = previous;
            next[j] = candidates[previous] +
                      (observation.data[t] < 0 ? 0 : log(model.emission[j][observation.data[t]]));
        }
        memcpy(scores, next, sizeof(scores));
    }
    Viterbi out = {.path = path_new(length)};
    out.path.data[length - 1] = maximum(scores, k);
    out.logprob = scores[out.path.data[length - 1]];
    for (int t = length - 1; t > 0; --t)
        out.path.data[t - 1] = predecessors[t][out.path.data[t]];
    return out;
}
Decoding decode(Model model, Path observation) {
    Decoding out = {.fb = forward_backward(model, observation),
                    .viterbi = viterbi(model, observation),
                    .posterior = path_new(observation.count),
                    .confidence = allocate(observation.count, sizeof(double))};
    for (int t = 0; t < observation.count; ++t) {
        int state = maximum(out.fb.posterior[t], model.k);
        out.posterior.data[t] = state;
        out.confidence[t] = out.fb.posterior[t][state];
    }
    return out;
}
