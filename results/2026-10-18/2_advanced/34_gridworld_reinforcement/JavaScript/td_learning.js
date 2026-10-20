'use strict';

const { floorDivide, firstMaximum } = require('./dynamic_programming');

function choose(table, state, epsilon, generator) {
    if (generator.draw() % 1000 < epsilon) return generator.draw() % 4;
    return firstMaximum(table[state]);
}

function nextValue(table, state, epsilon = null) {
    if (state < 0) return 0;
    const values = table[state];
    const maximum = values[firstMaximum(values)];
    if (epsilon === null) return maximum;
    let total = 0;
    for (const value of values) total += value;
    return floorDivide(epsilon * total + 4 * (1000 - epsilon) * maximum, 4000);
}

function target(reward, next, future, gamma) {
    return 10000 * reward + (next < 0 ? 0 : floorDivide(gamma * future, 100));
}

function update(table, state, action, reward, next, future, gamma, alpha) {
    const old = table[state][action];
    table[state][action] = old + floorDivide(alpha * (target(reward, next, future, gamma) - old), 100);
}

class DynaModel {
    constructor() {
        this.entries = new Map();
        this.pairs = [];
    }

    record(state, action, reward, next) {
        const key = state * 4 + action;
        if (!this.entries.has(key)) this.pairs.push(key);
        this.entries.set(key, { state, action, reward, next });
    }

    plan(table, count, gamma, alpha, generator) {
        for (let step = 0; step < count; step++) {
            const key = this.pairs[generator.draw() % this.pairs.length];
            const entry = this.entries.get(key);
            const future = nextValue(table, entry.next);
            update(table, entry.state, entry.action, entry.reward, entry.next, future, gamma, alpha);
        }
    }
}

module.exports = { choose, nextValue, target, update, DynaModel };
