'use strict';

const { isNonterminal } = require('./grammar_parser');

function firstOf(symbols, nullable, first) {
  const terminals = new Set();
  for (const symbol of symbols) {
    if (!isNonterminal(symbol)) {
      terminals.add(symbol);
      return { terminals, nullable: false };
    }
    for (const terminal of first.get(symbol)) terminals.add(terminal);
    if (!nullable.get(symbol)) return { terminals, nullable: false };
  }
  return { terminals, nullable: true };
}

function addAll(target, values) {
  let changed = false;
  for (const value of values) {
    if (!target.has(value)) {
      target.add(value);
      changed = true;
    }
  }
  return changed;
}

function computeSets(grammar) {
  const nullable = new Map(grammar.order.map(name => [name, false]));
  const first = new Map(grammar.order.map(name => [name, new Set()]));
  const follow = new Map(grammar.order.map(name => [name, new Set()]));
  follow.get(grammar.start).add('$');
  const passes = { nullable: 0, first: 0, follow: 0 };
  let changed;
  do {
    changed = false;
    passes.nullable++;
    for (const name of grammar.order) {
      if (nullable.get(name)) continue;
      if (grammar.rules.get(name).some(right => right.every(symbol => isNonterminal(symbol) && nullable.get(symbol)))) {
        nullable.set(name, true);
        changed = true;
      }
    }
  } while (changed);
  do {
    changed = false;
    passes.first++;
    for (const name of grammar.order) {
      for (const right of grammar.rules.get(name)) {
        if (addAll(first.get(name), firstOf(right, nullable, first).terminals)) changed = true;
      }
    }
  } while (changed);
  do {
    changed = false;
    passes.follow++;
    for (const name of grammar.order) {
      for (const right of grammar.rules.get(name)) {
        for (let index = 0; index < right.length; index++) {
          const symbol = right[index];
          if (!isNonterminal(symbol)) continue;
          const suffix = firstOf(right.slice(index + 1), nullable, first);
          if (addAll(follow.get(symbol), suffix.terminals)) changed = true;
          if (suffix.nullable && addAll(follow.get(symbol), follow.get(name))) changed = true;
        }
      }
    }
  } while (changed);
  return { nullable, first, follow, passes };
}

module.exports = { firstOf, computeSets };
