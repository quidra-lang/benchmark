'use strict';

function zeros(rows, columns = rows) {
    return Array.from({ length: rows }, () => new Array(columns).fill(0));
}

function diagonal(values) {
    return values.map((value, i) => values.map((unused, j) => i === j ? value : 0));
}

function identity(size) {
    return diagonal(new Array(size).fill(1));
}

function transpose(matrix) {
    return matrix[0].map((unused, j) => matrix.map(row => row[j]));
}

function product(first, second) {
    return first.map(row => second[0].map((unused, j) => {
        let value = row[0] * second[0][j];
        for (let k = 1; k < row.length; k++) value += row[k] * second[k][j];
        return value;
    }));
}

function vectorProduct(matrix, vector) {
    return matrix.map(row => {
        let value = row[0] * vector[0];
        for (let k = 1; k < vector.length; k++) value += row[k] * vector[k];
        return value;
    });
}

function add(first, second) {
    return first.map((row, i) => row.map((value, j) => value + second[i][j]));
}

function subtract(first, second) {
    return first.map((row, i) => row.map((value, j) => value - second[i][j]));
}

function vectorAdd(first, second) {
    return first.map((value, i) => value + second[i]);
}

function vectorSubtract(first, second) {
    return first.map((value, i) => value - second[i]);
}

function inverse(matrix) {
    const n = matrix.length, unit = identity(n);
    const rows = matrix.map((row, i) => [...row, ...unit[i]]);
    for (let c = 0; c < n; c++) {
        const pivot = rows[c][c];
        for (let j = 0; j < 2 * n; j++) rows[c][j] /= pivot;
        for (let i = 0; i < n; i++) {
            if (i === c) continue;
            const factor = rows[i][c];
            for (let j = 0; j < 2 * n; j++) rows[i][j] -= factor * rows[c][j];
        }
    }
    return rows.map(row => row.slice(n));
}

function determinant2(matrix) {
    return matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0];
}

function quadratic2(vector, matrix) {
    return vector[0] * (matrix[0][0] * vector[0] + matrix[0][1] * vector[1])
        + vector[1] * (matrix[1][0] * vector[0] + matrix[1][1] * vector[1]);
}

module.exports = {
    zeros, diagonal, identity, transpose, product, vectorProduct,
    add, subtract, vectorAdd, vectorSubtract, inverse, determinant2, quadratic2,
};
