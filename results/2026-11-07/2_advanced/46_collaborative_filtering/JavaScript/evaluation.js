'use strict';

function clip(value) {
  return value < 1 ? 1 : value > 5 ? 5 : value;
}

function errorMetrics(errors) {
  if (errors.length === 0) return { rmse: null, mae: null };
  let squared = 0;
  let absolute = 0;
  for (const error of errors) {
    squared += error * error;
    absolute += Math.abs(error);
  }
  return { rmse: Math.sqrt(squared / errors.length), mae: absolute / errors.length };
}

function trainingRmse(ratings, predict) {
  let squared = 0;
  for (const row of ratings) {
    const error = row.rating - predict(row.u, row.i);
    squared += error * error;
  }
  return Math.sqrt(squared / ratings.length);
}

function rankWeight(rank) {
  return 1 / Math.log2(rank + 1);
}

function rankingMetrics(items, relevant, cutoff) {
  let hits = 0;
  let dcg = 0;
  let averagePrecision = 0;
  let reciprocalRank = 0;
  for (let index = 0; index < cutoff; index++) {
    if (!relevant.has(items[index])) continue;
    hits++;
    dcg += rankWeight(index + 1);
    averagePrecision += hits / (index + 1);
    if (reciprocalRank === 0) reciprocalRank = 1 / (index + 1);
  }
  const idealCount = Math.min(cutoff, relevant.size);
  let ideal = 0;
  for (let rank = 1; rank <= idealCount; rank++) ideal += rankWeight(rank);
  return { hits, recall: hits / relevant.size, ndcg: dcg / ideal, ap: averagePrecision / idealCount, rr: reciprocalRank };
}

module.exports = { clip, errorMetrics, trainingRmse, rankWeight, rankingMetrics };
