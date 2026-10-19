'use strict';

const { gradient, hessian } = require('./logistic');

class Minstd {
    constructor(seed) {
        this.state = seed;
    }

    draw() {
        this.state = (48271 * this.state) % 2147483647;
        return this.state;
    }
}

function shuffle(values, generator) {
    for (let index = values.length - 1; index >= 1; index--) {
        const other = generator.draw() % (index + 1);
        [values[index], values[other]] = [values[other], values[index]];
    }
}

function cholesky(matrix) {
    const factor = matrix.map(() => Array(matrix.length).fill(0));
    for (let column = 0; column < matrix.length; column++) {
        for (let row = column; row < matrix.length; row++) {
            let total = 0;
            for (let inner = 0; inner < column; inner++) total += factor[row][inner] * factor[column][inner];
            const remainder = matrix[row][column] - total;
            factor[row][column] = row === column ? Math.sqrt(remainder) : remainder / factor[column][column];
        }
    }
    return factor;
}

function solveFactor(factor, right) {
    const forward = Array(right.length);
    for (let row = 0; row < right.length; row++) {
        let total = 0;
        for (let column = 0; column < row; column++) total += factor[row][column] * forward[column];
        forward[row] = (right[row] - total) / factor[row][row];
    }
    const solution = Array(right.length);
    for (let row = right.length - 1; row >= 0; row--) {
        let total = 0;
        for (let column = row + 1; column < right.length; column++) total += factor[column][row] * solution[column];
        solution[row] = (forward[row] - total) / factor[row][row];
    }
    return solution;
}

function gradientDescent(vectors, targets, lambda, rate, iterations) {
    let weights = Array(vectors[0].length).fill(0);
    const checkpoints = [{ iteration: 0, weights: weights.slice() }];
    for (let iteration = 1; iteration <= iterations; iteration++) {
        const direction = gradient(weights, vectors, targets, lambda);
        weights = weights.map((weight, component) => weight - rate * direction[component]);
        if (iteration % 100 === 0) checkpoints.push({ iteration, weights: weights.slice() });
    }
    return { weights, checkpoints };
}

function stochasticDescent(vectors, targets, lambda, rate, batchSize, epochs, seed) {
    let weights = Array(vectors[0].length).fill(0);
    const checkpoints = [{ iteration: 0, weights: weights.slice() }];
    const generator = new Minstd(seed);
    const order = vectors.map((_, index) => index);
    for (let epoch = 1; epoch <= epochs; epoch++) {
        shuffle(order, generator);
        for (let start = 0; start < order.length; start += batchSize) {
            const batch = order.slice(start, start + batchSize);
            const direction = gradient(weights, batch.map(index => vectors[index]), batch.map(index => targets[index]), lambda);
            weights = weights.map((weight, component) => weight - rate * direction[component]);
        }
        checkpoints.push({ iteration: epoch, weights: weights.slice() });
    }
    return { weights, checkpoints };
}

function newton(vectors, targets, lambda) {
    let weights = Array(vectors[0].length).fill(0);
    const checkpoints = [{ iteration: 0, weights: weights.slice() }];
    const steps = [];
    for (let iteration = 1; iteration <= 10; iteration++) {
        const direction = gradient(weights, vectors, targets, lambda);
        const delta = solveFactor(cholesky(hessian(weights, vectors, lambda)), direction);
        steps.push({ gradient: direction, delta });
        weights = weights.map((weight, component) => weight - delta[component]);
        checkpoints.push({ iteration, weights: weights.slice() });
    }
    return { weights, checkpoints, steps };
}

module.exports = { Minstd, shuffle, cholesky, solveFactor, gradientDescent, stochasticDescent, newton };
