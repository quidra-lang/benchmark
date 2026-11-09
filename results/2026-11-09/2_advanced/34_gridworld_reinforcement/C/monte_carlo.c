#include "reinforcement.h"
Integer discounted(const Integer *rewards, int count, Integer gamma) {
    Integer value = 0;
    for (int i = count - 1; i >= 0; --i)
        value = 10000 * rewards[i] + floor_div(gamma * value, 100);
    return value;
}
void monte_carlo(const Sample *steps, int count, Table q, Table sums, Table counts, int states,
                 Integer gamma) {
    int (*first)[4] = allocate(states, sizeof *first);
    for (int s = 0; s < states; ++s)
        for (int a = 0; a < 4; ++a)
            first[s][a] = -1;
    for (int i = 0; i < count; ++i)
        if (first[steps[i].state][steps[i].action] < 0)
            first[steps[i].state][steps[i].action] = i;
    Integer value = 0;
    for (int i = count - 1; i >= 0; --i) {
        Sample s = steps[i];
        value = 10000 * s.reward + floor_div(gamma * value, 100);
        if (first[s.state][s.action] == i) {
            sums[s.state][s.action] += value;
            ++counts[s.state][s.action];
            q[s.state][s.action] = floor_div(sums[s.state][s.action], counts[s.state][s.action]);
        }
    }
    free(first);
}
