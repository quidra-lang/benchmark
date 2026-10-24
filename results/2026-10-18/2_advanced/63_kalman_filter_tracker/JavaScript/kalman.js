'use strict';

const matrix = require('./matrix');
const { product, transpose, vectorProduct, add, subtract, vectorAdd, vectorSubtract } = matrix;

function motion(kind, T, q) {
    const n = kind === 'CV' ? 4 : 6;
    const F = matrix.identity(n), Q = matrix.zeros(n);
    F[0][2] = T;
    F[1][3] = T;
    let entries;
    if (kind === 'CV') {
        entries = [[0, 0, q * T * T * T / 3], [0, 2, q * T * T / 2], [2, 2, q * T]];
    } else {
        F[0][4] = T * T / 2;
        F[1][5] = T * T / 2;
        F[2][4] = T;
        F[3][5] = T;
        entries = [
            [0, 0, q * T * T * T * T * T / 20],
            [0, 2, q * T * T * T * T / 8],
            [0, 4, q * T * T * T / 6],
            [2, 2, q * T * T * T / 3],
            [2, 4, q * T * T / 2], [4, 4, q * T],
        ];
    }
    for (let axis = 0; axis < 2; axis++) {
        for (const [i, j, value] of entries) {
            Q[i + axis][j + axis] = value;
            Q[j + axis][i + axis] = value;
        }
    }
    return { F, Q };
}

function measurementModel(size, sigma) {
    const H = matrix.zeros(2, size);
    H[0][0] = 1;
    H[1][1] = 1;
    return { H, R: matrix.diagonal([sigma * sigma, sigma * sigma]) };
}

function initialize(kind, measurement, params) {
    const x = [...measurement, 0, 0];
    const variances = [
        params.SIGMA * params.SIGMA, params.SIGMA * params.SIGMA,
        params.INIT_VELOCITY_VARIANCE, params.INIT_VELOCITY_VARIANCE,
    ];
    if (kind === 'CA') {
        x.push(0, 0);
        variances.push(params.INIT_ACCELERATION_VARIANCE, params.INIT_ACCELERATION_VARIANCE);
    }
    return { x, P: matrix.diagonal(variances) };
}

function predict(estimate, kind, T, q) {
    const { F, Q } = motion(kind, T, q);
    return { x: vectorProduct(F, estimate.x), P: add(product(product(F, estimate.P), transpose(F)), Q), F };
}

function innovation(prediction, measurement, sigma) {
    const { H, R } = measurementModel(prediction.x.length, sigma);
    const nu = vectorSubtract(measurement, vectorProduct(H, prediction.x));
    const S = add(product(product(H, prediction.P), transpose(H)), R);
    const Si = matrix.inverse(S);
    return { nu, S, Si, H, R, d2: matrix.quadratic2(nu, Si) };
}

function update(prediction, residual) {
    const { H, R, Si, nu, S, d2 } = residual;
    const K = product(product(prediction.P, transpose(H)), Si);
    const J = subtract(matrix.identity(prediction.x.length), product(K, H));
    const x = vectorAdd(prediction.x, vectorProduct(K, nu));
    const P = add(product(product(J, prediction.P), transpose(J)), product(product(K, R), transpose(K)));
    const logLikelihood = -Math.log(2 * Math.PI) - Math.log(matrix.determinant2(S)) / 2 - d2 / 2;
    return { x, P, logLikelihood };
}

function smooth(history) {
    const states = new Array(history.length);
    states[history.length - 1] = history[history.length - 1].estimate.x.slice();
    for (let i = history.length - 2; i >= 0; i--) {
        const current = history[i].estimate, nextPrediction = history[i + 1].prediction;
        const gain = product(product(current.P, transpose(nextPrediction.F)), matrix.inverse(nextPrediction.P));
        states[i] = vectorAdd(current.x, vectorProduct(gain, vectorSubtract(states[i + 1], nextPrediction.x)));
    }
    return states;
}

module.exports = { motion, measurementModel, initialize, predict, innovation, update, smooth };
