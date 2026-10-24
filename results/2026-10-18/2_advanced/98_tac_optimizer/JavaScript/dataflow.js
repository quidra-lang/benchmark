'use strict';

const { definition, uses, variable, expression, expressionKey } = require('./tac_parser');
const { buildCFG, equalSets, intersection } = require('./cfg');
const definitionKey = (name, number) => number + ':' + name;
const copyKey = (left, right) => left + ',' + right;
const union = sets => new Set(sets.flatMap(set => Array.from(set)));

function liveTransfer(instruction, state) {
  const next = new Set(state); next.delete(definition(instruction));
  for (const name of uses(instruction)) next.add(name);
  return next;
}

function analyze(fn) {
  const graph = buildCFG(fn), definitions = new Map(), expressions = new Map(), copyPairs = new Map();
  const parameters = new Set(fn.parameters.map(name => definitionKey(name, 0)));
  for (const name of fn.parameters) definitions.set(definitionKey(name, 0), { name, number: 0 });
  for (const block of graph.blocks) if (graph.reachable.has(block.number)) {
    for (const instruction of block.instructions) {
      const name = definition(instruction);
      if (name !== undefined) definitions.set(definitionKey(name, instruction.number), { name, number: instruction.number });
      const value = expression(instruction);
      if (value !== null) expressions.set(expressionKey(instruction), value);
      if (instruction.kind === 'copy' && variable(instruction.a) && instruction.a !== instruction.dest) {
        copyPairs.set(copyKey(instruction.dest, instruction.a), [instruction.dest, instruction.a]);
      }
    }
  }
  const transfers = {
    rd(instruction, state) {
      const next = new Set(state), name = definition(instruction);
      if (name !== undefined) {
        for (const key of next) if (definitions.get(key).name === name) next.delete(key);
        next.add(definitionKey(name, instruction.number));
      }
      return next;
    },
    available(instruction, state) {
      const next = new Set(state), key = expressionKey(instruction), name = definition(instruction);
      if (key !== null) next.add(key);
      for (const candidate of next) {
        const value = expressions.get(candidate);
        if ((instruction.kind === 'store' && value.kind === 'load' && value.array === instruction.array)
            || (instruction.kind === 'call' && value.kind === 'load')
            || (name !== undefined && (value.a === name || value.b === name))) next.delete(candidate);
      }
      return next;
    },
    copies(instruction, state) {
      const next = new Set(state), name = definition(instruction);
      if (name !== undefined) for (const key of next) if (copyPairs.get(key).includes(name)) next.delete(key);
      if (instruction.kind === 'copy' && variable(instruction.a) && instruction.dest !== instruction.a) next.add(copyKey(instruction.dest, instruction.a));
      return next;
    }
  };
  const flows = {};
  for (const kind of ['rd', 'live', 'available', 'copies']) {
    const live = kind === 'live', universe = kind === 'available' ? new Set(expressions.keys()) :
      kind === 'copies' ? new Set(copyPairs.keys()) : new Set();
    const incoming = new Map(), outgoing = new Map();
    for (const n of graph.reachable) { incoming.set(n, new Set()); outgoing.set(n, new Set(universe)); }
    let changed, iterations = 0;
    do {
      changed = false; iterations++;
      for (const n of live ? graph.postorder : graph.reversePostorder) {
        const block = graph.byNumber.get(n);
        if (live) {
          const out = union(block.successors.map(s => incoming.get(s)));
          let state = out;
          for (let i = block.instructions.length - 1; i >= 0; i--) state = liveTransfer(block.instructions[i], state);
          if (!equalSets(state, incoming.get(n))) changed = true;
          outgoing.set(n, out); incoming.set(n, state);
        } else {
          const predecessorSets = graph.reachablePredecessors(n).map(p => outgoing.get(p));
          const entry = kind === 'rd' ? union(n === 1 ? [parameters, ...predecessorSets] : predecessorSets) :
            n === 1 ? new Set() : intersection(predecessorSets);
          let state = entry;
          for (const instruction of block.instructions) state = transfers[kind](instruction, state);
          if (!equalSets(state, outgoing.get(n))) changed = true;
          incoming.set(n, entry); outgoing.set(n, state);
        }
      }
    } while (changed);
    const before = new Map(), after = new Map();
    for (const block of graph.blocks) if (graph.reachable.has(block.number)) {
      if (live) {
        let state = outgoing.get(block.number);
        for (let i = block.instructions.length - 1; i >= 0; i--) {
          const instruction = block.instructions[i]; after.set(instruction.number, state);
          state = liveTransfer(instruction, state); before.set(instruction.number, state);
        }
      } else {
        let state = incoming.get(block.number);
        for (const instruction of block.instructions) {
          before.set(instruction.number, state); state = transfers[kind](instruction, state); after.set(instruction.number, state);
        }
      }
    }
    flows[kind] = { incoming, outgoing, before, after, iterations };
  }
  return { ...graph, ...flows, definitions, expressions, copyPairs };
}

function reaching(analysis, instruction, name) {
  return Array.from(analysis.rd.before.get(instruction.number)).map(key => analysis.definitions.get(key)).filter(value => value.name === name);
}

module.exports = { analyze, reaching, liveTransfer };
