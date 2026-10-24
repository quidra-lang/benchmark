'use strict';

const { isNonterminal } = require('./grammar_parser');

function treeNode(symbol) {
  return { symbol, mark: null, children: [] };
}

function parse(grammar, table, sets, input) {
  const root = treeNode(grammar.start);
  const stack = [{ symbol: '$', node: null }, { symbol: grammar.start, node: root }];
  const trace = [];
  const leftParse = [];
  const counts = { skip: 0, pop: 0, missing: 0 };
  let position = 0;
  let matches = 0;
  let maximumStack = 0;
  while (true) {
    const top = stack.at(-1);
    const token = input[position];
    maximumStack = Math.max(maximumStack, stack.length);
    const step = { number: trace.length + 1, stack: stack.map(entry => entry.symbol),
      input: input.slice(position).map(entry => entry.value), top: top.symbol, token };
    if (top.symbol === '$' && token.value === '$') step.action = 'accept';
    else if (top.symbol === '$') {
      step.action = 'skip';
      position++;
    } else if (!isNonterminal(top.symbol)) {
      stack.pop();
      if (top.symbol === token.value) {
        step.action = 'match';
        position++;
        matches++;
      } else {
        step.action = 'missing';
        top.node.mark = 'missing';
      }
    } else {
      const production = table.choices.get(top.symbol).get(token.value);
      if (production) {
        step.action = 'predict';
        step.production = production;
        leftParse.push(production.number);
        stack.pop();
        top.node.children = production.right.length ? production.right.map(treeNode) : [treeNode('%empty')];
        for (let index = production.right.length - 1; index >= 0; index--) {
          stack.push({ symbol: production.right[index], node: top.node.children[index] });
        }
      } else if (token.value === '$' || sets.follow.get(top.symbol).has(token.value)) {
        step.action = 'pop';
        top.node.mark = 'error';
        stack.pop();
      } else {
        step.action = 'skip';
        position++;
      }
    }
    if (Object.hasOwn(counts, step.action)) counts[step.action]++;
    trace.push(step);
    if (step.action === 'accept') break;
  }
  return { trace, root, leftParse, counts, matches, maximumStack };
}

module.exports = { parse };
