'use strict';

const fs = require('node:fs');
const { isNonterminal, notation, productionText, copyGrammar, parseGrammar } = require('./grammar_parser');
const { eliminate, factor } = require('./transform');
const { firstOf, computeSets } = require('./first_follow');
const { numberProductions, buildTable } = require('./table');
const driver = require('./driver');

function readLines(filename) {
  return fs.readFileSync(filename, 'ascii').slice(0, -1).split('\n');
}

function terminalOrder(values) {
  return [...values].sort((a, b) => a === b ? 0 : a === '$' ? 1 : b === '$' ? -1 : a < b ? -1 : 1);
}

function list(heading, values) {
  return heading + (values.length ? ' ' + values.join(' ') : '');
}

function sections(parts) {
  const result = [];
  parts.forEach((part, index) => {
    if (index > 0) result.push('');
    for (const line of part) result.push(line);
  });
  return result;
}

function prune(grammar, keep) {
  grammar.order = grammar.order.filter(name => keep.has(name));
  for (const name of grammar.rules.keys()) if (!keep.has(name)) grammar.rules.delete(name);
}

function reachable(grammar) {
  const queue = [grammar.start];
  const seen = new Set(queue);
  for (let head = 0; head < queue.length; head++) {
    for (const right of grammar.rules.get(queue[head])) {
      for (const symbol of right) {
        if (isNonterminal(symbol) && !seen.has(symbol)) {
          seen.add(symbol);
          queue.push(symbol);
        }
      }
    }
  }
  return seen;
}

function checkDeclarations(parsed) {
  if (!parsed.hasDeclarations) return [];
  const missing = terminalOrder([...parsed.wordLines.keys()].filter(name => !parsed.declared.has(name)));
  return missing.map(name => `undeclared terminal ${name} at line ${parsed.wordLines.get(name)}`);
}

function cleanGrammar(original) {
  const grammar = copyGrammar(original);
  const diagnostics = [];
  const undefinedNames = new Set();
  for (const right of [...grammar.rules.values()].flat()) {
    for (const symbol of right) if (isNonterminal(symbol) && !grammar.rules.has(symbol)) undefinedNames.add(symbol);
  }
  const undefinedOrder = [...undefinedNames].sort((a, b) => {
    const first = a.slice(1, -1);
    const second = b.slice(1, -1);
    return first === second ? 0 : first < second ? -1 : 1;
  });
  for (const name of undefinedOrder) diagnostics.push(`undefined nonterminal ${name}`);
  function removeAlternatives(names, reason) {
    for (const left of grammar.order) {
      grammar.rules.set(left, grammar.rules.get(left).filter(right => {
        const removed = right.find(symbol => names.has(symbol));
        if (removed === undefined) return true;
        diagnostics.push(`removed ${productionText(left, right)} (${reason} ${removed})`);
        return false;
      }));
    }
  }
  removeAlternatives(undefinedNames, 'undefined');
  const productive = new Set();
  let changed;
  do {
    changed = false;
    for (const name of grammar.order) {
      if (productive.has(name)) continue;
      if (grammar.rules.get(name).some(right => right.every(symbol => !isNonterminal(symbol) || productive.has(symbol)))) {
        productive.add(name);
        changed = true;
      }
    }
  } while (changed);
  const unproductive = new Set(grammar.order.filter(name => !productive.has(name)));
  for (const name of unproductive) diagnostics.push(`unproductive nonterminal ${name}`);
  prune(grammar, productive);
  removeAlternatives(unproductive, 'unproductive');
  const reached = reachable(grammar);
  for (const name of grammar.order) if (!reached.has(name)) diagnostics.push(`unreachable nonterminal ${name}`);
  prune(grammar, reached);
  return { grammar, diagnostics };
}

