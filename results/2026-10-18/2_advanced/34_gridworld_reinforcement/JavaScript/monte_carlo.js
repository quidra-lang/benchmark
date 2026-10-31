'use strict';

const { floorDivide } = require('./dynamic_programming');

function discountedReturn(rewards, gamma) {
    let value = 0;
    for (let step = rewards.length - 1; step >= 0; step--) value = 10000 * rewards[step] + floorDivide(gamma * value, 100);
    return value;
}

class FirstVisit {
    constructor(states) {
        this.totals = Array.from({ length: states }, () => Array(4).fill(0));
        this.counts = Array.from({ length: states }, () => Array(4).fill(0));
    }

    update(table, steps, gamma) {
        const first = new Map();
        steps.forEach((step, index) => {
            const key = step.state * 4 + step.action;
            if (!first.has(key)) first.set(key, index);
        });
        let value = 0;
        for (let index = steps.length - 1; index >= 0; index--) {
            const { state, action, reward } = steps[index];
            value = 10000 * reward + floorDivide(gamma * value, 100);
            if (first.get(state * 4 + action) !== index) continue;
            this.totals[state][action] += value;
            this.counts[state][action]++;
            table[state][action] = floorDivide(this.totals[state][action], this.counts[state][action]);
        }
    }
}

module.exports = { discountedReturn, FirstVisit };
