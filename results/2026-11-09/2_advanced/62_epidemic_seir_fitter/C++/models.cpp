#include "epidemic.hpp"
Field Model::initial() const {
    if (kind == Kind::generation)
        return {1, 0, 0};
    if (kind == Kind::sir)
        return {population - e0 - i0, e0 + i0, 0, 0};
    if (kind == Kind::seird)
        return {population - e0 - i0, e0, i0, 0, 0, 0};
    Field out(groups.size() * 6);
    for (int g = 0; g < int(groups.size()); ++g) {
        const double e = e0 * double(groups[g].population) / population,
                     i = i0 * double(groups[g].population) / population;
        out[6 * g] = double(groups[g].population) - e - i;
        out[6 * g + 1] = e;
        out[6 * g + 2] = i;
    }
    return out;
}
Field Model::rates(const Field &state, double multiplier) const {
    if (kind == Kind::generation)
        return {-sigma * state[0], sigma * state[0] - gamma * state[1], gamma * state[1]};
    if (kind == Kind::sir) {
        const double flow = beta * multiplier * state[0] * state[1] / population;
        return {-flow, flow - gamma * state[1], gamma * state[1], flow};
    }
    if (kind == Kind::seird) {
        const double flow = beta * multiplier * state[0] * state[2] / population;
        return {-flow,
                flow - sigma * state[1],
                sigma * state[1] - gamma * state[2],
                (1 - fatality) * gamma * state[2],
                fatality * gamma * state[2],
                sigma * state[1]};
    }
    Field out(state.size());
    for (int g = 0; g < int(groups.size()); ++g) {
        double sum = 0;
        for (int h = 0; h < int(groups.size()); ++h)
            sum += contacts[g][h] * state[6 * h + 2] / double(groups[h].population);
        const double lambda = beta * multiplier * sum, flow = lambda * state[6 * g],
                     e = state[6 * g + 1], i = state[6 * g + 2];
        out[6 * g] = -flow;
        out[6 * g + 1] = flow - sigma * e;
        out[6 * g + 2] = sigma * e - gamma * i;
        out[6 * g + 3] = (1 - groups[g].fatality) * gamma * i;
        out[6 * g + 4] = groups[g].fatality * gamma * i;
        out[6 * g + 5] = sigma * e;
    }
    return out;
}
void Model::reset(Field &state) const {
    if (kind == Kind::generation)
        state[2] = 0;
    else if (kind == Kind::sir)
        state[3] = 0;
    else if (kind == Kind::seird)
        state[5] = 0;
    else
        for (int g = 0; g < int(groups.size()); ++g)
            state[6 * g + 5] = 0;
}