function leftRecursionReport(grammar) {
  const diagnostics = [];
  for (const start of grammar.order) {
    const queue = [start];
    const parents = new Map([[start, null]]);
    let found = null;
    for (let head = 0; head < queue.length && found === null; head++) {
      const current = queue[head];
      for (const right of grammar.rules.get(current)) {
        const next = right[0];
        if (next === start) {
          found = current;
          break;
        }
        if (next !== undefined && isNonterminal(next) && !parents.has(next)) {
          parents.set(next, current);
          queue.push(next);
        }
      }
    }
    if (found === null) continue;
    const path = [found];
    while (path.at(-1) !== start) path.push(parents.get(path.at(-1)));
    path.reverse();
    path.push(start);
    diagnostics.push('left recursion: ' + path.join(' -> '));
  }
  return diagnostics;
}

function finishGrammar(original) {
  const grammar = copyGrammar(original);
  const reached = reachable(grammar);
  const removed = grammar.order.filter(name => !reached.has(name));
  prune(grammar, reached);
  return { grammar, log: removed.map(name => `remove unreachable ${name}`),
    diagnostics: removed.map(name => `unreachable after transformation ${name}`) };
}

function betterPair(candidate, previous) {
  return previous === undefined || candidate[0] < previous[0] || candidate[0] === previous[0] && candidate[1] < previous[1];
}

function equalPair(first, second) {
  return first[0] === second[0] && first[1] === second[1];
}

function shortestSentences(grammar, productions) {
  const costs = new Map();
  function measure(right) {
    let length = 0;
    let height = 1;
    for (const symbol of right) {
      if (!isNonterminal(symbol)) length++;
      else {
        const cost = costs.get(symbol);
        if (cost === undefined) return null;
        length += cost[0];
        height = Math.max(height, cost[1] + 1);
      }
    }
    return [length, height];
  }
  let changed;
  do {
    changed = false;
    for (const left of grammar.order) {
      for (const right of grammar.rules.get(left)) {
        const candidate = measure(right);
        if (candidate !== null && betterPair(candidate, costs.get(left))) {
          costs.set(left, candidate);
          changed = true;
        }
      }
    }
  } while (changed);
  const words = new Map();
  function word(symbol) {
    if (!isNonterminal(symbol)) return [symbol];
    if (!words.has(symbol)) {
      const right = grammar.rules.get(symbol).find(alternative => equalPair(measure(alternative), costs.get(symbol)));
      words.set(symbol, expand(right));
    }
    return words.get(symbol);
  }
  function expand(symbols) {
    const tokens = [];
    for (const symbol of symbols) for (const token of word(symbol)) tokens.push(token);
    return tokens;
  }
  function length(symbols) {
    let total = 0;
    for (const symbol of symbols) total += isNonterminal(symbol) ? costs.get(symbol)[0] : 1;
    return total;
  }
  const contextCosts = new Map([[grammar.start, [0, 0]]]);
  function occurrenceCost(production, index) {
    const parent = contextCosts.get(production.left);
    if (parent === undefined) return null;
    return [parent[0] + length(production.right.slice(0, index)) + length(production.right.slice(index + 1)), parent[1] + 1];
  }
  do {
    changed = false;
    for (const production of productions) {
      for (let index = 0; index < production.right.length; index++) {
        const symbol = production.right[index];
        if (!isNonterminal(symbol) || symbol === grammar.start) continue;
        const candidate = occurrenceCost(production, index);
        if (candidate !== null && betterPair(candidate, contextCosts.get(symbol))) {
          contextCosts.set(symbol, candidate);
          changed = true;
        }
      }
    }
  } while (changed);
  const occurrences = new Map();
  for (const production of productions) {
    for (let index = 0; index < production.right.length; index++) {
      const symbol = production.right[index];
      if (!isNonterminal(symbol) || symbol === grammar.start || occurrences.has(symbol)) continue;
      if (equalPair(occurrenceCost(production, index), contextCosts.get(symbol))) occurrences.set(symbol, { production, index });
    }
  }
  const contexts = new Map([[grammar.start, { before: [], after: [] }]]);
  function context(symbol) {
    if (!contexts.has(symbol)) {
      const { production, index } = occurrences.get(symbol);
      const parent = context(production.left);
      contexts.set(symbol, { before: parent.before.concat(expand(production.right.slice(0, index))),
        after: expand(production.right.slice(index + 1)).concat(parent.after) });
    }
    return contexts.get(symbol);
  }
  for (const name of grammar.order) {
    word(name);
    context(name);
  }
  const example = production => {
    const outer = context(production.left);
    return outer.before.concat(expand(production.right), outer.after);
  };
  return { word, example };
}

