import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import {
  isNonterminal,
  notation,
  productionText,
  copyGrammar,
  parseGrammar,
  type Grammar,
} from './grammar_parser.ts';
import { eliminate, factor } from './transform.ts';
import { firstOf, computeSets, type GrammarSets } from './first_follow.ts';
import { numberProductions, buildTable, type Production, type ParseTable } from './table.ts';
import { parse, type TreeNode, type Step, type InputToken } from './driver.ts';

const readLines = (filename: string): string[] =>
  readFileSync(filename, 'ascii').slice(0, -1).split('\n');
const terminalOrder = (values: Iterable<string>): string[] =>
  [...values].sort((a, b) => (a === b ? 0 : a === '$' ? 1 : b === '$' ? -1 : a < b ? -1 : 1));
const list = (heading: string, values: readonly (string | number)[]): string =>
  heading + (values.length ? ' ' + values.join(' ') : '');
const sections = (parts: string[][]): string[] =>
  parts.flatMap((part, i) => (i ? ['', ...part] : part));
function prune(grammar: Grammar, keep: Set<string>): void {
  grammar.order = grammar.order.filter((name) => keep.has(name));
  for (const name of grammar.rules.keys()) if (!keep.has(name)) grammar.rules.delete(name);
}
function reachable(grammar: Grammar): Set<string> {
  const queue = [grammar.start];
  const seen = new Set(queue);
  for (let head = 0; head < queue.length; head++) {
    for (const right of grammar.rules.get(queue[head])!) {
      for (const s of right) {
        if (isNonterminal(s) && !seen.has(s)) {
          seen.add(s);
          queue.push(s);
        }
      }
    }
  }
  return seen;
}
function checkDeclarations(parsed: ReturnType<typeof parseGrammar>): string[] {
  return !parsed.hasDeclarations
    ? []
    : terminalOrder([...parsed.wordLines.keys()].filter((name) => !parsed.declared.has(name))).map(
        (name) => `undeclared terminal ${name} at line ${parsed.wordLines.get(name)}`,
      );
}
function cleanGrammar(original: Grammar) {
  const grammar = copyGrammar(original);
  const diagnostics: string[] = [];
  const undefinedNames = new Set<string>();
  for (const right of [...grammar.rules.values()].flat()) {
    for (const s of right) if (isNonterminal(s) && !grammar.rules.has(s)) undefinedNames.add(s);
  }
  const undefinedOrder = [...undefinedNames].sort((a, b) =>
    a.slice(1, -1) < b.slice(1, -1) ? -1 : a.slice(1, -1) > b.slice(1, -1) ? 1 : 0,
  );
  for (const name of undefinedOrder) diagnostics.push(`undefined nonterminal ${name}`);
  function removeAlternatives(names: Set<string>, reason: string): void {
    for (const left of grammar.order) {
      grammar.rules.set(
        left,
        grammar.rules.get(left)!.filter((right) => {
          const removed = right.find((s) => names.has(s));
          if (removed === undefined) return true;
          diagnostics.push(`removed ${productionText(left, right)} (${reason} ${removed})`);
          return false;
        }),
      );
    }
  }
  removeAlternatives(undefinedNames, 'undefined');
  const productive = new Set<string>();
  let changed: boolean;
  do {
    changed = false;
    for (const name of grammar.order) {
      if (
        !productive.has(name) &&
        grammar.rules
          .get(name)!
          .some((right) => right.every((s) => !isNonterminal(s) || productive.has(s)))
      ) {
        productive.add(name);
        changed = true;
      }
    }
  } while (changed);
  const unproductive = new Set(grammar.order.filter((name) => !productive.has(name)));
  for (const name of unproductive) diagnostics.push(`unproductive nonterminal ${name}`);
  prune(grammar, productive);
  removeAlternatives(unproductive, 'unproductive');
  const reached = reachable(grammar);
  for (const name of grammar.order) {
    if (!reached.has(name)) diagnostics.push(`unreachable nonterminal ${name}`);
  }
  prune(grammar, reached);
  return { grammar, diagnostics };
}
function leftRecursionReport(grammar: Grammar): string[] {
  const diagnostics: string[] = [];
  for (const start of grammar.order) {
    const queue = [start];
    const parents = new Map<string, string | null>([[start, null]]);
    let found: string | null = null;
    for (let head = 0; head < queue.length && found === null; head++) {
      for (const right of grammar.rules.get(queue[head])!) {
        const next = right[0];
        if (next === start) {
          found = queue[head];
          break;
        }
        if (next !== undefined && isNonterminal(next) && !parents.has(next)) {
          parents.set(next, queue[head]);
          queue.push(next);
        }
      }
    }
    if (found === null) continue;
    const path = [found];
    while (path[path.length - 1] !== start) path.push(parents.get(path[path.length - 1])!);
    path.reverse();
    path.push(start);
    diagnostics.push('left recursion: ' + path.join(' -> '));
  }
  return diagnostics;
}
function finishGrammar(original: Grammar) {
  const grammar = copyGrammar(original);
  const reached = reachable(grammar);
  const removed = grammar.order.filter((name) => !reached.has(name));
  prune(grammar, reached);
  return {
    grammar,
    log: removed.map((name) => `remove unreachable ${name}`),
    diagnostics: removed.map((name) => `unreachable after transformation ${name}`),
  };
}
type Cost = readonly [number, number];
const betterPair = (a: Cost, b: Cost | undefined): boolean =>
  b === undefined || a[0] < b[0] || (a[0] === b[0] && a[1] < b[1]);
