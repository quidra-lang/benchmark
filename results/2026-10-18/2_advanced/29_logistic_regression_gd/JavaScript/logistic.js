'use strict';

function score(weights, vector) {
    let total = 0;
    for (let component = 0; component < weights.length; component++) total += weights[component] * vector[component];
    return total;
}

function sigmoid(value) {
    if (value >= 0) return 1 / (1 + Math.exp(-value));
    const exponential = Math.exp(value);
    return exponential / (1 + exponential);
}

function loss(value, target) {
    return Math.max(value, 0) - target * value + Math.log(1 + Math.exp(-Math.abs(value)));
}

function evaluate(weights, vectors, targets, lambda = 0) {
    const scores = [];
    const probabilities = [];
    let total = 0;
    for (let row = 0; row < vectors.length; row++) {
        const value = score(weights, vectors[row]);
        scores.push(value);
        probabilities.push(sigmoid(value));
        total += loss(value, targets[row]);
    }
    let squared = 0;
    for (let component = 1; component < weights.length; component++) squared += weights[component] * weights[component];
    const average = total / vectors.length;
    return { scores, probabilities, loss: average, objective: average + lambda * squared / 2 };
}

function gradient(weights, vectors, targets, lambda) {
    const errors = vectors.map((vector, row) => sigmoid(score(weights, vector)) - targets[row]);
    return weights.map((weight, component) => {
        let total = 0;
        for (let row = 0; row < vectors.length; row++) total += errors[row] * vectors[row][component];
        const value = total / vectors.length;
        return component === 0 ? value : value + lambda * weight;
    });
}

function hessian(weights, vectors, lambda) {
    const variances = vectors.map(vector => {
        const probability = sigmoid(score(weights, vector));
        return probability * (1 - probability);
    });
    const matrix = weights.map(() => Array(weights.length).fill(0));
    for (let first = 0; first < weights.length; first++) {
        for (let second = 0; second <= first; second++) {
            let total = 0;
            for (let row = 0; row < vectors.length; row++) total += variances[row] * vectors[row][first] * vectors[row][second];
            let value = total / vectors.length;
            if (first === second && first >= 1) value += lambda;
            matrix[first][second] = value;
            matrix[second][first] = value;
        }
    }
    return matrix;
}

module.exports = { score, sigmoid, loss, evaluate, gradient, hessian };