function firstPath(number, terminal, table, sets) {
  const queue = [number];
  const parents = new Map([[number, null]]);
  for (let head = 0; head < queue.length; head++) {
    const current = queue[head];
    for (const symbol of table.productions[current - 1].right) {
      if (symbol === terminal) {
        const path = [];
        for (let node = current; node !== number; node = parents.get(node)) path.push(node);
        return path.reverse();
      }
      if (isNonterminal(symbol)) {
        for (const production of table.byLeft.get(symbol)) {
          if (parents.has(production.number)) continue;
          parents.set(production.number, current);
          queue.push(production.number);
        }
      }
      if (!isNonterminal(symbol) || !sets.nullable.get(symbol)) break;
    }
  }
  throw new Error('FIRST explanation has no derivation');
}

function followPath(start, terminal, grammar, table, sets) {
  const queue = [start];
  const paths = new Map([[start, []]]);
  for (let head = 0; head < queue.length; head++) {
    const current = queue[head];
    const path = paths.get(current);
    if (current === grammar.start && terminal === '$') return path;
    for (const production of table.productions) {
      for (let index = 0; index < production.right.length; index++) {
        if (production.right[index] !== current) continue;
        const suffix = firstOf(production.right.slice(index + 1), sets.nullable, sets.first);
        if (suffix.terminals.has(terminal)) return [...path, production.number];
        if (suffix.nullable && !paths.has(production.left)) {
          paths.set(production.left, [...path, production.number]);
          queue.push(production.left);
        }
      }
    }
  }
  throw new Error('FOLLOW explanation has no derivation');
}

function grammarSummary(grammar) {
  const productions = numberProductions(grammar);
  const terminals = new Set();
  for (const production of productions) for (const symbol of production.right) if (!isNonterminal(symbol)) terminals.add(symbol);
  const empty = productions.filter(production => production.right.length === 0).length;
  const unit = productions.filter(production => production.right.length === 1 && isNonterminal(production.right[0])).length;
  return `start=${grammar.start} nonterminals=${grammar.order.length} terminals=${terminals.size} productions=${productions.length} empty=${empty} unit=${unit}`;
}

function grammarListing(grammar, numbered = false) {
  const lines = [];
  const width = String(numberProductions(grammar).length).length;
  let number = 0;
  for (const left of grammar.order) {
    grammar.rules.get(left).forEach((right, index) => {
      number++;
      const prefix = numbered ? String(number).padStart(width) + '  ' : '';
      const rule = index === 0 ? left + ' -> ' : ' '.repeat(left.length) + ' | ';
      lines.push(prefix + rule + notation(right));
    });
  }
  return lines;
}

function grammarReport(cleaned, eliminated, factored, final, table) {
  const stage = (heading, result, numbered = false) => [heading, ...(result.log.length ? result.log : ['none']),
    grammarSummary(result.grammar), ...grammarListing(result.grammar, numbered)];
  const reference = ['== cross reference =='];
  for (const symbol of [...final.grammar.order, ...terminalOrder(table.known)]) {
    const label = isNonterminal(symbol) ? symbol : '"' + symbol + '"';
    const numbers = table.productions.filter(production => production.right.includes(symbol)).map(production => production.number);
    reference.push(numbers.length ? list(label + ' used in', numbers) : label + ' not used');
  }
  return sections([['== cleaned grammar ==', grammarSummary(cleaned), ...grammarListing(cleaned)],
    stage('== left recursion elimination ==', eliminated), stage('== left factoring ==', factored),
    stage('== final grammar ==', final, true), reference]);
}

function setsReport(grammar, sets, shortest) {
  const passes = sets.passes;
  const lines = [`passes: nullable=${passes.nullable} first=${passes.first} follow=${passes.follow}`, ''];
  for (const name of grammar.order) {
    lines.push(name, '  nullable: ' + (sets.nullable.get(name) ? 'yes' : 'no'),
      list('  first:', terminalOrder(sets.first.get(name))), list('  follow:', terminalOrder(sets.follow.get(name))),
      list('  shortest:', shortest.word(name)));
  }
  return lines;
}

