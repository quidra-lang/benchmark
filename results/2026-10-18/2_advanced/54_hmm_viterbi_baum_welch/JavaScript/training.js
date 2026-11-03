'use strict';

const { normalize } = require('./model_io');
const { emission, forward, forwardBackward } = require('./inference');

function emptyCounts(model) {
    const count = model.states.length;
    return {
        initial: Array(count).fill(0),
        transition: Array.from({ length: count }, () => Array(count).fill(0)),
        emission: Array.from({ length: count }, () => Array(model.symbols.length).fill(0)),
    };
}

function smoothed(model, counts, alpha, name) {
    const row = values => normalize(values.map(value => value + alpha));
    return model.withProbabilities(name, row(counts.initial),
        counts.transition.map(row), counts.emission.map(row));
}

function reestimate(model, sequences, pseudocount) {
    const counts = emptyCounts(model);
    const size = model.states.length;
    for (const observations of sequences) {
        const result = forwardBackward(model, observations);
        for (let i = 0; i < size; i++) counts.initial[i] += result.gamma[0][i];
        for (let t = 0; t < observations.length; t++) {
            for (let i = 0; i < size; i++) {
                if (observations[t] >= 0) {
                    counts.emission[i][observations[t]] += result.gamma[t][i];
                }
                if (t + 1 < observations.length) {
                    for (let j = 0; j < size; j++) {
                        counts.transition[i][j] += result.factors[t][i]
                            * model.transition[i][j] * emission(model, observations[t + 1], j)
                            * result.backward[t + 1][j] / result.scales[t + 1];
                    }
                }
            }
        }
    }
    return smoothed(model, counts, pseudocount, 'BAUM_WELCH');
}

function estimateByCounting(model, pairs, alpha, name) {
    const counts = emptyCounts(model);
    for (const { observations, path } of pairs) {
        counts.initial[path[0]]++;
        for (let t = 0; t < observations.length; t++) {
            if (observations[t] >= 0) counts.emission[path[t]][observations[t]]++;
            if (t + 1 < observations.length) counts.transition[path[t]][path[t + 1]]++;
        }
    }
    return smoothed(model, counts, alpha, name);
}

function totalLoglik(model, sequences) {
    let total = 0;
    for (const observations of sequences) total += forward(model, observations).loglik;
    return total;
}

module.exports = { reestimate, estimateByCounting, totalLoglik };
