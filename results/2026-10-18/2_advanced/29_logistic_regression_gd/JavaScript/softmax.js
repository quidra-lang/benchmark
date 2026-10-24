'use strict';

const { score } = require('./logistic');

function rowValues(weights, vector, label = 0) {
    const scores = weights.map(row => score(row, vector));
    const maximum = Math.max(...scores);
    const shifted = scores.map(value => value - maximum);
    const exponentials = shifted.map(value => Math.exp(value));
    let total = 0;
    for (const value of exponentials) total += value;
    const probabilities = exponentials.map(value => value / total);
    let predicted = 0;
    for (let labelIndex = 1; labelIndex < probabilities.length; labelIndex++) {
        if (probabilities[labelIndex] > probabilities[predicted]) predicted = labelIndex;
    }
    return { probabilities, predicted, loss: Math.log(total) - shifted[label] };
}

function evaluate(weights, vectors, labels, lambda = 0) {
    const rows = vectors.map((vector, index) => rowValues(weights, vector, labels[index]));
    let total = 0;
    for (const row of rows) total += row.loss;
    let squared = 0;
    for (const classWeights of weights) {
        for (let component = 1; component < classWeights.length; component++) squared += classWeights[component] * classWeights[component];
    }
    const average = total / vectors.length;
    return { rows, loss: average, objective: average + lambda * squared / 2 };
}

function gradient(weights, vectors, labels, lambda) {
    const probabilities = vectors.map(vector => rowValues(weights, vector).probabilities);
    return weights.map((classWeights, label) => classWeights.map((weight, component) => {
        let total = 0;
        for (let row = 0; row < vectors.length; row++) {
            const error = probabilities[row][label] - Number(labels[row] === label);
            total += error * vectors[row][component];
        }
        const value = total / vectors.length;
        return component === 0 ? value : value + lambda * weight;
    }));
}

function train(vectors, labels, classes, lambda, rate, iterations) {
    let weights = Array.from({ length: classes }, () => Array(vectors[0].length).fill(0));
    const checkpoints = [{ iteration: 0, weights: weights.map(row => row.slice()) }];
    for (let iteration = 1; iteration <= iterations; iteration++) {
        const direction = gradient(weights, vectors, labels, lambda);
        weights = weights.map((row, label) => row.map((weight, component) => weight - rate * direction[label][component]));
        if (iteration % 100 === 0) checkpoints.push({ iteration, weights: weights.map(row => row.slice()) });
    }
    return { weights, checkpoints };
}

module.exports = { rowValues, evaluate, gradient, train };