function tableReport(grammar, table, sets, before) {
  const lines = ['== predict sets =='];
  for (const production of table.productions) {
    lines.push(`${production.number}: ${productionText(production.left, production.right)}`,
      list('  predict:', terminalOrder(production.reasons.keys())));
  }
  const rows = [['', ...table.columns]];
  for (const name of grammar.order) {
    rows.push([name, ...table.columns.map(terminal => {
      const entries = table.cells.get(name).get(terminal);
      return entries.length ? entries.map(production => production.number).join('/') : '.';
    })]);
  }
  const widths = rows[0].map((value, column) => Math.max(...rows.map(row => row[column].length)));
  lines.push('', '== parse table ==');
  for (const row of rows) lines.push(row[0].padEnd(widths[0]) + row.slice(1).map((value, index) => '  ' + value.padStart(widths[index + 1])).join(''));
  lines.push('', '== conflicts ==');
  if (table.conflicts.length === 0) lines.push('none');
  for (const conflict of table.conflicts) {
    lines.push(`conflict ${conflict.left} on ${conflict.terminal}: ${conflict.kind}, chosen ${conflict.chosen.number}`);
    for (const production of conflict.entries) {
      const reason = production.reasons.get(conflict.terminal);
      const path = reason === 'FIRST' ? firstPath(production.number, conflict.terminal, table, sets)
        : followPath(conflict.left, conflict.terminal, grammar, table, sets);
      const explanation = reason + (path.length ? ' via ' + path.join(' ') : '');
      lines.push(`  ${production.number}: ${productionText(production.left, production.right)} (${explanation})`);
    }
  }
  lines.push('LL(1): ' + (table.conflicts.length ? 'no' : 'yes'), `conflicts before transformation: ${before}`);
  return lines;
}

function languageModel(grammar, table, sets) {
  const productions = [{ left: null, right: [grammar.start] }, ...table.productions];
  const byLeft = new Map(grammar.order.map(name => [name, []]));
  for (let number = 1; number < productions.length; number++) byLeft.get(productions[number].left).push(number);
  return { productions, byLeft, nullable: sets.nullable, terminals: table.known };
}

function inLanguage(tokens, model) {
  if (tokens.some(token => !model.terminals.has(token))) return false;
  const charts = Array.from({ length: tokens.length + 1 }, () => ({ items: [], seen: new Set(), waiting: new Map() }));
  function add(position, production, dot, origin) {
    const chart = charts[position];
    const key = `${production}/${dot}/${origin}`;
    if (chart.seen.has(key)) return;
    chart.seen.add(key);
    chart.items.push({ production, dot, origin });
  }
  add(0, 0, 0, 0);
  for (let position = 0; position < charts.length; position++) {
    const chart = charts[position];
    for (let head = 0; head < chart.items.length; head++) {
      const item = chart.items[head];
      const production = model.productions[item.production];
      if (item.dot === production.right.length) {
        for (const parent of charts[item.origin].waiting.get(production.left) ?? []) {
          add(position, parent.production, parent.dot + 1, parent.origin);
        }
        continue;
      }
      const symbol = production.right[item.dot];
      if (isNonterminal(symbol)) {
        if (!chart.waiting.has(symbol)) chart.waiting.set(symbol, []);
        chart.waiting.get(symbol).push(item);
        for (const number of model.byLeft.get(symbol)) add(position, number, 0, position);
        // A nullable completion may have been processed before this waiting item.
        if (model.nullable.get(symbol)) add(position, item.production, item.dot + 1, item.origin);
      } else if (position < tokens.length && tokens[position] === symbol) {
        add(position + 1, item.production, item.dot + 1, item.origin);
      }
    }
  }
  return charts[tokens.length].seen.has('0/1/0');
}

