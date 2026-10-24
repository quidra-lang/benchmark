'use strict';

const { trainingRmse } = require('./evaluation');

class Random {
  constructor(seed) {
    this.state = seed;
  }

  next() {
    this.state = 48271 * this.state % 2147483647;
    return this.state;
  }

  factor() {
    return (this.next() % 2001 - 1000) / 10000;
  }
}

function dot(first, second) {
  let total = 0;
  for (let index = 0; index < first.length; index++) total += first[index] * second[index];
  return total;
}

function trainSvd(data) {
  const settings = data.settings;
  const random = new Random(settings.seed);
  const userFactors = data.users.map(() => Array.from({ length: settings.factors }, () => random.factor()));
  const itemFactors = data.items.map(() => Array.from({ length: settings.factors }, () => random.factor()));
  const userBias = data.users.map(() => 0);
  const itemBias = data.items.map(() => 0);
  const order = data.train.map((row, index) => index);
  const predict = (user, item) => ((data.mean + userBias[user]) + itemBias[item]) + dot(userFactors[user], itemFactors[item]);
  const history = [];
  for (let epoch = 1; epoch <= settings.epochs; epoch++) {
    for (let index = order.length - 1; index >= 1; index--) {
      const other = random.next() % (index + 1);
      [order[index], order[other]] = [order[other], order[index]];
    }
    for (const index of order) {
      const { u, i, rating } = data.train[index];
      const error = rating - predict(u, i);
      userBias[u] += settings.learningRate * (error - settings.regularization * userBias[u]);
      itemBias[i] += settings.learningRate * (error - settings.regularization * itemBias[i]);
      for (let factor = 0; factor < settings.factors; factor++) {
        const a = userFactors[u][factor];
        const b = itemFactors[i][factor];
        userFactors[u][factor] = a + settings.learningRate * (error * b - settings.regularization * a);
        itemFactors[i][factor] = b + settings.learningRate * (error * a - settings.regularization * b);
      }
    }
    history.push({ method: 'SVD', epoch, rmse: trainingRmse(data.train, predict) });
  }
  return { userFactors, itemFactors, userBias, itemBias, predict, history };
}

function solve(matrix, right) {
  const size = right.length;
  const lower = Array.from({ length: size }, () => Array(size).fill(0));
  for (let row = 0; row < size; row++) {
    for (let column = 0; column <= row; column++) {
      let total = 0;
      for (let index = 0; index < column; index++) total += lower[row][index] * lower[column][index];
      const value = matrix[row][column] - total;
      lower[row][column] = row === column ? Math.sqrt(value) : value / lower[column][column];
    }
  }
  const forward = Array(size).fill(0);
  for (let row = 0; row < size; row++) {
    let total = 0;
    for (let column = 0; column < row; column++) total += lower[row][column] * forward[column];
    forward[row] = (right[row] - total) / lower[row][row];
  }
  const result = Array(size).fill(0);
  for (let row = size - 1; row >= 0; row--) {
    let total = 0;
    for (let column = row + 1; column < size; column++) total += lower[column][row] * result[column];
    result[row] = (forward[row] - total) / lower[row][row];
  }
  return result;
}

function trainAls(data, baseline) {
  const settings = data.settings;
  const random = new Random(settings.seed);
  const itemFactors = data.items.map(() => Array.from({ length: settings.factors }, () => random.factor()));
  const userFactors = Array(data.users.length);
  const residual = data.train.map(row => row.rating - baseline(row.u, row.i));
  const history = [];
  function fit(entries, factors, key) {
    const size = settings.factors;
    const matrix = Array.from({ length: size }, () => Array(size).fill(0));
    const right = Array(size).fill(0);
    for (let first = 0; first < size; first++) {
      for (let second = 0; second < size; second++) {
        let total = 0;
        for (const row of entries) total += factors[row[key]][first] * factors[row[key]][second];
        matrix[first][second] = total;
      }
      matrix[first][first] += settings.alsReg * entries.length;
      let total = 0;
      for (const row of entries) total += residual[row.index] * factors[row[key]][first];
      right[first] = total;
    }
    return solve(matrix, right);
  }
  const predict = (user, item) => baseline(user, item) + dot(userFactors[user], itemFactors[item]);
  for (let iteration = 1; iteration <= settings.alsIterations; iteration++) {
    for (let user = 0; user < data.users.length; user++) userFactors[user] = fit(data.users[user].entries, itemFactors, 'i');
    for (let item = 0; item < data.items.length; item++) itemFactors[item] = fit(data.items[item].entries, userFactors, 'u');
    history.push({ method: 'ALS', epoch: iteration, rmse: trainingRmse(data.train, predict) });
  }
  return { userFactors, itemFactors, predict, history };
}

module.exports = { dot, trainSvd, trainAls };
