'use strict';

function isNonterminal(symbol) {
  return symbol.startsWith('<') && symbol.endsWith('>');
}

function notation(symbols) {
  return symbols.length ? symbols.join(' ') : '%empty';
}

function productionText(left, right) {
  return left + ' -> ' + notation(right);
}

function copyGrammar(grammar) {
  return { start: grammar.start, order: grammar.order.slice(),
    rules: new Map([...grammar.rules].map(([left, alternatives]) => [left, alternatives.map(right => right.slice())])) };
}

function tokenize(line) {
  const tokens = [];
  let position = 0;
  while (position < line.length) {
    if (line[position] === ' ') {
      position++;
      continue;
    }
    if (line[position] === '#') break;
    const rest = line.slice(position);
    let kind = 'invalid';
    let text = '';
    let value = '';
    let match;
    if ((match = /^<[A-Za-z][A-Za-z0-9_]*>/.exec(rest))) {
      kind = 'nonterminal';
      text = value = match[0];
    } else if ((match = /^"([^ "]+)"/.exec(rest))) {
      kind = 'quoted';
      text = match[0];
      value = match[1];
    } else if ((match = /^[A-Za-z][A-Za-z0-9_]*/.exec(rest))) {
      kind = 'word';
      text = value = match[0];
    } else if (rest.startsWith('::=')) {
      kind = 'definition';
      text = value = '::=';
    } else if (rest[0] === '|') {
      kind = 'separator';
      text = value = '|';
    } else if ((match = /^%([A-Za-z]+)/.exec(rest)) && ['empty', 'start', 'token'].includes(match[1])) {
      kind = match[1];
      text = value = match[0];
    }
    tokens.push({ kind, value, start: position + 1, end: position + text.length });
    if (kind === 'invalid') break;
    position += text.length;
  }
  return tokens;
}

function syntaxError(tokens) {
  let state = 'begin';
  for (const token of tokens) {
    const kind = token.kind;
    let next = null;
    if (state === 'begin') {
      if (kind === 'nonterminal') next = 'definition';
      else if (kind === 'separator') next = 'alternative';
      else if (kind === 'start') next = 'start_symbol';
      else if (kind === 'token') next = 'declaration';
    } else if (state === 'definition') {
      if (kind === 'definition') next = 'alternative';
    } else if (state === 'alternative') {
      if (['nonterminal', 'word', 'quoted'].includes(kind)) next = 'symbols';
      else if (kind === 'empty') next = 'empty';
    } else if (state === 'symbols') {
      if (['nonterminal', 'word', 'quoted'].includes(kind)) next = 'symbols';
      else if (kind === 'separator') next = 'alternative';
    } else if (state === 'empty') {
      if (kind === 'separator') next = 'alternative';
    } else if (state === 'start_symbol') {
      if (kind === 'nonterminal') next = 'complete';
    } else if (state === 'declaration' || state === 'words') {
      if (kind === 'word') next = 'words';
    }
    if (next === null) return token.start;
    state = next;
  }
  return ['symbols', 'empty', 'complete', 'words'].includes(state) ? null : tokens.at(-1).end + 1;
}

function parseGrammar(lines) {
  const grammar = { start: null, order: [], rules: new Map() };
  const declared = new Set();
  const wordLines = new Map();
  const diagnostics = [];
  let hasDeclarations = false;
  let attached = null;
  lines.forEach((line, index) => {
    const number = index + 1;
    const tokens = tokenize(line);
    if (tokens.length === 0) return;
    const column = syntaxError(tokens);
    if (column !== null) {
      diagnostics.push(`line ${number}: syntax error at column ${column}`);
      attached = null;
      return;
    }
    const first = tokens[0];
    if (first.kind === 'start') {
      if (grammar.start === null) grammar.start = tokens[1].value;
      else diagnostics.push(`line ${number}: duplicate %start`);
      attached = null;
      return;
    }
    if (first.kind === 'token') {
      hasDeclarations = true;
      for (const token of tokens.slice(1)) declared.add(token.value);
      attached = null;
      return;
    }
    let offset = 1;
    if (first.kind === 'nonterminal') {
      attached = first.value;
      if (!grammar.rules.has(attached)) {
        grammar.order.push(attached);
        grammar.rules.set(attached, []);
      }
      offset = 2;
    } else if (attached === null) {
      diagnostics.push(`line ${number}: continuation without a rule`);
      return;
    }
    const alternatives = [[]];
    for (const token of tokens.slice(offset)) {
      if (token.kind === 'separator') alternatives.push([]);
      else if (token.kind !== 'empty') alternatives.at(-1).push(token.value);
      if (token.kind === 'word' && !wordLines.has(token.value)) wordLines.set(token.value, number);
    }
    const previous = grammar.rules.get(attached);
    const seen = new Set(previous.map(right => JSON.stringify(right)));
    for (const right of alternatives) {
      const key = JSON.stringify(right);
      if (seen.has(key)) diagnostics.push(`line ${number}: duplicate alternative ${productionText(attached, right)}`);
      else {
        seen.add(key);
        previous.push(right);
      }
    }
  });
  if (grammar.start === null) grammar.start = grammar.order[0];
  return { grammar, declared, hasDeclarations, wordLines, diagnostics };
}

module.exports = { isNonterminal, notation, productionText, copyGrammar, parseGrammar };
