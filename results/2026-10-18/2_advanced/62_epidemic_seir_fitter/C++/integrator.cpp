#include "epidemic.hpp"
Field rk4(const Model &model, const Field &state, double multiplier) {
    constexpr double h = 0.25;
    const Field k1 = model.rates(state, multiplier);
    Field point(state.size());
    for (int i = 0; i < int(state.size()); ++i)
        point[i] = state[i] + (h / 2) * k1[i];
    const Field k2 = model.rates(point, multiplier);
    for (int i = 0; i < int(state.size()); ++i)
        point[i] = state[i] + (h / 2) * k2[i];
    const Field k3 = model.rates(point, multiplier);
    for (int i = 0; i < int(state.size()); ++i)
        point[i] = state[i] + h * k3[i];
    const Field k4 = model.rates(point, multiplier);
    Field out(state.size());
    for (int i = 0; i < int(state.size()); ++i)
        out[i] = state[i] + (h / 6) * (((k1[i] + 2 * k2[i]) + 2 * k3[i]) + k4[i]);
    return out;
}
States simulate(const Model &model, Field state, const Field &multipliers) {
    States out;
    for (double multiplier : multipliers) {
        model.reset(state);
        for (int step = 0; step < 4; ++step)
            state = rk4(model, state, multiplier);
        out.push_back(state);
    }
    return out;
}
