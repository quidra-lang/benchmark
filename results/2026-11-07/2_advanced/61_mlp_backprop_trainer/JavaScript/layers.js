'use strict';

function activate(kind, value) {
    if (kind === 'TANH') return Math.tanh(value);
    if (kind === 'SIGMOID') return 1 / (1 + Math.exp(-value));
    return value > 0 ? value : 0;
}

function derivative(kind, value, activation) {
    if (kind === 'TANH') return 1 - activation * activation;
    if (kind === 'SIGMOID') return activation * (1 - activation);
    return value > 0 ? 1 : 0;
}

function preactivate(theta, layer, inputs) {
    const values = [];
    for (let j = 0; j < layer.units; j++) {
        let weighted = 0;
        const offset = layer.offset + j * layer.inputs;
        for (let i = 0; i < layer.inputs; i++) weighted += theta[offset + i] * inputs[i];
        values.push(weighted + theta[layer.biasOffset + j]);
    }
    return values;
}

function propagate(theta, layer, errors) {
    const values = [];
    for (let i = 0; i < layer.inputs; i++) {
        let value = 0;
        for (let j = 0; j < layer.units; j++) value += theta[layer.offset + j * layer.inputs + i] * errors[j];
        values.push(value);
    }
    return values;
}

function output(kind, values, label) {
    const size = values.length;
    const errors = [];
    let scores;
    let loss;
    if (kind === 'SOFTMAX') {
        let maximum = values[0];
        for (let k = 1; k < size; k++) maximum = Math.max(maximum, values[k]);
        const exponentials = values.map(value => Math.exp(value - maximum));
        let total = 0;
        for (const value of exponentials) total += value;
        scores = exponentials.map(value => value / total);
        loss = Math.log(total) - (values[label] - maximum);
        for (let k = 0; k < size; k++) errors.push(scores[k] - (k === label ? 1 : 0));
    } else {
        scores = values.map(value => activate('SIGMOID', value));
        loss = 0;
        for (let k = 0; k < size; k++) {
            const difference = scores[k] - (k === label ? 1 : 0);
            loss += difference * difference;
            errors.push(2 * difference * scores[k] * (1 - scores[k]) / size);
        }
        loss /= size;
    }
    return {scores, loss, errors};
}

module.exports = {activate, derivative, preactivate, propagate, output};
