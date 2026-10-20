'use strict';

const matrix = require('./matrix');

function standardize(values, means, scales) {
  return values.map((value, index) => value === null ? 0 : (value - means[index]) / scales[index]);
}

function prepare(rows, scaling) {
  const dimension = rows[0].length;
  const count = rows.length;
  const means = [];
  for (let feature = 0; feature < dimension; feature++) {
    let total = 0;
    for (const row of rows) total += row[feature];
    means.push(total / count);
  }
  const covariance = matrix.zeros(dimension);
  for (let first = 0; first < dimension; first++) {
    for (let second = first; second < dimension; second++) {
      let total = 0;
      for (const row of rows) total += (row[first] - means[first]) * (row[second] - means[second]);
      covariance[first][second] = covariance[second][first] = total / (count - 1);
    }
  }
  const deviations = covariance.map((row, index) => Math.sqrt(row[index]));
  const correlation = covariance.map((row, first) => row.map((value, second) =>
    first === second ? 1 : value / (deviations[first] * deviations[second])));
  const scales = scaling === 'covariance' ? Array(dimension).fill(1) : deviations.slice();
  return { means, covariance, deviations, correlation, scales,
    matrix: scaling === 'covariance' ? covariance : correlation,
    standardized: rows.map(row => standardize(row, means, scales)) };
}

function scores(standardized, vectors) {
  return vectors.map(vector => matrix.dot(standardized, vector));
}

function residuals(standardized, scores, vectors, retained) {
  return standardized.map((value, feature) => {
    let fitted = 0;
    for (let component = 0; component < retained; component++) fitted += scores[component] * vectors[component][feature];
    return value - fitted;
  });
}

function tSquared(scores, values, retained) {
  let total = 0;
  for (let component = 0; component < retained; component++) total += (scores[component] * scores[component]) / values[component];
  return total;
}

module.exports = { prepare, standardize, scores, residuals, tSquared };
