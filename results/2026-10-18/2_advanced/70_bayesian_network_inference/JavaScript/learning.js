'use strict';

function combinationIndex(parents, assignment, sizes) {
  let index = 0;
  for (const parent of parents) index = index * sizes[parent] + assignment[parent];
  return index;
}

function countsFor(network, variable, parents) {
  let combinations = 1;
  for (const parent of parents) combinations *= network.sizes[parent];
  const counts = Array.from({length: combinations}, () => Array(network.sizes[variable]).fill(0));
  for (const sample of network.samples) {
    counts[combinationIndex(parents, sample, network.sizes)][sample[variable]]++;
  }
  return counts;
}

function learnedTable(counts, alpha) {
  return counts.map(row => {
    let total = 0;
    for (const count of row) total += count + alpha;
    return row.map(count => (count + alpha) / total);
  });
}

function logLikelihood(counts, table) {
  let total = 0;
  for (let row = 0; row < counts.length; row++) {
    for (let state = 0; state < counts[row].length; state++) {
      if (counts[row][state] !== 0) total += counts[row][state] * Math.log(table[row][state]);
    }
  }
  return total;
}

function parameters(counts) {
  return (counts[0].length - 1) * counts.length;
}

function familyScore(network, variable, parents) {
  const ordered = parents.slice().sort((a, b) => a - b);
  const counts = countsFor(network, variable, ordered);
  const learned = learnedTable(counts, network.params.alpha);
  return logLikelihood(counts, learned) - parameters(counts) * Math.log(network.samples.length) / 2;
}

module.exports = {combinationIndex, countsFor, learnedTable, logLikelihood, parameters, familyScore};