function compactTree(node) {
  const children = [];
  for (const child of node.children) {
    if (child.symbol === '%empty') continue;
    const compacted = compactTree(child);
    if (!compacted.mark && isNonterminal(compacted.symbol) && compacted.children.length === 0) continue;
    if (!compacted.mark && isNonterminal(compacted.symbol) && compacted.symbol.includes("'")) {
      for (const descendant of compacted.children) children.push(descendant);
    } else children.push(compacted);
  }
  if (children.length === 1 && !node.mark) return children[0];
  return { symbol: node.symbol, mark: node.mark, children };
}

function drawTree(root) {
  const label = node => node.symbol + (node.mark ? ` (${node.mark})` : '');
  const lines = [label(root)];
  const pending = [];
  function pushChildren(node, prefix) {
    for (let index = node.children.length - 1; index >= 0; index--) pending.push({ node: node.children[index], prefix, last: index === node.children.length - 1 });
  }
  pushChildren(root, '');
  while (pending.length) {
    const { node, prefix, last } = pending.pop();
    lines.push(prefix + (last ? '`-- ' : '|-- ') + label(node));
    pushChildren(node, prefix + (last ? '    ' : '|   '));
  }
  return lines;
}

function errorText(step, table) {
  const token = step.token;
  const unexpected = token.value === '$' ? 'end of input' : `"${token.value}" at token ${token.position}`;
  const quote = terminal => terminal === '$' ? '$' : '"' + terminal + '"';
  const expected = isNonterminal(step.top)
    ? table.columns.filter(terminal => table.choices.get(step.top).has(terminal)).map(quote).join(' ')
    : quote(step.top);
  const recovery = step.action === 'skip' ? `skipped "${token.value}"`
    : step.action === 'pop' ? `popped ${step.top}` : `inserted "${step.top}"`;
  return `step ${step.number}: unexpected ${unexpected}; expected ${expected}; ${recovery}`;
}

function actionText(step) {
  if (step.action === 'accept') return 'accept';
  if (step.action === 'match') return 'match ' + step.token.value;
  if (step.action === 'predict') return `predict ${step.production.number}: ${productionText(step.production.left, step.production.right)}`;
  return 'error: ' + step.action + ' ' + (step.action === 'skip' ? step.token.value : step.top);
}

function traceTable(trace) {
  const rows = [['step', 'stack', 'input', 'action'], ...trace.map(step =>
    [String(step.number), notation(step.stack), notation(step.input), actionText(step)])];
  const widths = [0, 1, 2].map(column => Math.max(...rows.map(row => row[column].length)));
  return rows.map(row => row.slice(0, 3).map((value, index) => value.padEnd(widths[index])).join('  ') + '  ' + row[3]);
}

function derivation(grammar, table, leftParse) {
  const symbols = [grammar.start];
  const lines = ['  ' + grammar.start];
  for (const number of leftParse) {
    const production = table.productions[number - 1];
    const index = symbols.findIndex(isNonterminal);
    symbols.splice(index, 1, ...production.right);
    lines.push('  => ' + notation(symbols));
  }
  return lines;
}

