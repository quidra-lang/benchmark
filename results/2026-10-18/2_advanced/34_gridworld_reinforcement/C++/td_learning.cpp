#include "reinforcement.hpp"
int choose(const Table &q, int state, Integer epsilon, Random &random) {
    if (random.draw() % 1000 < epsilon)
        return random.draw() % 4;
    return first_maximum(q[state]);
}
Integer next_value(const Table &q, int state, Integer epsilon, bool expected) {
    const Integer maximum = q[state][first_maximum(q[state])];
    if (!expected)
        return maximum;
    Integer sum = 0;
    for (Integer value : q[state])
        sum += value;
    return floor_div(epsilon * sum + 4 * (1000 - epsilon) * maximum, 4000);
}
void td_update(const Model &model, Table &q, int state, int action, int next, Integer r, Integer gamma,
               Integer alpha, Integer f) {
    const Integer target = 10000 * r + (terminal(*model.world, next) ? 0 : floor_div(gamma * f, 100));
    q[state][action] += floor_div(alpha * (target - q[state][action]), 100);
}
void Dyna::record(int state, int action, int next, Integer r) {
    if (!known[state][action]) {
        known[state][action] = true;
        observed.emplace_back(state, action);
    }
    entries[state][action] = {next, r};
}
void Dyna::plan(const Model &model, Table &q, int count, Integer gamma, Integer alpha, Random &random) {
    for (int i = 0; i < count; ++i) {
        const auto pair = observed[random.draw() % observed.size()];
        const auto entry = entries[pair.first][pair.second];
        const int state = model.world->index[entry.first];
        const Integer f = state < 0 ? 0 : next_value(q, state, 0, false);
        td_update(model, q, pair.first, pair.second, entry.first, entry.second, gamma, alpha, f);
    }
}
