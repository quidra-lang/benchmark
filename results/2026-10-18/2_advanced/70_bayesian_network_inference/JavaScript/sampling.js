'use strict';

const {combinationIndex} = require('./learning');

class Minstd {
  constructor(seed) {
    this.state = seed;
  }

  next() {
    this.state = 48271 * this.state % 2147483647;
    return this.state / 2147483647;
  }
}

function chooseState(probabilities, random) {
  const draw = random.next();
  let cumulative = 0;
  for (let state = 0; state < probabilities.length; state++) {
    cumulative += probabilities[state];
    if (draw < cumulative) return state;
  }
  return probabilities.length - 1;
}

function weightedSample(network, evidence, random) {
  const assignment = Array(network.variables.length).fill(0);
  let weight = 1;
  for (const index of network.topological) {
    const variable = network.variables[index];
    const row = variable.cpt[combinationIndex(variable.parents, assignment, network.sizes)];
    if (evidence.has(index)) {
      assignment[index] = evidence.get(index);
      weight *= row[assignment[index]];
    } else assignment[index] = chooseState(row, random);
  }
  return {assignment, weight};
}

module.exports = {Minstd, chooseState, weightedSample};
