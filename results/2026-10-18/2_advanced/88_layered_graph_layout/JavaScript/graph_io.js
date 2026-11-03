'use strict';

const fs = require('node:fs');

const defaults = {
  layering: 'longest', width: 4, promotion: 'off', heuristic: 'barycenter',
  sweeps: 12, node_sep: 2, dummy_sep: 1, layer_gap: 3, direction: 'TB',
  sifting: 'off', reduce: 'off', restarts: 0, seed: 1,
};
const settingsOrder = Object.keys(defaults);
const choices = {
  layering: ['longest', 'coffman'], promotion: ['on', 'off'],
  heuristic: ['barycenter', 'median'], direction: ['TB', 'BT', 'LR', 'RL'],
  sifting: ['on', 'off'], reduce: ['on', 'off'],
};
const ranges = {
  width: [1, 40], sweeps: [0, 50], node_sep: [1, 9], dummy_sep: [1, 9],
  layer_gap: [2, 9], restarts: [0, 9], seed: [1, 2147483646],
};

function settingValue(name, word) {
  if (Object.hasOwn(choices, name)) return choices[name].includes(word) ? word : undefined;
  if (!Object.hasOwn(ranges, name)) return undefined;
  if (word.length < 1 || word.length > 10 || /[^0-9]/.test(word)) return undefined;
  const value = Number(word);
  const [low, high] = ranges[name];
  return value >= low && value <= high ? value : undefined;
}

function lines(filename) {
  return fs.readFileSync('input/' + filename, 'utf8').split('\n');
}

function readInputs() {
  const settings = {...defaults};
  for (const line of lines('params.txt')) {
    if (line === '' || line[0] === '#') continue;
    const [name, word] = line.split(' ');
    settings[name] = settingValue(name, word);
  }
  const graphs = [];
  let graph;
  let declared;
  let accepted;
  const input = lines('graphs.txt');
  for (let index = 0; index < input.length; index++) {
    const line = input[index];
    if (line === '' || line[0] === '#') continue;
    const words = line.split(' ');
    const command = words[0];
    if (command === 'GRAPH') {
      graph = {name: words[1], settings: {...settings}, nodes: [], edges: [],
        path: null, error: null, selfLoops: 0, duplicates: 0};
      declared = new Set();
      accepted = new Set();
      continue;
    }
    if (command === 'END') {
      if (graph.error === null && graph.nodes.length === 0) graph.error = {kind: 'no_nodes', line: index + 1};
      graphs.push(graph);
      continue;
    }
    if (graph.error !== null) continue;
    let error = null;
    if (command === 'OPTION') {
      const value = settingValue(words[1], words[2]);
      if (value === undefined) error = 'bad_option';
      else graph.settings[words[1]] = value;
    } else if (command === 'NODE') {
      const id = Number(words[1]);
      if (declared.has(id)) error = 'duplicate_node';
      else if (graph.nodes.length === 40) error = 'too_many_nodes';
      else {
        declared.add(id);
        graph.nodes.push({id, label: words[2]});
      }
    } else {
      const from = Number(words[1]);
      const to = Number(words[2]);
      if (!declared.has(from) || !declared.has(to)) error = 'unknown_node';
      else if (command === 'PATH') graph.path = [from, to];
      else if (from === to) graph.selfLoops++;
      else if (accepted.has(from + ',' + to)) graph.duplicates++;
      else {
        accepted.add(from + ',' + to);
        graph.edges.push({from, to});
      }
    }
    if (error !== null) graph.error = {kind: error, line: index + 1};
  }
  return graphs;
}

module.exports = {readInputs, settingsOrder};
