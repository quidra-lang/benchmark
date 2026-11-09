'use strict';

function matrix(size) {
  return Array.from({ length: size }, () => Array(size).fill(0));
}

function cholesky(input) {
  const lower = matrix(input.length);
  for (let row = 0; row < input.length; row++) {
    for (let column = 0; column <= row; column++) {
      let total = 0;
      for (let index = 0; index < column; index++) total += lower[row][index] * lower[column][index];
      const value = input[row][column] - total;
      lower[row][column] = row === column ? Math.sqrt(value) : value / lower[column][column];
    }
  }
  return lower;
}

function forward(lower, right) {
  const result = Array(right.length).fill(0);
  for (let row = 0; row < right.length; row++) {
    let total = 0;
    for (let column = 0; column < row; column++) total += lower[row][column] * result[column];
    result[row] = (right[row] - total) / lower[row][row];
  }
  return result;
}

function backward(lower, right) {
  const result = Array(right.length).fill(0);
  for (let row = right.length - 1; row >= 0; row--) {
    let total = 0;
    for (let column = row + 1; column < right.length; column++) total += lower[column][row] * result[column];
    result[row] = (right[row] - total) / lower[row][row];
  }
  return result;
}

function logDeterminant(lower) {
  let total = 0;
  for (let index = 0; index < lower.length; index++) total += Math.log(lower[index][index]);
  return 2 * total;
}

function quadratic(lower, right) {
  const transformed = forward(lower, right);
  let total = 0;
  for (const value of transformed) total += value * value;
  return total;
}

function jacobi(input) {
  const size = input.length;
  const current = input.map(row => row.slice());
  const vectors = matrix(size);
  for (let index = 0; index < size; index++) vectors[index][index] = 1;
  let sweeps = 0;
  while (true) {
    let total = 0;
    for (let first = 0; first < size - 1; first++) {
      for (let second = first + 1; second < size; second++) total += current[first][second] * current[first][second];
    }
    if (Math.sqrt(total) < 0.000000000001 || sweeps === 50) break;
    for (let first = 0; first < size - 1; first++) {
      for (let second = first + 1; second < size; second++) {
        if (current[first][second] === 0) continue;
        const theta = (current[second][second] - current[first][first]) / (2 * current[first][second]);
        const tangent = (theta >= 0 ? 1 : -1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
        const cosine = 1 / Math.sqrt(tangent * tangent + 1);
        const sine = tangent * cosine;
        for (let index = 0; index < size; index++) {
          if (index === first || index === second) continue;
          const x = current[index][first];
          const y = current[index][second];
          current[index][first] = current[first][index] = cosine * x - sine * y;
          current[index][second] = current[second][index] = sine * x + cosine * y;
        }
        const cross = current[first][second];
        current[first][first] = current[first][first] - tangent * cross;
        current[second][second] = current[second][second] + tangent * cross;
        current[first][second] = current[second][first] = 0;
        for (let index = 0; index < size; index++) {
          const x = vectors[index][first];
          const y = vectors[index][second];
          vectors[index][first] = cosine * x - sine * y;
          vectors[index][second] = sine * x + cosine * y;
        }
      }
    }
    sweeps++;
  }
  return { values: current.map((row, index) => row[index]), vectors, sweeps };
}

module.exports = { matrix, cholesky, forward, backward, logDeterminant, quadratic, jacobi };
