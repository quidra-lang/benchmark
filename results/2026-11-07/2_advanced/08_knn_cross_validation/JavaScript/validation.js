'use strict';

const { fitScaling, transform } = require('./scaling');
const { compareText, neighborOrder, vote } = require('./neighbors');

function stratifiedSplit(rows, count) {
  const sorted = [...rows].sort((left, right) => compareText(left.label, right.label) || compareText(left.id, right.id));
  const assignments = new Map(sorted.map((row, index) => [row.id, index % count]));
  return Array.from({ length: count }, (_, index) => rows.filter(row => assignments.get(row.id) === index));
}

class Predictor {
  constructor(rows, features = rows[0].features.map((_, index) => index)) {
    this.rows = rows;
    this.features = features;
    this.scalings = new Map();
    this.orders = new Map();
  }

  order(query, model) {
    if (!this.scalings.has(model.scaling)) {
      const scaling = fitScaling(this.rows, model.scaling);
      this.scalings.set(model.scaling, { scaling,
        reference: this.rows.map(row => ({ row, vector: transform(row, scaling, this.features) })) });
    }
    const key = `${model.scaling}:${model.metric}`;
    if (!this.orders.has(key)) this.orders.set(key, new Map());
    const orders = this.orders.get(key);
    if (!orders.has(query.id)) {
      const { scaling, reference } = this.scalings.get(model.scaling);
      orders.set(query.id, neighborOrder(reference, transform(query, scaling, this.features), model.metric));
    }
    return orders.get(query.id);
  }

  predict(query, model) {
    return vote(this.order(query, model), model.k, model.weighting);
  }
}

function regression(pairs) {
  if (pairs.length === 0) return { count: 0, rmse: null, mae: null, r2: null };
  let squared = 0, absolute = 0, total = 0;
  for (const pair of pairs) {
    const error = pair.estimate - pair.target;
    squared += error * error;
    absolute += Math.abs(error);
    total += pair.target;
  }
  const mean = total / pairs.length;
  let variation = 0;
  for (const pair of pairs) {
    const difference = pair.target - mean;
    variation += difference * difference;
  }
  return { count: pairs.length, rmse: Math.sqrt(squared / pairs.length), mae: absolute / pairs.length,
    r2: variation === 0 ? null : 1 - squared / variation };
}

module.exports = { stratifiedSplit, Predictor, regression };
