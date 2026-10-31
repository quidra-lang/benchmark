'use strict';

const { matrix, cholesky, logDeterminant, quadratic } = require('./linalg');

function statistics(rows, features, classCount, prior) {
  const dimension = features.length;
  const groups = Array.from({ length: classCount }, () => []);
  for (const row of rows) groups[row.class].push(features.map(feature => row.values[feature]));
  const classes = groups.map(group => {
    const mean = Array(dimension).fill(0);
    for (let feature = 0; feature < dimension; feature++) {
      let total = 0;
      for (const vector of group) total += vector[feature];
      mean[feature] = total / group.length;
    }
    const scatter = matrix(dimension);
    for (let first = 0; first < dimension; first++) {
      for (let second = 0; second < dimension; second++) {
        let total = 0;
        for (const vector of group) total += (vector[first] - mean[first]) * (vector[second] - mean[second]);
        scatter[first][second] = total;
      }
    }
    return { count: group.length, mean, scatter, prior: prior === 'empirical' ? group.length / rows.length : 1 / classCount };
  });
  const center = [];
  const variance = [];
  for (let index = 0; index < dimension; index++) {
    const feature = features[index];
    let total = 0;
    for (const row of rows) total += row.values[feature];
    center.push(total / rows.length);
    total = 0;
    for (const row of rows) total += (row.values[feature] - center[index]) * (row.values[feature] - center[index]);
    variance.push(total / rows.length);
  }
  return { classes, center, variance, count: rows.length };
}

function train(rows, features, type, settings, classCount) {
  const data = statistics(rows, features, classCount, settings.prior);
  const dimension = features.length;
  const maximumVariance = Math.max(...data.variance);
  const added = settings.epsilon * maximumVariance;
  let pooled = null;
  if (type === 'LDA') {
    pooled = matrix(dimension);
    for (let first = 0; first < dimension; first++) {
      for (let second = 0; second < dimension; second++) {
        let total = 0;
        for (const group of data.classes) total += group.scatter[first][second];
        pooled[first][second] = total / (rows.length - classCount);
      }
    }
  }
  const classes = data.classes.map(group => {
    const covariance = type === 'LDA' ? pooled : matrix(dimension);
    if (type === 'NB') {
      for (let feature = 0; feature < dimension; feature++) covariance[feature][feature] = group.scatter[feature][feature] / group.count + added;
    } else if (type === 'QDA') {
      for (let first = 0; first < dimension; first++) {
        for (let second = 0; second < dimension; second++) {
          covariance[first][second] = group.scatter[first][second] / (group.count - 1);
          if (first !== second) covariance[first][second] *= 1 - settings.gamma;
        }
      }
    }
    const lower = cholesky(covariance);
    return { ...group, covariance, lower, logDeterminant: logDeterminant(lower) };
  });
  return { type, features: features.slice(), data, classes, maximumVariance, added };
}

function predict(model, vector, costs = null) {
  const halfConstant = model.features.length * Math.log(2 * Math.PI) / 2;
  const distances = [];
  const scores = [];
  for (const group of model.classes) {
    const difference = vector.map((value, index) => value - group.mean[index]);
    const distance = quadratic(group.lower, difference);
    distances.push(distance);
    scores.push(Math.log(group.prior) - halfConstant - group.logDeterminant / 2 - distance / 2);
  }
  let predicted = 0;
  for (let index = 1; index < scores.length; index++) if (scores[index] > scores[predicted]) predicted = index;
  const maximum = scores[predicted];
  const exponentials = scores.map(score => Math.exp(score - maximum));
  let total = 0;
  for (const value of exponentials) total += value;
  const posterior = exponentials.map(value => value / total);
  const logPosterior = scores.map(score => (score - maximum) - Math.log(total));
  const confidence = Math.max(...posterior);
  let decision = predicted;
  if (costs !== null) {
    let least = Infinity;
    for (let decided = 0; decided < scores.length; decided++) {
      let risk = 0;
      for (let actual = 0; actual < scores.length; actual++) risk += posterior[actual] * costs[actual][decided];
      if (risk < least) {
        least = risk;
        decision = decided;
      }
    }
  }
  return { predicted, posterior, logPosterior, confidence, decision, distances };
}

function predictRow(model, row, costs = null) {
  return predict(model, model.features.map(feature => row.values[feature]), costs);
}

module.exports = { statistics, train, predict, predictRow };
