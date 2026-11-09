'use strict';

class Stump {
  constructor(feature, thresholds, values) {
    this.feature = feature;
    this.thresholds = thresholds;
    this.values = values;
  }

  output(values) {
    let bin = 0;
    for (const threshold of this.thresholds) if (values[this.feature] > threshold) bin++;
    return this.values[bin];
  }
}

function prepare(rows) {
  return rows[0].values.map((value, feature) => {
    const order = rows.map((row, index) => index);
    order.sort((a, b) => rows[a].values[feature] - rows[b].values[feature] || a - b);
    const groups = [];
    const distinct = [];
    for (const index of order) {
      const current = rows[index].values[feature];
      if (distinct.length === 0 || distinct.at(-1) !== current) {
        distinct.push(current);
        groups.push([]);
      }
      groups.at(-1).push(index);
    }
    const thresholds = [distinct[0] - 1];
    for (let i = 1; i < distinct.length; i++) thresholds.push((distinct[i - 1] + distinct[i]) / 2);
    return { feature, order, groups, thresholds };
  });
}

function choose(candidates) {
  let minimum = candidates[0].error;
  for (const candidate of candidates) if (candidate.error < minimum) minimum = candidate.error;
  for (const candidate of candidates) if (candidate.error <= minimum + 1e-9) return candidate;
}

function discreteSearch(rows, weights, plans) {
  let positive = 0;
  let negative = 0;
  for (let i = 0; i < rows.length; i++) {
    positive += rows[i].label === 1 ? weights[i] : 0;
    negative += rows[i].label === -1 ? weights[i] : 0;
  }
  const candidates = [];
  for (const plan of plans) {
    let leftPositive = 0;
    let leftNegative = 0;
    for (let k = 0; k < plan.thresholds.length; k++) {
      if (k > 0) {
        for (const i of plan.groups[k - 1]) {
          leftPositive += rows[i].label === 1 ? weights[i] : 0;
          leftNegative += rows[i].label === -1 ? weights[i] : 0;
        }
      }
      const common = { feature: plan.feature, threshold: plan.thresholds[k] };
      candidates.push({ ...common, polarity: 1, error: leftPositive + (negative - leftNegative) });
      candidates.push({ ...common, polarity: -1, error: leftNegative + (positive - leftPositive) });
    }
  }
  return choose(candidates);
}

function regressionSearch(rows, targets, weights, plans) {
  let weight = 0;
  let total = 0;
  let squares = 0;
  for (let i = 0; i < rows.length; i++) {
    weight += weights[i];
    total += weights[i] * targets[i];
    squares += weights[i] * targets[i] * targets[i];
  }
  const candidates = [];
  for (const plan of plans) {
    let leftWeight = 0;
    let leftTotal = 0;
    for (let k = 0; k < plan.thresholds.length; k++) {
      if (k > 0) {
        for (const i of plan.groups[k - 1]) {
          leftWeight += weights[i];
          leftTotal += weights[i] * targets[i];
        }
      }
      const rightWeight = weight - leftWeight;
      const rightTotal = total - leftTotal;
      const left = k === 0 ? 0 : leftTotal / leftWeight;
      const gain = k === 0 ? rightTotal * rightTotal / rightWeight :
        leftTotal * leftTotal / leftWeight + rightTotal * rightTotal / rightWeight;
      const right = rightTotal / rightWeight;
      candidates.push({ stump: new Stump(plan.feature, [plan.thresholds[k]], [left, right]), error: squares - gain });
    }
  }
  return choose(candidates);
}

function largestIndex(values) {
  let best = 0;
  for (let i = 1; i < values.length; i++) if (values[i] > values[best]) best = i;
  return best;
}

function multiclassSearch(rows, weights, plans, classes) {
  let total = 0;
  const totals = Array(classes).fill(0);
  for (let i = 0; i < rows.length; i++) {
    total += weights[i];
    for (let c = 0; c < classes; c++) totals[c] += rows[i].category === c + 1 ? weights[i] : 0;
  }
  const candidates = [];
  for (const plan of plans) {
    const left = Array(classes).fill(0);
    for (let k = 0; k < plan.thresholds.length; k++) {
      if (k > 0) {
        for (const i of plan.groups[k - 1]) {
          for (let c = 0; c < classes; c++) left[c] += rows[i].category === c + 1 ? weights[i] : 0;
        }
      }
      const right = totals.map((value, c) => value - left[c]);
      const a = largestIndex(left);
      const b = largestIndex(right);
      candidates.push({ stump: new Stump(plan.feature, [plan.thresholds[k]], [a + 1, b + 1]),
        error: total - (left[a] + right[b]) });
    }
  }
  return choose(candidates);
}

function realPlans(rows, bins) {
  return prepare(rows).map(plan => {
    const cuts = [];
    for (let b = 1; b < bins; b++) {
      const r = Math.floor(b * rows.length / bins);
      cuts.push((rows[plan.order[r - 1]].values[plan.feature] + rows[plan.order[r]].values[plan.feature]) / 2);
    }
    const assignments = rows.map(row => {
      let bin = 0;
      for (const cut of cuts) if (cut < row.values[plan.feature]) bin++;
      return bin;
    });
    return { feature: plan.feature, cuts, assignments };
  });
}

function realSearch(rows, weights, plans, bins) {
  const candidates = [];
  for (const plan of plans) {
    const positive = Array(bins).fill(0);
    const negative = Array(bins).fill(0);
    for (let i = 0; i < rows.length; i++) {
      const bin = plan.assignments[i];
      if (rows[i].label === 1) positive[bin] += weights[i];
      else negative[bin] += weights[i];
    }
    let overlap = 0;
    for (let b = 0; b < bins; b++) overlap += Math.sqrt(positive[b] * negative[b]);
    candidates.push({ feature: plan.feature, cuts: plan.cuts, positive, negative, error: 2 * overlap });
  }
  return choose(candidates);
}

module.exports = { Stump, prepare, choose, discreteSearch, regressionSearch, multiclassSearch, realPlans, realSearch };
