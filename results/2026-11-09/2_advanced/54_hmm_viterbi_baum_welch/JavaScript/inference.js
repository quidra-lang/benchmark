'use strict';

function argmax(values) {
    let best = 0;
    for (let i = 1; i < values.length; i++) {
        if (values[i] > values[best]) best = i;
    }
    return best;
}

function emission(model, observation, state) {
    return observation < 0 ? 1 : model.emission[state][observation];
}

function logEmission(model, observation, state) {
    return observation < 0 ? 0 : Math.log(model.emission[state][observation]);
}

function forward(model, observations) {
    const count = model.states.length;
    const factors = [];
    const scales = [];
    let loglik = 0;
    for (let t = 0; t < observations.length; t++) {
        const row = [];
        for (let j = 0; j < count; j++) {
            let probability = model.initial[j];
            if (t > 0) {
                probability = 0;
                for (let i = 0; i < count; i++) {
                    probability += factors[t - 1][i] * model.transition[i][j];
                }
            }
            row.push(probability * emission(model, observations[t], j));
        }
        let scale = 0;
        for (const value of row) scale += value;
        scales.push(scale);
        factors.push(row.map(value => value / scale));
        loglik += Math.log(scale);
    }
    return { factors, scales, loglik };
}

function forwardBackward(model, observations) {
    const result = forward(model, observations);
    const count = model.states.length;
    const length = observations.length;
    const backward = Array(length);
    backward[length - 1] = Array(count).fill(1);
    for (let t = length - 2; t >= 0; t--) {
        backward[t] = [];
        for (let i = 0; i < count; i++) {
            let value = 0;
            for (let j = 0; j < count; j++) {
                value += model.transition[i][j] * emission(model, observations[t + 1], j)
                    * backward[t + 1][j];
            }
            backward[t].push(value / result.scales[t + 1]);
        }
    }
    const gamma = result.factors.map((row, t) =>
        row.map((value, i) => value * backward[t][i]));
    return { ...result, backward, gamma };
}

function viterbi(model, observations) {
    const count = model.states.length;
    const transitions = model.transition.map(row => row.map(Math.log));
    let delta = model.initial.map((value, j) =>
        Math.log(value) + logEmission(model, observations[0], j));
    const predecessors = [Array(count).fill(0)];
    for (let t = 1; t < observations.length; t++) {
        const next = [];
        const row = [];
        for (let j = 0; j < count; j++) {
            const candidates = delta.map((value, i) => value + transitions[i][j]);
            const best = argmax(candidates);
            row.push(best);
            next.push((delta[best] + transitions[best][j])
                + logEmission(model, observations[t], j));
        }
        predecessors.push(row);
        delta = next;
    }
    const path = Array(observations.length);
    path[path.length - 1] = argmax(delta);
    const logprob = delta[path[path.length - 1]];
    for (let t = path.length - 1; t > 0; t--) path[t - 1] = predecessors[t][path[t]];
    return { path, logprob };
}

function decode(model, observations) {
    const result = forwardBackward(model, observations);
    const best = viterbi(model, observations);
    const posterior = result.gamma.map(argmax);
    const confidence = result.gamma.map((row, t) => row[posterior[t]]);
    return { ...result, viterbi: best.path, logprob: best.logprob, posterior, confidence };
}

module.exports = { argmax, emission, forward, forwardBackward, viterbi, decode };
