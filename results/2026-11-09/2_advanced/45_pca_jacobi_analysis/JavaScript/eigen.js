'use strict';

const matrix = require('./matrix');

function offDiagonal(values) {
  let total = 0;
  for (let first = 0; first < values.length - 1; first++) {
    for (let second = first + 1; second < values.length; second++) total += values[first][second] * values[first][second];
  }
  return total;
}

function rotate(values, vectors, first, second) {
  if (values[first][second] === 0) return;
  const theta = (values[second][second] - values[first][first]) / (2 * values[first][second]);
  let tangent = 1 / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
  if (theta < 0) tangent = -tangent;
  const cosine = 1 / Math.sqrt(tangent * tangent + 1);
  const sine = tangent * cosine;
  for (let row = 0; row < values.length; row++) {
    if (row === first || row === second) continue;
    const x = values[row][first];
    const y = values[row][second];
    values[row][first] = values[first][row] = cosine * x - sine * y;
    values[row][second] = values[second][row] = sine * x + cosine * y;
  }
  const cross = values[first][second];
  values[first][first] -= tangent * cross;
  values[second][second] += tangent * cross;
  values[first][second] = values[second][first] = 0;
  for (let row = 0; row < values.length; row++) {
    const x = vectors[row][first];
    const y = vectors[row][second];
    vectors[row][first] = cosine * x - sine * y;
    vectors[row][second] = sine * x + cosine * y;
  }
}

function jacobi(input) {
  const values = matrix.copy(input);
  const vectors = matrix.identity(input.length);
  const initial = offDiagonal(values);
  let sweeps = 0;
  if (initial !== 0) {
    for (let sweep = 1; sweep <= 100; sweep++) {
      for (let first = 0; first < input.length - 1; first++) {
        for (let second = first + 1; second < input.length; second++) rotate(values, vectors, first, second);
      }
      const off = offDiagonal(values);
      if (sweeps === 0 && off < 1e-16 * initial) sweeps = sweep;
      if (off < 1e-22 * initial) break;
    }
  }
  const order = Array.from({ length: input.length }, (_, index) => index)
    .sort((a, b) => values[b][b] - values[a][a] || a - b);
  return { values: order.map(index => values[index][index]),
    vectors: order.map(index => matrix.orient(matrix.normalize(matrix.column(vectors, index)))), sweeps };
}

function power(input, reference) {
  const remaining = matrix.copy(input);
  const results = [];
  for (let component = 0; component < input.length; component++) {
    let vector = Array(input.length).fill(1);
    let agreement = null;
    const target = reference.vectors[component];
    const negative = target.map(value => -value);
    for (let iteration = 1; iteration <= 1000; iteration++) {
      vector = matrix.normalize(matrix.multiply(remaining, vector));
      const distance = Math.min(matrix.difference(vector, target), matrix.difference(vector, negative));
      if (agreement === null && distance < 0.000001) agreement = iteration;
    }
    const product = matrix.multiply(remaining, vector);
    const value = matrix.dot(vector, product);
    const oriented = matrix.orient(matrix.normalize(vector));
    const match = Math.abs(value - reference.values[component]) <= 1e-8 * reference.values[0]
      && matrix.difference(oriented, target) <= 0.000001;
    results.push({ value, vector: oriented, agreement, match });
    matrix.deflate(remaining, value, oriented);
  }
  return results;
}

module.exports = { jacobi, power };
