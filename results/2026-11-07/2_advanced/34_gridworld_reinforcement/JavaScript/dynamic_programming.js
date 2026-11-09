'use strict';

function floorDivide(numerator, denominator) {
    const dividend = BigInt(numerator);
    const divisor = BigInt(denominator);
    let quotient = dividend / divisor;
    if (dividend < 0n && dividend % divisor !== 0n) quotient--;
    return Number(quotient);
}

function firstMaximum(values) {
    let best = 0;
    for (let action = 1; action < values.length; action++) if (values[action] > values[best]) best = action;
    return best;
}

function bellman(model, values, state, action, gamma) {
    let total = 0;
    for (const transition of model.transitions[state][action]) {
        const future = transition.next < 0 ? 0 : floorDivide(gamma * values[transition.next], 100);
        total += transition.weight * (10000 * transition.reward + future);
    }
    return floorDivide(total, model.denominator);
}

function rowValues(model, values, state, gamma) {
    return [0, 1, 2, 3].map(action => bellman(model, values, state, action, gamma));
}

function actionValues(model, values, gamma) {
    return values.map((_, state) => rowValues(model, values, state, gamma));
}

function greedyPolicy(table) {
    return table.map(firstMaximum);
}

function valueIteration(model, gamma, theta) {
    let values = Array(model.world.states.length).fill(0);
    const changes = [];
    while (true) {
        const next = actionValues(model, values, gamma).map(row => row[firstMaximum(row)]);
        let delta = 0;
        for (let state = 0; state < values.length; state++) delta = Math.max(delta, Math.abs(next[state] - values[state]));
        values = next;
        changes.push(delta);
        if (delta <= theta) return { values, changes, iterations: changes.length };
    }
}

function inPlaceValueIteration(model, gamma, theta) {
    const values = Array(model.world.states.length).fill(0);
    let iterations = 0;
    while (true) {
        let delta = 0;
        for (let state = 0; state < values.length; state++) {
            const row = rowValues(model, values, state, gamma);
            const next = row[firstMaximum(row)];
            delta = Math.max(delta, Math.abs(next - values[state]));
            values[state] = next;
        }
        iterations++;
        if (delta <= theta) return { values, iterations };
    }
}

function evaluatePolicy(model, policy, gamma, theta, initial = null) {
    const values = initial === null ? Array(policy.length).fill(0) : initial.slice();
    let sweeps = 0;
    while (true) {
        let delta = 0;
        for (let state = 0; state < values.length; state++) {
            const next = bellman(model, values, state, policy[state], gamma);
            delta = Math.max(delta, Math.abs(next - values[state]));
            values[state] = next;
        }
        sweeps++;
        if (delta <= theta) return { values, sweeps };
    }
}

function policyIteration(model, gamma, theta) {
    let policy = Array(model.world.states.length).fill(0);
    let values = Array(policy.length).fill(0);
    const rounds = [];
    while (true) {
        const evaluation = evaluatePolicy(model, policy, gamma, theta, values);
        values = evaluation.values;
        const next = greedyPolicy(actionValues(model, values, gamma));
        let changed = 0;
        for (let state = 0; state < policy.length; state++) if (next[state] !== policy[state]) changed++;
        rounds.push({ number: rounds.length + 1, sweeps: evaluation.sweeps, changed, start: values[model.world.startIndex] });
        policy = next;
        if (changed === 0) return { values, policy, rounds };
    }
}

module.exports = { floorDivide, firstMaximum, bellman, rowValues, actionValues, greedyPolicy, valueIteration, inPlaceValueIteration, evaluatePolicy, policyIteration };
