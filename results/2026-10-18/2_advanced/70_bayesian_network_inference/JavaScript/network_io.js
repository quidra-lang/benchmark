'use strict';

const fs = require('node:fs');

function lines(name) {
  const text = fs.readFileSync('input/' + name, 'ascii');
  return text === '' ? [] : text.slice(0, -1).split('\n');
}

function readNetwork() {
  const source = lines('network.txt').filter(line => line !== '' && !line.startsWith('#'));
  const variables = [];
  const names = new Map();
  for (let index = 0; index < source.length; index++) {
    const fields = source[index].split(' ');
    if (fields[0] === 'VARIABLE') {
      names.set(fields[1], variables.length);
      variables.push({name: fields[1], states: fields.slice(2), parents: [], given: null});
    } else if (fields[0] === 'PARENTS') {
      variables[names.get(fields[1])].parents = fields.slice(2).map(name => names.get(name));
    } else {
      const variable = variables[names.get(fields[1])];
      let count = 1;
      for (const parent of variable.parents) count *= variables[parent].states.length;
      variable.given = [];
      for (let row = 0; row < count; row++) variable.given.push(source[++index].split(' ').map(Number));
    }
  }
  return {variables, names, sizes: variables.map(variable => variable.states.length)};
}

function readInputs() {
  const network = readNetwork();
  const stateNames = network.variables.map(variable => new Map(variable.states.map((name, index) => [name, index])));
  const source = lines('samples.csv');
  const columns = source[0].split(',').map(name => network.names.get(name));
  const samples = source.slice(1).map(line => {
    const values = line.split(',');
    const assignment = Array(network.variables.length);
    for (let column = 0; column < columns.length; column++) {
      const variable = columns[column];
      assignment[variable] = stateNames[variable].get(values[column]);
    }
    return assignment;
  });
  const settings = lines('params.txt').map(line => line.split(' '));
  const params = {alpha: Number(settings[0][1]), method: settings[1][1].toLowerCase(),
    order: settings[2].slice(1).map(name => network.names.get(name)),
    limit: Number(settings[3][1]), seed: Number(settings[4][1])};
  for (let index = 5; index < settings.length; index++) {
    network.variables[network.names.get(settings[index][1])].source = settings[index][2];
  }
  return {...network, stateNames, samples, params, queries: lines('queries.txt')};
}

module.exports = {readInputs};
