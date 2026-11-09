'use strict';

const FEATURES = ['recency', 'frequency', 'monetary', 'basket', 'categories', 'tenure'];
const SQUARE_ROOT = new Set([1, 2, 3]);
const transformValues = values => values.map((value, index) => SQUARE_ROOT.has(index) ? Math.sqrt(value) : value);

function meanSD(values) {
  let total = 0;
  for (const value of values) total += value;
  const mean = total / values.length;
  let squared = 0;
  for (const value of values) { const difference = value - mean; squared += difference * difference; }
  return { mean, sd: values.length === 1 ? 0 : Math.sqrt(squared / (values.length - 1)) };
}

function customerFeatures(orders, day) {
  const groups = new Map();
  for (const order of orders) {
    if (order.net <= 0) continue;
    if (!groups.has(order.customer)) groups.set(order.customer, []);
    groups.get(order.customer).push(order);
  }
  return [...groups.keys()].sort().map(id => {
    const purchases = groups.get(id), categorySpend = new Map();
    let first = purchases[0].day, last = first, spend = 0;
    for (const order of purchases) {
      first = Math.min(first, order.day); last = Math.max(last, order.day); spend += order.net;
      for (const row of order.rows) categorySpend.set(row.category, (categorySpend.get(row.category) || 0) + row.amount);
    }
    const monetary = spend / 100, frequency = purchases.length;
    const raw = [day - last, frequency, monetary, monetary / frequency,
      [...categorySpend.values()].filter(value => value > 0).length, day - first];
    return { id, purchases, spend, categorySpend, raw, transformed: transformValues(raw) };
  });
}

function fitStandardization(customers) {
  return FEATURES.map((_, feature) => {
    const raw = meanSD(customers.map(customer => customer.raw[feature]));
    return { ...meanSD(customers.map(customer => customer.transformed[feature])), rawMean: raw.mean, rawSD: raw.sd };
  });
}

function standardize(customers, scaling) {
  for (const customer of customers) customer.point = customer.transformed.map((value, feature) =>
    scaling[feature].sd === 0 ? 0 : (value - scaling[feature].mean) / scaling[feature].sd);
}

function correlation(customers) {
  return FEATURES.map((_, first) => FEATURES.map((__, second) => {
    let total = 0;
    for (const customer of customers) total += customer.point[first] * customer.point[second];
    return total / (customers.length - 1);
  }));
}

module.exports = { FEATURES, SQUARE_ROOT, meanSD, customerFeatures, fitStandardization, standardize, correlation };