const equalPair = (a: Cost | null, b: Cost | undefined): boolean =>
  a !== null && b !== undefined && a[0] === b[0] && a[1] === b[1];
function shortestSentences(grammar: Grammar, productions: Production[]) {
  const costs = new Map<string, Cost>();
  function measure(right: string[]): Cost | null {
    let length = 0;
    let height = 1;
    for (const s of right) {
      if (!isNonterminal(s)) length++;
      else {
        const cost = costs.get(s);
        if (cost === undefined) return null;
        length += cost[0];
        height = Math.max(height, cost[1] + 1);
      }
    }
    return [length, height];
  }
  let changed: boolean;
  do {
    changed = false;
    for (const left of grammar.order) {
      for (const right of grammar.rules.get(left)!) {
        const candidate = measure(right);
        if (candidate !== null && betterPair(candidate, costs.get(left))) {
          costs.set(left, candidate);
          changed = true;
        }
      }
    }
  } while (changed);
  const words = new Map<string, string[]>();
  function word(symbol: string): string[] {
    if (!isNonterminal(symbol)) return [symbol];
    if (!words.has(symbol)) {
      const right = grammar.rules
        .get(symbol)!
        .find((r) => equalPair(measure(r), costs.get(symbol)))!;
      words.set(symbol, expand(right));
    }
    return words.get(symbol)!;
  }
  function expand(symbols: string[]): string[] {
    return symbols.flatMap(word);
  }
  function length(symbols: string[]): number {
    let total = 0;
    for (const s of symbols) total += isNonterminal(s) ? costs.get(s)![0] : 1;
    return total;
  }
  const contextCosts = new Map<string, Cost>([[grammar.start, [0, 0]]]);
  function occurrenceCost(p: Production, i: number): Cost | null {
    const parent = contextCosts.get(p.left);
    return parent === undefined
      ? null
      : [parent[0] + length(p.right.slice(0, i)) + length(p.right.slice(i + 1)), parent[1] + 1];
  }
  do {
    changed = false;
    for (const p of productions) {
      for (let i = 0; i < p.right.length; i++) {
        const s = p.right[i];
        if (!isNonterminal(s) || s === grammar.start) continue;
        const candidate = occurrenceCost(p, i);
        if (candidate !== null && betterPair(candidate, contextCosts.get(s))) {
          contextCosts.set(s, candidate);
          changed = true;
        }
      }
    }
  } while (changed);
  const occurrences = new Map<string, { production: Production; index: number }>();
  for (const p of productions) {
    for (let i = 0; i < p.right.length; i++) {
      const s = p.right[i];
      if (!isNonterminal(s) || s === grammar.start || occurrences.has(s)) continue;
      if (equalPair(occurrenceCost(p, i), contextCosts.get(s))) {
        occurrences.set(s, { production: p, index: i });
      }
    }
  }
  interface Context {
    before: string[];
    after: string[];
  }
  const contexts = new Map<string, Context>([[grammar.start, { before: [], after: [] }]]);
  function context(symbol: string): Context {
    if (!contexts.has(symbol)) {
      const { production: p, index: i } = occurrences.get(symbol)!;
      const parent = context(p.left);
      contexts.set(symbol, {
        before: [...parent.before, ...expand(p.right.slice(0, i))],
        after: [...expand(p.right.slice(i + 1)), ...parent.after],
      });
    }
    return contexts.get(symbol)!;
  }
  for (const name of grammar.order) {
    word(name);
    context(name);
  }
  const example = (p: Production): string[] => {
    const outer = context(p.left);
    return [...outer.before, ...expand(p.right), ...outer.after];
  };
  return { word, example };
}
type Shortest = ReturnType<typeof shortestSentences>;
function firstPath(
  number: number,
  terminal: string,
  table: ParseTable,
  sets: GrammarSets,
): number[] {
  const queue = [number];
  const parents = new Map<number, number | null>([[number, null]]);
  for (let head = 0; head < queue.length; head++) {
    const current = queue[head];
    for (const s of table.productions[current - 1].right) {
      if (s === terminal) {
        const path: number[] = [];
        for (let node = current; node !== number; node = parents.get(node)!) path.push(node);
        return path.reverse();
      }
      if (isNonterminal(s)) {
        for (const p of table.byLeft.get(s)!) {
          if (!parents.has(p.number)) {
            parents.set(p.number, current);
            queue.push(p.number);
          }
        }
      }
      if (!isNonterminal(s) || !sets.nullable.get(s)) break;
    }
  }
  throw new Error('FIRST explanation has no derivation');
}
function followPath(
  start: string,
  terminal: string,
  grammar: Grammar,
  table: ParseTable,
  sets: GrammarSets,
): number[] {
  const queue = [start];
  const paths = new Map<string, number[]>([[start, []]]);
  for (let head = 0; head < queue.length; head++) {
    const current = queue[head];
    const path = paths.get(current)!;
    if (current === grammar.start && terminal === '$') return path;
    for (const p of table.productions) {
      for (let i = 0; i < p.right.length; i++) {
        if (p.right[i] !== current) continue;
        const suffix = firstOf(p.right.slice(i + 1), sets.nullable, sets.first);
        if (suffix.terminals.has(terminal)) return [...path, p.number];
        if (suffix.nullable && !paths.has(p.left)) {
          paths.set(p.left, [...path, p.number]);
          queue.push(p.left);
        }
      }
    }
  }
  throw new Error('FOLLOW explanation has no derivation');
}
interface EarleyItem {
  production: number;
  dot: number;
  origin: number;
}
interface Chart {
  items: EarleyItem[];
  seen: Set<string>;
  waiting: Map<string, EarleyItem[]>;
}
function languageModel(grammar: Grammar, table: ParseTable, sets: GrammarSets) {
  const productions: { left: string; right: string[] }[] = [
    { left: '', right: [grammar.start] },
    ...table.productions,
  ];
  const byLeft = new Map<string, number[]>(grammar.order.map((name) => [name, []]));
  for (let n = 1; n < productions.length; n++) byLeft.get(productions[n].left)!.push(n);
  return { productions, byLeft, nullable: sets.nullable, terminals: table.known };
}
function inLanguage(tokens: string[], model: ReturnType<typeof languageModel>): boolean {
  if (tokens.some((t) => !model.terminals.has(t))) return false;
  const charts: Chart[] = Array.from({ length: tokens.length + 1 }, () => ({
    items: [],
    seen: new Set(),
    waiting: new Map(),
  }));
  function add(position: number, production: number, dot: number, origin: number): void {
    const c = charts[position];
    const key = `${production}/${dot}/${origin}`;
    if (c.seen.has(key)) return;
    c.seen.add(key);
    c.items.push({ production, dot, origin });
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
        chart.waiting.get(symbol)!.push(item);
        for (const number of model.byLeft.get(symbol)!) add(position, number, 0, position);
        if (model.nullable.get(symbol)) add(position, item.production, item.dot + 1, item.origin);
      } else if (position < tokens.length && tokens[position] === symbol) {
        add(position + 1, item.production, item.dot + 1, item.origin);
      }
    }
  }
  return charts[tokens.length].seen.has('0/1/0');
}
function compactTree(node: TreeNode): TreeNode {
  const children: TreeNode[] = [];
  for (const child of node.children) {
    if (child.symbol === '%empty') continue;
    const c = compactTree(child);
    if (!c.mark && isNonterminal(c.symbol) && !c.children.length) continue;
    if (!c.mark && isNonterminal(c.symbol) && c.symbol.includes("'")) children.push(...c.children);
    else children.push(c);
  }
  return children.length === 1 && !node.mark
    ? children[0]
    : { symbol: node.symbol, mark: node.mark, children };
}
function drawTree(root: TreeNode): string[] {
  const label = (n: TreeNode) => n.symbol + (n.mark ? ` (${n.mark})` : '');
  const lines = [label(root)];
  const pending: { node: TreeNode; prefix: string; last: boolean }[] = [];
  function pushChildren(node: TreeNode, prefix: string): void {
    for (let i = node.children.length - 1; i >= 0; i--) {
      pending.push({ node: node.children[i], prefix, last: i === node.children.length - 1 });
    }
  }
  pushChildren(root, '');
  while (pending.length) {
    const { node, prefix, last } = pending.pop()!;
    lines.push(prefix + (last ? '`-- ' : '|-- ') + label(node));
    pushChildren(node, prefix + (last ? '    ' : '|   '));
  }
  return lines;
}
function errorText(step: Step, table: ParseTable): string {
  const token = step.token;
  const unexpected =
    token.value === '$' ? 'end of input' : `"${token.value}" at token ${token.position}`;
  const quote = (t: string) => (t === '$' ? '$' : '"' + t + '"');
  const expected = isNonterminal(step.top)
    ? table.columns
        .filter((t) => table.choices.get(step.top)!.has(t))
        .map(quote)
        .join(' ')
    : quote(step.top);
  const recovery =
    step.action === 'skip'
      ? `skipped "${token.value}"`
      : step.action === 'pop'
        ? `popped ${step.top}`
        : `inserted "${step.top}"`;
  return `step ${step.number}: unexpected ${unexpected}; expected ${expected}; ${recovery}`;
}
function actionText(step: Step): string {
  if (step.action === 'accept') return 'accept';
  if (step.action === 'match') return 'match ' + step.token.value;
  if (step.action === 'predict') {
    return `predict ${step.production!.number}: ${productionText(step.production!.left, step.production!.right)}`;
  }
  return 'error: ' + step.action + ' ' + (step.action === 'skip' ? step.token.value : step.top);
}
function traceTable(trace: Step[]): string[] {
  const rows = [
    ['step', 'stack', 'input', 'action'],
    ...trace.map((s) => [String(s.number), notation(s.stack), notation(s.input), actionText(s)]),
  ];
  const widths = [0, 1, 2].map((i) => Math.max(...rows.map((row) => row[i].length)));
  return rows.map(
    (row) =>
      row
        .slice(0, 3)
        .map((v, i) => v.padEnd(widths[i]))
        .join('  ') +
      '  ' +
      row[3],
  );
}
function derivation(grammar: Grammar, table: ParseTable, leftParse: number[]): string[] {
  const symbols = [grammar.start];
  const lines = ['  ' + grammar.start];
  for (const number of leftParse) {
    const p = table.productions[number - 1];
    const i = symbols.findIndex(isNonterminal);
    symbols.splice(i, 1, ...p.right);
    lines.push('  => ' + notation(symbols));
  }
  return lines;
}
function grammarSummary(grammar: Grammar): string {
  const p = numberProductions(grammar);
  const terminals = new Set(p.flatMap((p) => p.right).filter((s) => !isNonterminal(s)));
  return `start=${grammar.start} nonterminals=${grammar.order.length} terminals=${terminals.size} productions=${p.length} empty=${p.filter((p) => !p.right.length).length} unit=${p.filter((p) => p.right.length === 1 && isNonterminal(p.right[0])).length}`;
}
function grammarListing(grammar: Grammar, numbered = false): string[] {
  const lines: string[] = [];
  const width = String(numberProductions(grammar).length).length;
  let number = 0;
  for (const left of grammar.order) {
    grammar.rules.get(left)!.forEach((right, i) => {
      number++;
      const prefix = numbered ? String(number).padStart(width) + '  ' : '';
      const rule = i === 0 ? left + ' -> ' : ' '.repeat(left.length) + ' | ';
      lines.push(prefix + rule + notation(right));
    });
  }
  return lines;
}
interface Stage {
  grammar: Grammar;
  log: string[];
}
function grammarReport(
  cleaned: Grammar,
  eliminated: Stage,
  factored: Stage,
  final: Stage,
  table: ParseTable,
): string[] {
  const stage = (heading: string, result: Stage, numbered = false) => [
    heading,
    ...(result.log.length ? result.log : ['none']),
    grammarSummary(result.grammar),
    ...grammarListing(result.grammar, numbered),
  ];
  const reference = ['== cross reference =='];
  for (const s of [...final.grammar.order, ...terminalOrder(table.known)]) {
    const label = isNonterminal(s) ? s : '"' + s + '"';
    const numbers = table.productions.filter((p) => p.right.includes(s)).map((p) => p.number);
    reference.push(numbers.length ? list(label + ' used in', numbers) : label + ' not used');
  }
  return sections([
    ['== cleaned grammar ==', grammarSummary(cleaned), ...grammarListing(cleaned)],
    stage('== left recursion elimination ==', eliminated),
    stage('== left factoring ==', factored),
    stage('== final grammar ==', final, true),
    reference,
  ]);
}
function setsReport(grammar: Grammar, sets: GrammarSets, shortest: Shortest): string[] {
  const p = sets.passes;
  const lines = [`passes: nullable=${p.nullable} first=${p.first} follow=${p.follow}`, ''];
  for (const name of grammar.order) {
    lines.push(
      name,
      '  nullable: ' + (sets.nullable.get(name) ? 'yes' : 'no'),
      list('  first:', terminalOrder(sets.first.get(name)!)),
      list('  follow:', terminalOrder(sets.follow.get(name)!)),
      list('  shortest:', shortest.word(name)),
    );
  }
  return lines;
}
function tableReport(
  grammar: Grammar,
  table: ParseTable,
  sets: GrammarSets,
  before: number,
): string[] {
  const lines = ['== predict sets =='];
  for (const p of table.productions) {
    lines.push(
      `${p.number}: ${productionText(p.left, p.right)}`,
      list('  predict:', terminalOrder(p.reasons.keys())),
    );
  }
  const rows = [['', ...table.columns]];
  for (const name of grammar.order) {
    rows.push([
      name,
      ...table.columns.map((t) => {
        const entries = table.cells.get(name)!.get(t)!;
        return entries.length ? entries.map((p) => p.number).join('/') : '.';
      }),
    ]);
  }
  const widths = rows[0].map((_, i) => Math.max(...rows.map((row) => row[i].length)));
  lines.push('', '== parse table ==');
  for (const row of rows) {
    lines.push(
      row[0].padEnd(widths[0]) +
        row
          .slice(1)
          .map((v, i) => '  ' + v.padStart(widths[i + 1]))
          .join(''),
    );
  }
  lines.push('', '== conflicts ==');
  if (!table.conflicts.length) lines.push('none');
  for (const c of table.conflicts) {
    lines.push(`conflict ${c.left} on ${c.terminal}: ${c.kind}, chosen ${c.chosen.number}`);
    for (const p of c.entries) {
      const reason = p.reasons.get(c.terminal)!;
      const path =
        reason === 'FIRST'
          ? firstPath(p.number, c.terminal, table, sets)
          : followPath(c.left, c.terminal, grammar, table, sets);
      lines.push(
        `  ${p.number}: ${productionText(p.left, p.right)} (${reason}${path.length ? ' via ' + path.join(' ') : ''})`,
      );
    }
  }
  lines.push(
    'LL(1): ' + (table.conflicts.length ? 'no' : 'yes'),
    `conflicts before transformation: ${before}`,
  );
  return lines;
}
function parseReport(
  inputs: string[][],
  grammar: Grammar,
  table: ParseTable,
  sets: GrammarSets,
  shortest: Shortest,
  membership: ReturnType<typeof languageModel>,
): string[] {
  const lines: string[] = [];
  const used = new Set<number>();
  const recovery = { unknown: 0, skip: 0, pop: 0, missing: 0 };
  const mismatches: number[] = [];
  let accepted = 0;
  let members = 0;
  inputs.forEach((tokens, index) => {
    const errors: string[] = [];
    const sequence: InputToken[] = [];
    tokens.forEach((value, i) => {
      if (table.known.has(value)) sequence.push({ value, position: i + 1 });
      else {
        errors.push(`unknown "${value}" at token ${i + 1}; removed`);
        recovery.unknown++;
      }
    });
    sequence.push({ value: '$', position: tokens.length + 1 });
    const result = parse(grammar, table, sets, sequence);
    for (const step of result.trace) {
      if (step.action === 'skip' || step.action === 'pop' || step.action === 'missing') {
        errors.push(errorText(step, table));
      }
    }
    for (const name of ['skip', 'pop', 'missing'] as const) recovery[name] += result.counts[name];
    for (const number of result.leftParse) used.add(number);
    const success = errors.length === 0;
    const member = inLanguage(tokens, membership);
    if (success) accepted++;
    if (member) members++;
    if (success !== member) mismatches.push(index + 1);
    lines.push(
      `== input ${index + 1} ==`,
      list('tokens:', tokens),
      ...traceTable(result.trace),
      list('left parse:', result.leftParse),
      `stats: steps=${result.trace.length} predicts=${result.leftParse.length} matches=${result.matches} max_stack=${result.maximumStack}`,
    );
    if (errors.length) lines.push('errors:', ...errors.map((e) => '  ' + e));
    lines.push(
      success ? 'result: accepted' : `result: rejected (errors: ${errors.length})`,
      'language: ' + (member ? 'yes' : 'no'),
    );
    if (success) lines.push('derivation:', ...derivation(grammar, table, result.leftParse));
    lines.push(
      'tree:',
      ...drawTree(result.root),
      'compact tree:',
      ...drawTree(compactTree(result.root)),
      '',
    );
  });
  const unused = table.productions.filter((p) => !used.has(p.number));
  lines.push(
    '== summary ==',
    `inputs=${inputs.length} accepted=${accepted} rejected=${inputs.length - accepted} in_language=${members}`,
    list('mismatches:', mismatches),
    `recovery: unknown=${recovery.unknown} skip=${recovery.skip} pop=${recovery.pop} missing=${recovery.missing}`,
    `coverage: ${used.size} of ${table.productions.length} productions used`,
    list(
      'unused:',
      unused.map((p) => p.number),
    ),
  );
  for (const p of unused) {
    const tokens = shortest.example(p);
    const sequence = tokens.map((value, i) => ({ value, position: i + 1 }));
    sequence.push({ value: '$', position: tokens.length + 1 });
    const result = parse(grammar, table, sets, sequence);
    const errors = result.counts.skip + result.counts.pop + result.counts.missing;
    lines.push(
      `  ${p.number}: ${productionText(p.left, p.right)}`,
      list('    example:', tokens),
      errors ? `    result: rejected (errors: ${errors})` : '    result: accepted',
      '    used: ' + (result.leftParse.includes(p.number) ? 'yes' : 'no'),
    );
  }
  return lines;
}
function main(): void {
  const parsed = parseGrammar(readLines('input/grammar.bnf'));
  const inputs = readLines('input/inputs.txt').map((line) => (line === '' ? [] : line.split(' ')));
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
  const unused = parsed.hasDeclarations
    ? terminalOrder([...parsed.declared].filter((name) => !table.known.has(name)))
    : [];
  const diagnostics = [
    ...parsed.diagnostics,
    ...declarationDiagnostics,
    ...cleaned.diagnostics,
    ...recursionDiagnostics,
    ...final.diagnostics,
    ...unused.map((name) => 'unused token ' + name),
    table.conflicts.length
      ? `result: not LL(1) (conflicts: ${table.conflicts.length})`
      : 'result: LL(1)',
  ];
  const outputs: [string, string[]][] = [
    ['grammar.txt', grammarReport(cleaned.grammar, eliminated, factored, final, table)],
    ['sets.txt', setsReport(final.grammar, sets, shortest)],
    ['table.txt', tableReport(final.grammar, table, sets, originalTable.conflicts.length)],
    ['parses.txt', parseReport(inputs, final.grammar, table, sets, shortest, membership)],
    ['diagnostics.txt', diagnostics],
  ];
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of outputs) {
    writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
  }
}
main();
