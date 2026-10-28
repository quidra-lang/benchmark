#include "reinforcement.h"
int first_maximum(const Integer values[4]) {
    int a = 0;
    for (int i = 1; i < 4; ++i)
        if (values[i] > values[a])
            a = i;
    return a;
}
Integer bellman(const Model *model, const Integer *values, int state, int action, Integer gamma) {
    Transitions ts = transitions(model, state, action);
    Integer sum = 0;
    for (int i = 0; i < ts.count; ++i) {
        Transition t = ts.data[i];
        int next = model->world->index[t.cell];
        sum += t.weight * (10000 * reward(model->world, t.cell, model->step_reward) +
                           (next < 0 ? 0 : floor_div(gamma * values[next], 100)));
    }
    return floor_div(sum, model->q);
}
Table action_values(const Model *model, const Integer *values, Integer gamma) {
    int n = model->world->n;
    Table q = allocate(n, sizeof *q);
    for (int s = 0; s < n; ++s)
        for (int a = 0; a < 4; ++a)
            q[s][a] = bellman(model, values, s, a, gamma);
    return q;
}
int *greedy(Table values, int count) {
    int *policy = allocate(count, sizeof *policy);
    for (int s = 0; s < count; ++s)
        policy[s] = first_maximum(values[s]);
    return policy;
}
Iteration value_iteration(const Model *model, Integer gamma, Integer theta) {
    int n = model->world->n;
    Iteration out = {0};
    out.values = allocate(n, sizeof *out.values);
    for (;;) {
        Table q = action_values(model, out.values, gamma);
        Integer *next = allocate(n, sizeof *next), delta = 0;
        for (int s = 0; s < n; ++s) {
            next[s] = q[s][first_maximum(q[s])];
            Integer difference = absolute(next[s] - out.values[s]);
            if (difference > delta)
                delta = difference;
        }
        free(q);
        free(out.values);
        out.values = next;
        grow((void **)&out.deltas, &out.cap, out.count + 1, sizeof *out.deltas);
        out.deltas[out.count++] = delta;
        if (delta <= theta)
            break;
    }
    out.actions = action_values(model, out.values, gamma);
    out.policy = greedy(out.actions, n);
    return out;
}
Evaluation in_place(const Model *model, Integer gamma, Integer theta) {
    int n = model->world->n;
    Integer *values = allocate(n, sizeof *values);
    int sweeps = 0;
    for (;;) {
        ++sweeps;
        Integer delta = 0;
        for (int s = 0; s < n; ++s) {
            Integer actions[4];
            for (int a = 0; a < 4; ++a)
                actions[a] = bellman(model, values, s, a, gamma);
            Integer value = actions[first_maximum(actions)], difference = absolute(value - values[s]);
            if (difference > delta)
                delta = difference;
            values[s] = value;
        }
        if (delta <= theta)
            return (Evaluation){values, sweeps};
    }
}
Evaluation evaluate(const Model *model, const int *policy, Integer *values, Integer gamma, Integer theta) {
    int sweeps = 0;
    for (;;) {
        ++sweeps;
        Integer delta = 0;
        for (int s = 0; s < model->world->n; ++s) {
            Integer value = bellman(model, values, s, policy[s], gamma),
                    difference = absolute(value - values[s]);
            if (difference > delta)
                delta = difference;
            values[s] = value;
        }
        if (delta <= theta)
            return (Evaluation){values, sweeps};
    }
}
PolicyIteration policy_iteration(const Model *model, Integer gamma, Integer theta) {
    int n = model->world->n;
    PolicyIteration out = {0};
    out.values = allocate(n, sizeof *out.values);
    out.policy = allocate(n, sizeof *out.policy);
    for (;;) {
        Evaluation evaluated = evaluate(model, out.policy, out.values, gamma, theta);
        Table q = action_values(model, out.values, gamma);
        int *policy = greedy(q, n), changed = 0;
        free(q);
        for (int s = 0; s < n; ++s)
            if (policy[s] != out.policy[s])
                ++changed;
        grow((void **)&out.rounds, &out.cap, out.count + 1, sizeof *out.rounds);
        out.rounds[out.count++] =
            (Round){evaluated.sweeps, changed, out.values[model->world->index[model->world->start]]};
        free(out.policy);
        out.policy = policy;
        if (!changed)
            return out;
    }
}
