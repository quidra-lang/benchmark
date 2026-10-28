#include "reinforcement.h"
int choose(Table q, int state, Integer epsilon, Random *random) {
    if (draw(random) % 1000 < epsilon)
        return (int)(draw(random) % 4);
    return first_maximum(q[state]);
}
Integer next_value(Table q, int state, Integer epsilon, bool expected) {
    Integer maximum = q[state][first_maximum(q[state])];
    if (!expected)
        return maximum;
    Integer sum = 0;
    for (int a = 0; a < 4; ++a)
        sum += q[state][a];
    return floor_div(epsilon * sum + 4 * (1000 - epsilon) * maximum, 4000);
}
void td_update(const Model *model, Table q, int state, int action, int next, Integer r, Integer gamma,
               Integer alpha, Integer f) {
    Integer target = 10000 * r + (terminal(model->world, next) ? 0 : floor_div(gamma * f, 100));
    q[state][action] += floor_div(alpha * (target - q[state][action]), 100);
}
Dyna dyna_create(int states) {
    Dyna result = {0};
    result.entries = allocate(states, sizeof *result.entries);
    result.observed = allocate((size_t)states * 4, sizeof *result.observed);
    return result;
}
void dyna_record(Dyna *dyna, int state, int action, int next, Integer r) {
    ModelEntry *entry = &dyna->entries[state][action];
    if (!entry->known)
        dyna->observed[dyna->count++] = (Pair){state, action};
    *entry = (ModelEntry){true, next, r};
}
void dyna_plan(Dyna *dyna, const Model *model, Table q, int count, Integer gamma, Integer alpha,
               Random *random) {
    for (int i = 0; i < count; ++i) {
        Pair pair = dyna->observed[draw(random) % (Integer)dyna->count];
        ModelEntry entry = dyna->entries[pair.state][pair.action];
        int state = model->world->index[entry.next];
        Integer f = state < 0 ? 0 : next_value(q, state, 0, false);
        td_update(model, q, pair.state, pair.action, entry.next, entry.reward, gamma, alpha, f);
    }
}
