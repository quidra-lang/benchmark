'use strict';

const { isNonterminal } = require('./grammar_parser');
const { firstOf } = require('./first_follow');

function numberProductions(grammar) {
  const productions = [];
  for (const left of grammar.order) {
    for (const right of grammar.rules.get(left)) productions.push({ number: productions.length + 1, left, right });
  }
  return productions;
}

function buildTable(grammar, sets) {
  const productions = numberProductions(grammar);
  const known = new Set();
  for (const production of productions) for (const symbol of production.right) if (!isNonterminal(symbol)) known.add(symbol);
  const columns = [...known].sort();
  columns.push('$');
  const cells = new Map(grammar.order.map(left => [left, new Map(columns.map(terminal => [terminal, []]))]));
  const byLeft = new Map(grammar.order.map(left => [left, []]));
  for (const production of productions) {
    const sequence = firstOf(production.right, sets.nullable, sets.first);
    const reasons = new Map([...sequence.terminals].map(terminal => [terminal, 'FIRST']));
    if (sequence.nullable) {
      for (const terminal of sets.follow.get(production.left)) if (!reasons.has(terminal)) reasons.set(terminal, 'FOLLOW');
    }
    production.reasons = reasons;
    byLeft.get(production.left).push(production);
    for (const terminal of reasons.keys()) cells.get(production.left).get(terminal).push(production);
  }
  const choices = new Map(grammar.order.map(left => [left, new Map()]));
  const conflicts = [];
  for (const left of grammar.order) {
    for (const terminal of columns) {
      const entries = cells.get(left).get(terminal);
      if (entries.length === 0) continue;
      const chosen = entries.find(production => production.reasons.get(terminal) === 'FIRST') ?? entries[0];
      choices.get(left).set(terminal, chosen);
      if (entries.length < 2) continue;
      const reasons = new Set(entries.map(production => production.reasons.get(terminal)));
      const kind = reasons.size === 2 ? 'FIRST/FOLLOW' : reasons.has('FIRST') ? 'FIRST/FIRST' : 'FOLLOW/FOLLOW';
      conflicts.push({ left, terminal, entries, chosen, kind });
    }
  }
  return { productions, known, columns, cells, choices, conflicts, byLeft };
}

module.exports = { numberProductions, buildTable };