function parseReport(inputs, grammar, table, sets, shortest, membership) {
  const lines = [];
  const used = new Set();
  const recovery = { unknown: 0, skip: 0, pop: 0, missing: 0 };
  const mismatches = [];
  let accepted = 0;
  let members = 0;
  inputs.forEach((tokens, index) => {
    const errors = [];
    const sequence = [];
    tokens.forEach((value, position) => {
      if (table.known.has(value)) sequence.push({ value, position: position + 1 });
      else {
        errors.push(`unknown "${value}" at token ${position + 1}; removed`);
        recovery.unknown++;
      }
    });
    sequence.push({ value: '$', position: tokens.length + 1 });
    const result = driver.parse(grammar, table, sets, sequence);
    for (const step of result.trace) if (['skip', 'pop', 'missing'].includes(step.action)) errors.push(errorText(step, table));
    for (const name of ['skip', 'pop', 'missing']) recovery[name] += result.counts[name];
    for (const number of result.leftParse) used.add(number);
    const success = errors.length === 0;
    const member = inLanguage(tokens, membership);
    if (success) accepted++;
    if (member) members++;
    if (success !== member) mismatches.push(index + 1);
    lines.push(`== input ${index + 1} ==`, list('tokens:', tokens), ...traceTable(result.trace), list('left parse:', result.leftParse),
      `stats: steps=${result.trace.length} predicts=${result.leftParse.length} matches=${result.matches} max_stack=${result.maximumStack}`);
    if (errors.length) lines.push('errors:', ...errors.map(error => '  ' + error));
    lines.push(success ? 'result: accepted' : `result: rejected (errors: ${errors.length})`, 'language: ' + (member ? 'yes' : 'no'));
    if (success) lines.push('derivation:', ...derivation(grammar, table, result.leftParse));
    lines.push('tree:', ...drawTree(result.root), 'compact tree:', ...drawTree(compactTree(result.root)), '');
  });
  const unused = table.productions.filter(production => !used.has(production.number));
  lines.push('== summary ==', `inputs=${inputs.length} accepted=${accepted} rejected=${inputs.length - accepted} in_language=${members}`,
    list('mismatches:', mismatches), `recovery: unknown=${recovery.unknown} skip=${recovery.skip} pop=${recovery.pop} missing=${recovery.missing}`,
    `coverage: ${used.size} of ${table.productions.length} productions used`, list('unused:', unused.map(production => production.number)));
  for (const production of unused) {
    const tokens = shortest.example(production);
    const sequence = tokens.map((value, position) => ({ value, position: position + 1 }));
    sequence.push({ value: '$', position: tokens.length + 1 });
    const result = driver.parse(grammar, table, sets, sequence);
    const errors = result.counts.skip + result.counts.pop + result.counts.missing;
    lines.push(`  ${production.number}: ${productionText(production.left, production.right)}`, list('    example:', tokens),
      errors ? `    result: rejected (errors: ${errors})` : '    result: accepted',
      '    used: ' + (result.leftParse.includes(production.number) ? 'yes' : 'no'));
  }
  return lines;
}

function main() {
  const parsed = parseGrammar(readLines('input/grammar.bnf'));
  const inputs = readLines('input/inputs.txt').map(line => line === '' ? [] : line.split(' '));
  const declarationDiagnostics = checkDeclarations(parsed);
  const cleaned = cleanGrammar(parsed.grammar);
  const recursionDiagnostics = leftRecursionReport(cleaned.grammar);
  const originalSets = computeSets(cleaned.grammar);
  const originalTable = buildTable(cleaned.grammar, originalSets);
  const eliminated = eliminate(cleaned.grammar);
  const factored = factor(eliminated.grammar);
  const final = finishGrammar(factored.grammar);
  const sets = computeSets(final.grammar);
  const table = buildTable(final.grammar, sets);
  const shortest = shortestSentences(final.grammar, table.productions);
  const membership = languageModel(cleaned.grammar, originalTable, originalSets);
  const grammarLines = grammarReport(cleaned.grammar, eliminated, factored, final, table);
  const setLines = setsReport(final.grammar, sets, shortest);
  const tableLines = tableReport(final.grammar, table, sets, originalTable.conflicts.length);
  const parseLines = parseReport(inputs, final.grammar, table, sets, shortest, membership);
  const unused = parsed.hasDeclarations ? terminalOrder([...parsed.declared].filter(name => !table.known.has(name))) : [];
  const diagnostics = [...parsed.diagnostics, ...declarationDiagnostics, ...cleaned.diagnostics, ...recursionDiagnostics,
    ...final.diagnostics, ...unused.map(name => 'unused token ' + name),
    table.conflicts.length ? `result: not LL(1) (conflicts: ${table.conflicts.length})` : 'result: LL(1)'];
  fs.mkdirSync('output', { recursive: true });
  for (const [filename, lines] of [['grammar.txt', grammarLines], ['sets.txt', setLines], ['table.txt', tableLines],
    ['parses.txt', parseLines], ['diagnostics.txt', diagnostics]]) {
    fs.writeFileSync('output/' + filename, lines.join('\n') + '\n', 'ascii');
  }
}

if (require.main === module) main();
