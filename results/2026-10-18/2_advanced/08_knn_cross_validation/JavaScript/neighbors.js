'use strict';

const compareText = (left, right) => left < right ? -1 : left > right ? 1 : 0;

function distance(left, right, metric) {
  let total = 0, dot = 0, normLeft = 0, normRight = 0;
  for (let index = 0; index < left.length; index++) {
    const difference = left[index] - right[index];
    if (metric === 'squared_euclidean') total += difference * difference;
    else if (metric === 'manhattan') total += Math.abs(difference);
    else if (metric === 'chebyshev') total = Math.max(total, Math.abs(difference));
    else {
      dot += left[index] * right[index];
      normLeft += left[index] * left[index];
      normRight += right[index] * right[index];
    }
  }
  if (metric !== 'cosine') return total;
  const first = Math.sqrt(normLeft), second = Math.sqrt(normRight);
  return first === 0 || second === 0 ? 1 : 1 - dot / (first * second);
}

function neighborOrder(reference, query, metric) {
  return reference.map(item => ({ row: item.row, distance: distance(query, item.vector, metric) }))
    .sort((left, right) => left.distance - right.distance || compareText(left.row.id, right.row.id));
}

function vote(order, k, weighting) {
  const neighbors = order.slice(0, Math.min(k, order.length)), labels = new Map();
  let weightTotal = 0, targetTotal = 0, weightedTarget = 0;
  for (const neighbor of neighbors) {
    const weight = 1 / (neighbor.distance + 0.000000001), label = neighbor.row.label;
    if (!labels.has(label)) labels.set(label, { label, count: 0, distance: 0, weight: 0 });
    const group = labels.get(label);
    group.count++;
    group.distance += neighbor.distance;
    group.weight += weight;
    weightTotal += weight;
    targetTotal += neighbor.row.target;
    weightedTarget += weight * neighbor.row.target;
  }
  const ranked = [...labels.values()].sort((left, right) =>
    (weighting === 'uniform' ? right.count - left.count : right.weight - left.weight)
    || left.distance - right.distance || compareText(left.label, right.label));
  const share = group => weighting === 'uniform' ? group.count / neighbors.length : group.weight / weightTotal;
  return { label: ranked[0].label, share: share(ranked[0]), runnerUp: ranked[1]?.label ?? null,
    runnerShare: ranked.length > 1 ? share(ranked[1]) : 0,
    estimate: weighting === 'uniform' ? targetTotal / neighbors.length : weightedTarget / weightTotal,
    neighbors };
}

module.exports = { compareText, distance, neighborOrder, vote };
