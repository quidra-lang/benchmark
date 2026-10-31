'use strict';

function cholesky(matrix) {
  const size = matrix.length;
  const lower = Array.from({length: size}, () => Array(size).fill(0));
  for (let i = 0; i < size; i++) {
    for (let j = 0; j <= i; j++) {
      let value = matrix[i][j];
      for (let h = 0; h < j; h++) value -= lower[i][h] * lower[j][h];
      if (j < i) lower[i][j] = value / lower[j][j];
      else {
        if (value <= 0.000000001 * matrix[i][i]) return {lower, unstable: i};
        lower[i][i] = Math.sqrt(value);
      }
    }
  }
  return {lower, unstable: null};
}

function solve(lower, right) {
  const size = right.length;
  const intermediate = Array(size);
  for (let i = 0; i < size; i++) {
    let value = right[i];
    for (let h = 0; h < i; h++) value -= lower[i][h] * intermediate[h];
    intermediate[i] = value / lower[i][i];
  }
  const solution = Array(size);
  for (let i = size - 1; i >= 0; i--) {
    let value = intermediate[i];
    for (let h = i + 1; h < size; h++) value -= lower[h][i] * solution[h];
    solution[i] = value / lower[i][i];
  }
  return solution;
}

module.exports = {cholesky, solve};
