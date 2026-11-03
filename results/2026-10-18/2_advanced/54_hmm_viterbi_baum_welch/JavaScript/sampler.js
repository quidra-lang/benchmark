'use strict';

class Minstd {
    constructor(seed) {
        this.state = seed;
    }

    uniform() {
        this.state = (48271 * this.state) % 2147483647;
        return this.state / 2147483647;
    }

    draw(weights) {
        let total = 0;
        for (const weight of weights) total += weight;
        const threshold = this.uniform() * total;
        let cumulative = 0;
        for (let i = 0; i < weights.length; i++) {
            cumulative += weights[i];
            if (threshold < cumulative) return i;
        }
        return weights.length - 1;
    }
}

function synthetic(model, length, generator) {
    const path = [];
    const observations = [];
    for (let t = 0; t < length; t++) {
        const weights = t === 0 ? model.initial : model.transition[path[t - 1]];
        const state = generator.draw(weights);
        path.push(state);
        observations.push(generator.draw(model.emission[state]));
    }
    return { path, observations };
}

function posteriorPath(model, factors, generator) {
    const path = Array(factors.length);
    path[path.length - 1] = generator.draw(factors[factors.length - 1]);
    for (let t = path.length - 2; t >= 0; t--) {
        const next = path[t + 1];
        const weights = factors[t].map((value, i) => value * model.transition[i][next]);
        path[t] = generator.draw(weights);
    }
    return path;
}

module.exports = { Minstd, synthetic, posteriorPath };
