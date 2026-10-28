#include "reinforcement.hpp"
Integer discounted(const Values &rewards, Integer gamma) {
    Integer value = 0;
    for (auto r = rewards.rbegin(); r != rewards.rend(); ++r)
        value = 10000 * (*r) + floor_div(gamma * value, 100);
    return value;
}
void monte_carlo(const std::vector<Sample> &steps, Table &q, Table &sums, Table &counts, Integer gamma) {
    std::vector<std::array<int, 4>> first(q.size());
    for (auto &row : first)
        row.fill(-1);
    for (std::size_t i = 0; i < steps.size(); ++i) {
        const Sample &s = steps[i];
        if (first[s.state][s.action] < 0)
            first[s.state][s.action] = i;
    }
    Integer value = 0;
    for (int i = int(steps.size()) - 1; i >= 0; --i) {
        const Sample &s = steps[i];
        value = 10000 * s.reward + floor_div(gamma * value, 100);
        if (first[s.state][s.action] == i) {
            sums[s.state][s.action] += value;
            ++counts[s.state][s.action];
            q[s.state][s.action] = floor_div(sums[s.state][s.action], counts[s.state][s.action]);
        }
    }
}
