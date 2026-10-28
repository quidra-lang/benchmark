#include "reinforcement.hpp"
int first_maximum(const std::array<Integer, 4> &values) {
    int action = 0;
    for (int a = 1; a < 4; ++a)
        if (values[a] > values[action])
            action = a;
    return action;
}
Integer bellman(const Model &model, const Values &values, int state, int action, Integer gamma) {
    Integer sum = 0;
    for (const Transition &t : model.transitions(state, action)) {
        const int next = model.world->index[t.cell];
        sum += t.weight * (10000 * reward(*model.world, t.cell, model.step_reward) +
                           (next < 0 ? 0 : floor_div(gamma * values[next], 100)));
    }
    return floor_div(sum, model.q);
}
Table action_values(const Model &model, const Values &values, Integer gamma) {
    Table q(values.size());
    for (int state = 0; state < int(values.size()); ++state)
        for (int action = 0; action < 4; ++action)
            q[state][action] = bellman(model, values, state, action, gamma);
    return q;
}
Policy greedy(const Table &values) {
    Policy policy;
    for (const auto &row : values)
        policy.push_back(first_maximum(row));
    return policy;
}
Iteration value_iteration(const Model &model, Integer gamma, Integer theta) {
    Iteration result;
    result.values.assign(model.world->states.size(), 0);
    while (true) {
        const Table q = action_values(model, result.values, gamma);
        Values next(q.size());
        Integer delta = 0;
        for (std::size_t i = 0; i < q.size(); ++i) {
            next[i] = q[i][first_maximum(q[i])];
            delta = std::max(delta, absolute(next[i] - result.values[i]));
        }
        result.values = std::move(next);
        result.deltas.push_back(delta);
        if (delta <= theta)
            break;
    }
    result.actions = action_values(model, result.values, gamma);
    result.policy = greedy(result.actions);
    return result;
}
std::pair<Values, int> in_place(const Model &model, Integer gamma, Integer theta) {
    Values values(model.world->states.size());
    int sweeps = 0;
    while (true) {
        Integer delta = 0;
        ++sweeps;
        for (int state = 0; state < int(values.size()); ++state) {
            std::array<Integer, 4> actions{};
            for (int a = 0; a < 4; ++a)
                actions[a] = bellman(model, values, state, a, gamma);
            const Integer value = actions[first_maximum(actions)];
            delta = std::max(delta, absolute(value - values[state]));
            values[state] = value;
        }
        if (delta <= theta)
            return {values, sweeps};
    }
}
std::pair<Values, int> evaluate(const Model &model, const Policy &policy, Values values, Integer gamma,
                                Integer theta) {
    int sweeps = 0;
    while (true) {
        Integer delta = 0;
        ++sweeps;
        for (int state = 0; state < int(values.size()); ++state) {
            const Integer value = bellman(model, values, state, policy[state], gamma);
            delta = std::max(delta, absolute(value - values[state]));
            values[state] = value;
        }
        if (delta <= theta)
            return {values, sweeps};
    }
}
PolicyIteration policy_iteration(const Model &model, Integer gamma, Integer theta) {
    PolicyIteration result;
    result.values.assign(model.world->states.size(), 0);
    result.policy.assign(result.values.size(), 0);
    while (true) {
        auto evaluated = evaluate(model, result.policy, result.values, gamma, theta);
        result.values = std::move(evaluated.first);
        Policy policy = greedy(action_values(model, result.values, gamma));
        int changed = 0;
        for (std::size_t i = 0; i < policy.size(); ++i)
            if (policy[i] != result.policy[i])
                ++changed;
        result.rounds.push_back(
            {evaluated.second, changed, result.values[model.world->index[model.world->start]]});
        result.policy = std::move(policy);
        if (changed == 0)
            return result;
    }
}
