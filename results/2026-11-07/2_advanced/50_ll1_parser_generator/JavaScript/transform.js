'use strict';

const { isNonterminal, notation, copyGrammar } = require('./grammar_parser');

function freshName(grammar, source) {
  let name = source;
  do name = name.slice(0, -1) + "'>";
  while (grammar.rules.has(name));
  return name;
}

function leadingReachable(grammar, source, target) {
  const queue = [source];
  const seen = new Set(queue);
  for (let head = 0; head < queue.length; head++) {
    for (const right of grammar.rules.get(queue[head])) {
      const symbol = right[0];
      if (symbol === target) return true;
      if (symbol !== undefined && isNonterminal(symbol) && !seen.has(symbol)) {
        seen.add(symbol);
        queue.push(symbol);
      }
    }
  }
  return false;
}

function unique(alternatives) {
  const seen = new Set();
  return alternatives.filter(right => {
    const key = JSON.stringify(right);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function eliminate(original) {
  const grammar = copyGrammar(original);
  const order = original.order;
  const log = [];
  for (let index = 0; index < order.length; index++) {
    const left = order[index];
    for (let earlier = 0; earlier < index; earlier++) {
      const source = order[earlier];
      if (!grammar.rules.get(left).some(right => right[0] === source) || !leadingReachable(grammar, source, left)) continue;
      const alternatives = [];
      for (const right of grammar.rules.get(left)) {
        if (right[0] === source) {
          for (const replacement of grammar.rules.get(source)) alternatives.push([...replacement, ...right.slice(1)]);
        } else alternatives.push(right);
      }
      grammar.rules.set(left, unique(alternatives));
      log.push(`substitute ${source} into ${left}`);
    }
    let alternatives = grammar.rules.get(left);
    if (alternatives.some(right => right.length === 1 && right[0] === left)) {
      alternatives = alternatives.filter(right => right.length !== 1 || right[0] !== left);
      grammar.rules.set(left, alternatives);
      log.push(`remove cycle ${left} -> ${left}`);
    }
    const recursive = alternatives.filter(right => right[0] === left);
    if (recursive.length === 0) continue;
    const name = freshName(grammar, left);
    grammar.rules.set(left, alternatives.filter(right => right[0] !== left).map(right => [...right, name]));
    grammar.rules.set(name, [...recursive.map(right => [...right.slice(1), name]), []]);
    grammar.order.splice(grammar.order.indexOf(left) + 1, 0, name);
    log.push(`eliminate left recursion in ${left} with ${name}`);
  }
  return { grammar, log };
}

function factor(original) {
  const grammar = copyGrammar(original);
  const log = [];
  for (let index = 0; index < grammar.order.length; index++) {
    const left = grammar.order[index];
    const alternatives = grammar.rules.get(left);
    const used = new Set();
    const replacement = [];
    const created = [];
    for (const right of alternatives) {
      if (right.length === 0) {
        replacement.push(right);
        continue;
      }
      if (used.has(right[0])) continue;
      used.add(right[0]);
      const group = alternatives.filter(other => other[0] === right[0]);
      if (group.length === 1) {
        replacement.push(right);
        continue;
      }
      let length = 0;
      while (length < right.length && group.every(other => other[length] === right[length])) length++;
      const prefix = right.slice(0, length);
      const name = freshName(grammar, left);
      grammar.rules.set(name, group.map(other => other.slice(length)));
      replacement.push([...prefix, name]);
      created.push(name);
      log.push(`left factor ${left} on ${notation(prefix)} with ${name}`);
    }
    grammar.rules.set(left, replacement);
    grammar.order.splice(index + 1, 0, ...created);
  }
  return { grammar, log };
}

module.exports = { eliminate, factor };
