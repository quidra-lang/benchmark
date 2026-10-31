'use strict';

const PI = 3.141592653589793;

function angle(speed, time) {
  const degrees = speed * time;
  const reduced = degrees - 360 * Math.floor(degrees / 360);
  return reduced * PI / 180;
}

function regressors(constituents, time) {
  const values = [1];
  for (const constituent of constituents) {
    const theta = angle(constituent.speed, time);
    values.push(Math.cos(theta), Math.sin(theta));
  }
  return values;
}

function normalEquations(rows, constituents) {
  const size = 2 * constituents.length + 1;
  const matrix = Array.from({length: size}, () => Array(size).fill(0));
  const rhs = Array(size).fill(0);
  for (const row of rows) {
    const x = regressors(constituents, row.time);
    for (let i = 0; i < size; i++) {
      for (let j = 0; j < size; j++) matrix[i][j] += x[i] * x[j];
      rhs[i] += x[i] * row.value;
    }
  }
  return {matrix, rhs};
}

function solve(matrix, rhs) {
  const size = rhs.length;
  const augmented = matrix.map((row, i) => row.concat(rhs[i],
    Array.from({length: size}, (_, j) => i === j ? 1 : 0)));
  for (let column = 0; column < size; column++) {
    let pivot = column;
    for (let row = column + 1; row < size; row++) {
      if (Math.abs(augmented[row][column]) > Math.abs(augmented[pivot][column])) pivot = row;
    }
    if (pivot !== column) [augmented[pivot], augmented[column]] = [augmented[column], augmented[pivot]];
    for (let row = column + 1; row < size; row++) {
      const factor = augmented[row][column] / augmented[column][column];
      for (let c = column; c <= 2 * size; c++) {
        augmented[row][c] = augmented[row][c] - factor * augmented[column][c];
      }
    }
  }
  let coefficients;
  const inverse = Array.from({length: size}, () => Array(size));
  for (let column = size; column <= 2 * size; column++) {
    const solution = Array(size);
    for (let row = size - 1; row >= 0; row--) {
      let value = augmented[row][column];
      for (let j = row + 1; j < size; j++) value = value - augmented[row][j] * solution[j];
      solution[row] = value / augmented[row][row];
    }
    if (column === size) coefficients = solution;
    else for (let row = 0; row < size; row++) inverse[row][column - size - 1] = solution[row];
  }
  return {coefficients, inverse};
}

function fit(rows, constituents) {
  const {matrix, rhs} = normalEquations(rows, constituents);
  const {coefficients, inverse} = solve(matrix, rhs);
  const fitted = constituents.map((constituent, index) => {
    const a = coefficients[2 * index + 1];
    const b = coefficients[2 * index + 2];
    const amplitude = Math.sqrt(a * a + b * b);
    let phase = Math.atan2(b, a) * 180 / PI;
    if (phase < 0) phase += 360;
    return {...constituent, a, b, amplitude, phase};
  });
  return {mean: coefficients[0], unknowns: coefficients.length, coefficients, inverse,
    constituents: fitted};
}

module.exports = {PI, angle, regressors, normalEquations, solve, fit};
