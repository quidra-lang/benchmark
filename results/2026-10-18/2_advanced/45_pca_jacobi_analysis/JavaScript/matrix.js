'use strict';

function zeros(rows, columns = rows) {
  return Array.from({ length: rows }, () => Array(columns).fill(0));
}

function identity(size) {
  const result = zeros(size);
  for (let index = 0; index < size; index++) result[index][index] = 1;
  return result;
}

function copy(matrix) {
  return matrix.map(row => row.slice());
}

function column(matrix, index) {
  return matrix.map(row => row[index]);
}

function dot(first, second) {
  let total = 0;
  for (let index = 0; index < first.length; index++) total += first[index] * second[index];
  return total;
}

function multiply(matrix, vector) {
  return matrix.map(row => dot(row, vector));
}

function length(vector) {
  return Math.sqrt(dot(vector, vector));
}

function normalize(vector) {
  const norm = length(vector);
  return vector.map(value => value / norm);
}

function orient(vector) {
  let largest = 0;
  for (let index = 1; index < vector.length; index++) if (Math.abs(vector[index]) > Math.abs(vector[largest])) largest = index;
  return vector[largest] < 0 ? vector.map(value => -value) : vector.slice();
}

function difference(first, second) {
  let maximum = 0;
  for (let index = 0; index < first.length; index++) maximum = Math.max(maximum, Math.abs(first[index] - second[index]));
  return maximum;
}

function deflate(matrix, value, vector) {
  for (let row = 0; row < matrix.length; row++) {
    for (let column = 0; column < matrix.length; column++) matrix[row][column] -= value * vector[row] * vector[column];
  }
}

function inverseDeterminant(matrix) {
  const size = matrix.length;
  const unit = identity(size);
  const augmented = matrix.map((row, index) => [...row, ...unit[index]]);
  let determinant = 1;
  for (let pivot = 0; pivot < size; pivot++) {
    const value = augmented[pivot][pivot];
    determinant *= value;
    for (let column = 0; column < 2 * size; column++) augmented[pivot][column] /= value;
    for (let row = 0; row < size; row++) {
      if (row === pivot) continue;
      const coefficient = augmented[row][pivot];
      for (let column = 0; column < 2 * size; column++) augmented[row][column] -= coefficient * augmented[pivot][column];
    }
  }
  return { inverse: augmented.map(row => row.slice(size)), determinant };
}

module.exports = { zeros, identity, copy, column, dot, multiply, length, normalize, orient, difference, deflate, inverseDeterminant };
