'use strict';

const {combinationIndex} = require('./learning');

function assignmentCount(variables, sizes) {
  let count = 1;
  for (const variable of variables) count *= sizes[variable];
  return count;
}

function* assignments(variables, sizes) {
  const assignment = Array(sizes.length).fill(0);
  for (;;) {
    yield assignment.slice();
    let index = variables.length - 1;
    while (index >= 0) {
      const variable = variables[index];
      assignment[variable]++;
      if (assignment[variable] < sizes[variable]) break;
      assignment[variable] = 0;
      index--;
    }
    if (index < 0) return;
  }
}

function decode(variables, index, sizes) {
  const assignment = Array(sizes.length).fill(0);
  for (let position = variables.length - 1; position >= 0; position--) {
    const variable = variables[position];
    assignment[variable] = index % sizes[variable];
    index = Math.floor(index / sizes[variable]);
  }
  return assignment;
}

function valueAt(factor, assignment, sizes) {
  return factor.values[combinationIndex(factor.variables, assignment, sizes)];
}

function cptFactor(network, index) {
  const variable = network.variables[index];
  const variables = [index, ...variable.parents].sort((a, b) => a - b);
  const values = [];
  for (const assignment of assignments(variables, network.sizes)) {
    values.push(variable.cpt[combinationIndex(variable.parents, assignment, network.sizes)][assignment[index]]);
  }
  return {variables, values};
}

function reduce(factor, evidence, sizes) {
  const variables = factor.variables.filter(variable => !evidence.has(variable));
  const values = [];
  for (const assignment of assignments(variables, sizes)) {
    for (const [variable, state] of evidence) assignment[variable] = state;
    values.push(valueAt(factor, assignment, sizes));
  }
  return {variables, values};
}

function multiply(first, second, sizes) {
  const variables = [...new Set(first.variables.concat(second.variables))].sort((a, b) => a - b);
  const values = [];
  for (const assignment of assignments(variables, sizes)) {
    values.push(valueAt(first, assignment, sizes) * valueAt(second, assignment, sizes));
  }
  return {variables, values};
}

function product(sequence, sizes) {
  if (sequence.length === 0) return {variables: [], values: [1]};
  let result = sequence[0];
  for (let index = 1; index < sequence.length; index++) result = multiply(result, sequence[index], sizes);
  return result;
}

function removeVariable(factor, variable, sizes, maximize) {
  const variables = factor.variables.filter(item => item !== variable);
  const values = [];
  for (const assignment of assignments(variables, sizes)) {
    assignment[variable] = 0;
    let value = valueAt(factor, assignment, sizes);
    for (let state = 1; state < sizes[variable]; state++) {
      assignment[variable] = state;
      const candidate = valueAt(factor, assignment, sizes);
      if (maximize) {
        if (candidate > value) value = candidate;
      } else value += candidate;
    }
    values.push(value);
  }
  return {variables, values};
}

const sumOut = (factor, variable, sizes) => removeVariable(factor, variable, sizes, false);
const maxOut = (factor, variable, sizes) => removeVariable(factor, variable, sizes, true);

module.exports = {assignmentCount, assignments, decode, valueAt, cptFactor, reduce, product, sumOut, maxOut};
