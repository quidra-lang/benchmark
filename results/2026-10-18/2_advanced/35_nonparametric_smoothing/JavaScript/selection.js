'use strict';

function crossValidation(actual, predictions) {
    if (predictions.some(value => value === null)) return null;
    let total = 0;
    for (let i = 0; i < actual.length; i++) { const error = actual[i] - predictions[i]; total += error * error; }
    return total / actual.length;
}

function generalized(actual, fitted, edf) {
    let rss = 0;
    for (let i = 0; i < actual.length; i++) { const error = actual[i] - fitted[i]; rss += error * error; }
    const tau = 1 - edf / actual.length;
    return rss / actual.length / (tau * tau);
}

function choose(candidates) {
    let best = -1;
    for (let i = 0; i < candidates.length; i++) {
        if (candidates[i].score !== null && (best < 0 || candidates[i].score < candidates[best].score)) best = i;
    }
    return best;
}

module.exports = { crossValidation, generalized, choose };
