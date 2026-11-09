'use strict';

const kalman = require('./kalman');
const { determinant2 } = require('./matrix');

function initialize(measurement, params) {
    return {
        models: [kalman.initialize('CV', measurement, params), kalman.initialize('CV', measurement, params)],
        probabilities: params.IMM_INITIAL.slice(),
    };
}

function advance(previous, T, measurement, params) {
    const transition = [params.IMM_TRANSITION.slice(0, 2), params.IMM_TRANSITION.slice(2)];
    const [first, second] = previous.models, [mu1, mu2] = previous.probabilities;
    const predicted = [], models = [], likelihoods = [];
    for (let j = 0; j < 2; j++) {
        const c = transition[0][j] * mu1 + transition[1][j] * mu2;
        predicted.push(c);
        const w1 = transition[0][j] * mu1 / c, w2 = transition[1][j] * mu2 / c;
        const x = first.x.map((value, r) => w1 * value + w2 * second.x[r]);
        const P = first.P.map((row, r) => row.map((value, s) =>
            w1 * (value + (first.x[r] - x[r]) * (first.x[s] - x[s]))
                + w2 * (second.P[r][s] + (second.x[r] - x[r]) * (second.x[s] - x[s]))));
        const prediction = kalman.predict({ x, P }, 'CV', T, params.IMM_Q[j]);
        if (measurement === null) {
            models.push(prediction);
            likelihoods.push(1);
        } else {
            const residual = kalman.innovation(prediction, measurement, params.SIGMA);
            models.push(kalman.update(prediction, residual));
            likelihoods.push(Math.exp(-residual.d2 / 2) / (2 * Math.PI * Math.sqrt(determinant2(residual.S))));
        }
    }
    const denominator = likelihoods[0] * predicted[0] + likelihoods[1] * predicted[1];
    const probabilities = likelihoods.map((likelihood, j) => likelihood * predicted[j] / denominator);
    return { models, probabilities };
}

function estimate(state) {
    return state.models[0].x.map((value, r) =>
        state.probabilities[0] * value + state.probabilities[1] * state.models[1].x[r]);
}

module.exports = { initialize, advance, estimate };
