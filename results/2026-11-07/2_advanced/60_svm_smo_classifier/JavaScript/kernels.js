'use strict';

const { fixed } = require('./evaluation');

function value(kernel, a, b) {
  if (kernel.kind === 'linear') return a[0] * b[0] + a[1] * b[1];
  if (kernel.kind === 'poly') {
    const s = kernel.gamma * (a[0] * b[0] + a[1] * b[1]) + kernel.coef0;
    let result = 1;
    for (let i = 0; i < kernel.degree; i++) result *= s;
    return result;
  }
  const e1 = a[0] - b[0], e2 = a[1] - b[1];
  return Math.exp(-kernel.gamma * (e1 * e1 + e2 * e2));
}

function matrix(kernel, points) {
  return points.map(a => points.map(b => value(kernel, a, b)));
}

function subset(matrix, indices) {
  return indices.map(i => indices.map(j => matrix[i][j]));
}

function description(kernel) {
  if (kernel.kind === 'linear') return 'linear';
  if (kernel.kind === 'poly') return `poly degree ${kernel.degree} gamma ${fixed(kernel.gamma, 4)} coef0 ${fixed(kernel.coef0, 4)}`;
  return `rbf gamma ${fixed(kernel.gamma, 4)}`;
}

module.exports = { value, matrix, subset, description };
