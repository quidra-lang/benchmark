#include "epidemic.h"
State rk4(const Model *model, State state, double multiplier) {
    const double h = 0.25;
    State k1 = rates(model, state, multiplier), point = state;
    for (int i = 0; i < state.count; ++i)
        point.values[i] = state.values[i] + (h / 2) * k1.values[i];
    State k2 = rates(model, point, multiplier);
    for (int i = 0; i < state.count; ++i)
        point.values[i] = state.values[i] + (h / 2) * k2.values[i];
    State k3 = rates(model, point, multiplier);
    for (int i = 0; i < state.count; ++i)
        point.values[i] = state.values[i] + h * k3.values[i];
    State k4 = rates(model, point, multiplier), out = state;
    for (int i = 0; i < state.count; ++i)
        out.values[i] =
            state.values[i] +
            (h / 6) * (((k1.values[i] + 2 * k2.values[i]) + 2 * k3.values[i]) + k4.values[i]);
    return out;
}
Trajectory simulate(const Model *model, State state, const double *multipliers, int count) {
    Trajectory out = {allocate((size_t)count, sizeof(State)), count};
    for (int day = 0; day < count; ++day) {
        reset(model, &state);
        for (int step = 0; step < 4; ++step)
            state = rk4(model, state, multipliers[day]);
        out.states[day] = state;
    }
    return out;
}
