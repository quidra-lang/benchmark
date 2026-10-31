import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { FormulaError, COMMAND_NAMES, tokenize } from './lexer.ts';
import { Parser } from './parser.ts';
import { Box, LARGE_GLYPHS, atomDisplay, delimiterGlyph, center } from './boxes.ts';
import { spacing, rowBox } from './layout.ts';
import { entries, draw, boxLines } from './canvas.ts';
import type {
  Formula, FormulaNode, FormulaToken, Params, Glyph, Placement, BrokenLine, LaidOutFormula,
} from './types.ts';

type Style = 'normal' | 'script';

function inputLines(name: string): string[] {
  return readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
}

function parseFormulas(lines: string[]): Formula[] {
  return lines.map((source, index) => {
    const formula: Formula = { number: index + 1, source, warnings: [],
      elements: [], tag: null, label: null, tokens: [], tagString: null, error: null };
    try {
      formula.tokens = tokenize(source);
      Object.assign(formula, new Parser(formula.tokens).parse());
    } catch (error) {
      if (!(error instanceof FormulaError)) throw error;
      formula.error = { column: error.column, message: error.message };
    }
    return formula;
  });
}

function equationReferences(formulas: Formula[]): Map<string,string> {
  const references = new Map<string,string>();
  let counter = 0;
  for (const formula of formulas) {
    if (formula.error) continue;
    if (formula.tag !== null) formula.tagString = '(' + formula.tag.value + ')';
    else if (formula.label !== null) formula.tagString = '(' + (++counter) + ')';
    else formula.tagString = null;
  }
  for (const formula of formulas) {
    if (formula.error || formula.label === null) continue;
    const { value, column } = formula.label;
    if (references.has(value)) formula.warnings.push({ column, message: `duplicate label "${value}"` });
    else references.set(value, formula.tagString!);
  }
  return references;
}

function drawGlyph(box: Box, glyph: Glyph, x: number): void {
  glyph.lines.forEach((line, y) => box.draw(line, x, y));
}

class Typesetter {
  params: Params;
  references: Map<string,string>;
  constructor(params: Params, references: Map<string,string>) { this.params = params; this.references = references; }

  atom(node: Extract<FormulaNode,{kind:'atom'}>, style: Style): Box {
    const kind = node.atom === 'text' ? 'text' : node.atom === 'reference' ? 'eqref' : 'atom';
    const description = `${kind} "${node.value}"`;
    if (node.atom === 'command' && style === 'normal' && LARGE_GLYPHS.has(node.value)) {
      const glyph = LARGE_GLYPHS.get(node.value)!, result = new Box(glyph[0].length, 3, 1, description);
      glyph.forEach((line, y) => result.draw(line, 0, y));
      return result;
    }
    const display = atomDisplay(node, this.references);
    return new Box(display.length, 1, 0, description).draw(display);
  }

  scripts(node: Extract<FormulaNode,{kind:'script'}>, style: Style): Box {
    const base = this.box(node.base, style);
    const sub = node.sub === null ? null : this.box(node.sub, 'script');
    const sup = node.sup === null ? null : this.box(node.sup, 'script');
    const subWidth = sub === null ? 0 : sub.width, supWidth = sup === null ? 0 : sup.width;
    const subHeight = sub === null ? 0 : sub.height, supHeight = sup === null ? 0 : sup.height;
    const stacked = style === 'normal' && ((node.base.kind === 'atom' && node.base.atom === 'command'
      && ['\\sum', '\\prod', '\\lim', '\\max', '\\min'].includes(node.base.value))
      || (node.base.kind === 'accent' && ['overbrace', 'underbrace'].includes(node.base.name)));
    if (stacked) {
      const width = Math.max(base.width, subWidth, supWidth);
      const result = new Box(width, supHeight + base.height + subHeight, supHeight + base.baseline, 'limits');
      result.add(base, center(base, width), supHeight, 'base: ');
      if (sub !== null) result.add(sub, center(sub, width), supHeight + base.height, 'sub: ');
      if (sup !== null) result.add(sup, center(sup, width), 0, 'sup: ');
      return result;
    }
    const supTop = (base.baseline === 0 ? -1 : 0) - supHeight + 1;
    const subTop = base.height - 1 - base.baseline === 0 ? base.height : base.height - 1;
    const top = sup === null ? 0 : Math.min(0, supTop);
    const bottom = sub === null ? base.height - 1 : Math.max(base.height - 1, subTop + subHeight - 1);
    const result = new Box(base.width + Math.max(subWidth, supWidth), bottom - top + 1, base.baseline - top, 'scripts');
    result.add(base, 0, -top, 'base: ');
    if (sub !== null) result.add(sub, base.width, subTop - top, 'sub: ');
    if (sup !== null) result.add(sup, base.width, supTop - top, 'sup: ');
    return result;
  }

  fraction(node: Extract<FormulaNode,{kind:'frac'|'binom'}>, style: Style): Box {
    if (style === 'script') {
      const parenthesized = (child: FormulaNode): FormulaNode => child.kind === 'row' || child.kind === 'frac'
        ? { kind: 'delim', left: '(', right: ')', body: child } : child;
      const numerator = this.box(parenthesized(node.first), style), denominator = this.box(parenthesized(node.second), style);
      const slash = new Box(1, 1, 0, 'atom "/"').draw('/');
      return rowBox([numerator, slash, denominator], [0, 0], 'slash', ['num: ', '', 'den: ']);
    }
    const numerator = this.box(node.first, style), denominator = this.box(node.second, style);
    const width = Math.max(numerator.width, denominator.width) + 2;
    const result = new Box(width, numerator.height + 1 + denominator.height, numerator.height, 'frac');
    result.add(numerator, center(numerator, width), 0, 'num: ');
    result.add(denominator, center(denominator, width), numerator.height + 1, 'den: ');
    return result.draw('-'.repeat(width), 0, numerator.height);
  }

  binomial(node: Extract<FormulaNode,{kind:'frac'|'binom'}>, style: Style): Box {
    const upper = this.box(node.first, style), lower = this.box(node.second, style);
    const width = Math.max(upper.width, lower.width), height = upper.height + 1 + lower.height;
    const result = new Box(width + 2, height, upper.height, 'binom');
    result.add(upper, center(upper, width) + 1, 0, 'upper: ');
    result.add(lower, center(lower, width) + 1, upper.height + 1, 'lower: ');
    drawGlyph(result, delimiterGlyph('(', height), 0);
    drawGlyph(result, delimiterGlyph(')', height), width + 1);
    return result;
  }

  placed(node: Extract<FormulaNode,{kind:'overset'|'underset'}>, style: Style): Box {
    const placed = this.box(node.placed, 'script'), base = this.box(node.base, style);
    const width = Math.max(placed.width, base.width), over = node.kind === 'overset';
    const result = new Box(width, placed.height + base.height, base.baseline + (over ? placed.height : 0), node.kind);
    if (over) {
      result.add(placed, center(placed, width), 0, 'over: ');
      result.add(base, center(base, width), placed.height, 'base: ');
    } else {
      result.add(base, center(base, width), 0, 'base: ');
      result.add(placed, center(placed, width), base.height, 'under: ');
    }
    return result;
  }

  radical(node: Extract<FormulaNode,{kind:'sqrt'|'root'}>, style: Style): Box {
    const body = this.box(node.body, style), index = node.kind === 'root' ? this.box(node.index, 'script') : null;
    const height = body.height, extra = index === null ? 0 : Math.max(0, index.width - 1);
    const top = index === null ? 0 : Math.max(0, index.height - height);
    const result = new Box(extra + height + 1 + body.width, height + 1 + top, body.baseline + 1 + top, node.kind);
    result.draw('_'.repeat(body.width), extra + height + 1, top).draw('\\', extra, height + top);
    for (let row = 1; row <= height; row++) result.draw('/', extra + height - row + 1, row + top);
    if (index !== null) result.add(index, 0, height - index.height + top, 'index: ');
    result.add(body, extra + height + 1, 1 + top, index === null ? '' : 'body: ');
    return result;
  }

  delimited(node: Extract<FormulaNode,{kind:'delim'}>, style: Style): Box {
    const body = this.box(node.body, style), left = delimiterGlyph(node.left, body.height), right = delimiterGlyph(node.right, body.height);
    const result = new Box(left.width + body.width + right.width, body.height, body.baseline, `delim ${node.left} ${node.right}`);
    drawGlyph(result, left, 0);
    result.add(body, left.width, 0);
    drawGlyph(result, right, left.width + body.width);
    return result;
  }

  matrix(node: Extract<FormulaNode,{kind:'matrix'}>, style: Style): Box {
    const cells = node.rows.map(row => row.map(cell => this.box(cell, style)));
    const rowCount = cells.length, columns = cells[0].length;
    const widths = Array(columns).fill(0), ascents = [], heights = [], lefts = [], tops = [];
    for (const row of cells) {
      let ascent = 0, descent = 0;
      row.forEach((cell, column) => {
        widths[column] = Math.max(widths[column], cell.width);
        ascent = Math.max(ascent, cell.baseline); descent = Math.max(descent, cell.height - 1 - cell.baseline);
      });
      ascents.push(ascent); heights.push(ascent + descent + 1);
    }
    let bodyWidth = 0, bodyHeight = 0;
    for (let column = 0; column < columns; column++) {
      lefts.push(bodyWidth); bodyWidth += widths[column];
      if (column + 1 < columns) bodyWidth += this.params.col_gap;
    }
    for (let row = 0; row < rowCount; row++) {
      tops.push(bodyHeight); bodyHeight += heights[row];
      if (row + 1 < rowCount) bodyHeight += this.params.row_gap;
    }
    const environment = node.environment, shift = environment === 'matrix' ? 0 : 2;
    const extra = environment === 'matrix' ? 0 : environment === 'cases' ? 2 : 4;
    const result = new Box(bodyWidth + extra, bodyHeight, Math.floor((bodyHeight - 1) / 2), `${environment} rows=${rowCount} cols=${columns}`);
    cells.forEach((row, i) => row.forEach((cell, j) => {
      const offset = environment === 'cases' ? 0 : center(cell, widths[j]);
      result.add(cell, shift + lefts[j] + offset, tops[i] + ascents[i] - cell.baseline, `cell ${i + 1},${j + 1}: `);
    }));
    if (environment === 'cases') drawGlyph(result, delimiterGlyph('\\{', bodyHeight), 0);
    else if (environment !== 'matrix') {
      const delimiters = ({ pmatrix: ['(', ')'], bmatrix: ['[', ']'], vmatrix: ['|', '|'] } as Record<string,[string,string]>)[environment];
      drawGlyph(result, delimiterGlyph(delimiters[0], bodyHeight), 0);
      drawGlyph(result, delimiterGlyph(delimiters[1], bodyHeight), bodyWidth + 3);
    }
    return result;
  }

  accent(node: Extract<FormulaNode,{kind:'accent'}>, style: Style): Box {
    const body = this.box(node.body, style), name = node.name;
    let width = body.width;
    if (['hat', 'dot', 'tilde'].includes(name)) width = Math.max(width, 1);
    else if (name === 'vec') width = Math.max(width, 2);
    else if (name === 'overbrace' || name === 'underbrace') width += 2;
    const result = new Box(width, body.height + 1, body.baseline + (name === 'underbrace' ? 0 : 1), name);
    if (name === 'underbrace') return result.add(body, 1, 0).draw('\\' + '-'.repeat(body.width) + '/', 0, body.height);
    result.add(body, name === 'overbrace' ? 1 : 0, 1);
    if (name === 'overline') result.draw('_'.repeat(width));
    else if (name === 'vec') result.draw('-'.repeat(width - 1) + '>');
    else if (name === 'overbrace') result.draw('/' + '-'.repeat(body.width) + '\\');
    else result.draw(({ hat: '^', dot: '.', tilde: '~' } as Record<string,string>)[name], Math.floor((width - 1) / 2), 0);
    return result;
  }

  box(node: FormulaNode, style: Style): Box {
    switch (node.kind) {
      case 'atom': return this.atom(node, style);
      case 'row': return rowBox(node.elements.map(child => this.box(child, style)), spacing(node.elements, style, this.params).gaps);
      case 'script': return this.scripts(node, style);
      case 'frac': return this.fraction(node, style);
      case 'binom': return this.binomial(node, style);
      case 'overset': case 'underset': return this.placed(node, style);
      case 'sqrt': case 'root': return this.radical(node, style);
      case 'delim': return this.delimited(node, style);
      case 'matrix': return this.matrix(node, style);
      case 'accent': return this.accent(node, style);
    }
  }
}

function buildLines(elements: FormulaNode[], boxes: Box[], types: [string,string][], gaps: number[], params: Params, pass: number): BrokenLine[] {
  const breaks: number[] = [], lefts = [0];
  for (let i = 1; i < elements.length; i++) {
    lefts.push(lefts[i - 1] + boxes[i - 1].width + gaps[i - 1]);
    const plusMinus = elements[i].kind === 'atom' && elements[i].atom === 'symbol'
      && ['+', '-'].includes(elements[i].value) && types[i][0] === 'binary';
    if (types[i][0] === 'relation' || (pass >= 1 && plusMinus) || (pass >= 2 && types[i - 1][1] === 'punctuation')) breaks.push(i);
  }
  breaks.push(elements.length);
  const width = (start: number, end: number): number => lefts[end - 1] + boxes[end - 1].width - lefts[start];
  const lines: BrokenLine[] = [];
  let start = 0, alignment: number | null = null, relationWidth = 0;
  while (start < elements.length) {
    const indent = start === 0 ? 0 : alignment === null ? params.indent
      : types[start][0] === 'relation' ? alignment : alignment + relationWidth + params.rel_space;
    const candidates = breaks.filter(end => end > start);
    let chosen: number | null = null;
    for (const end of candidates) if (indent + width(start, end) <= params.width) chosen = end;
    if (chosen === null) chosen = candidates[0];
    lines.push({ start, end: chosen, indent, width: width(start, chosen) });
    if (start === 0) {
      for (let i = 0; i < chosen; i++) if (types[i][0] === 'relation') {
        alignment = lefts[i]; relationWidth = boxes[i].width; break;
      }
    }
    start = chosen;
  }
  return lines;
}

function placeFormula(formula: Formula, typesetter: Typesetter, params: Params): LaidOutFormula {
  const elements = formula.elements, boxes = elements.map(element => typesetter.box(element, 'normal'));
  const { types, gaps } = spacing(elements, 'normal', params);
  let lines: BrokenLine[] = [];
  for (let pass = 0; pass < 3; pass++) {
    lines = buildLines(elements, boxes, types, gaps, params, pass);
    if (lines.every(line => line.indent + line.width <= params.width)) break;
  }
  const roots: Placement[] = [], overfull: {number: number; width: number}[] = [];
  let height = 0, width = 0;
  lines.forEach((line, index) => {
    const box = rowBox(boxes.slice(line.start, line.end), gaps.slice(line.start, line.end - 1), `line ${index + 1}`);
    roots.push({ box, x: line.indent, y: height });
    height += box.height; width = Math.max(width, line.indent + box.width);
    if (line.indent + box.width > params.width) overfull.push({ number: index + 1, width: line.indent + box.width });
  });
  if (formula.tagString !== null) {
    const tag = formula.tagString, x = params.width - tag.length, last = roots[roots.length - 1];
    const sameLine = x >= last.x + last.box.width + 2;
    const y = sameLine ? last.y + last.box.baseline : height++;
    roots.push({ box: new Box(tag.length, 1, 0, `tag "${tag}"`).draw(tag), x, y });
    width = Math.max(width, x + tag.length);
  }
  const placements = entries(roots), depth = Math.max(...placements.map(entry => entry.level)) + 1;
  return { lineCount: lines.length, width, height, placements, depth, overfull, rendered: draw(placements, width, height) };
}

function tree(node: FormulaNode): string {
  const delimiter = (value: string): string => value.length === 1 ? "'" + value + "'" : value;
  switch (node.kind) {
    case 'atom':
      if (node.atom === 'symbol') return "'" + node.value + "'";
      if (node.atom === 'text') return '"' + node.value + '"';
      if (node.atom === 'reference') return `(eqref "${node.value}")`;
      return node.value;
    case 'row': return '(row' + node.elements.map(child => ' ' + tree(child)).join('') + ')';
    case 'frac': case 'binom': return `(${node.kind} ${tree(node.first)} ${tree(node.second)})`;
    case 'overset': case 'underset': return `(${node.kind} ${tree(node.placed)} ${tree(node.base)})`;
    case 'sqrt': return `(sqrt ${tree(node.body)})`;
    case 'root': return `(root ${tree(node.index)} ${tree(node.body)})`;
    case 'script':
      if (node.sub === null) return `(sup ${tree(node.base)} ${tree(node.sup)})`;
      if (node.sup === null) return `(sub ${tree(node.base)} ${tree(node.sub)})`;
      return `(subsup ${tree(node.base)} ${tree(node.sub)} ${tree(node.sup)})`;
    case 'delim': return `(delim ${delimiter(node.left)} ${delimiter(node.right)} ${tree(node.body)})`;
    case 'matrix': return '(' + node.environment + node.rows.map(row => ' [' + row.map(tree).join(' ') + ']').join('') + ')';
    case 'accent': return `(${node.name} ${tree(node.body)})`;
  }
}

function linearRow(elements: FormulaNode[], style: Style, params: Params, references: Map<string,string>): string {
  const { gaps } = spacing(elements, style, params);
  return elements.map((child, index) => (index === 0 ? '' : ' '.repeat(gaps[index - 1])) + linear(child, style, params, references)).join('');
}

function linear(node: FormulaNode, style: Style, params: Params, references: Map<string,string>): string {
  const child = (value: FormulaNode, childStyle: Style = style): string => linear(value, childStyle, params, references);
  const grouped = (value: FormulaNode, kinds: string[], childStyle: Style = style): string => kinds.includes(value.kind) ? '(' + child(value, childStyle) + ')' : child(value, childStyle);
  const delimiter = (value: string): string => value === '.' ? '' : value.length === 1 ? value : value[1];
  switch (node.kind) {
    case 'atom': return atomDisplay(node, references);
    case 'row': return linearRow(node.elements, style, params, references);
    case 'frac': return grouped(node.first, ['row', 'frac']) + '/' + grouped(node.second, ['row', 'frac']);
    case 'binom': return `binom(${child(node.first)}, ${child(node.second)})`;
    case 'overset': case 'underset': return `${node.kind}(${child(node.placed, 'script')}, ${child(node.base)})`;
    case 'script': {
      let result = grouped(node.base, ['row', 'frac', 'script']);
      if (node.sub !== null) result += '_' + grouped(node.sub, ['row', 'frac'], 'script');
      if (node.sup !== null) result += '^' + grouped(node.sup, ['row', 'frac'], 'script');
      return result;
    }
    case 'sqrt': return `sqrt(${child(node.body)})`;
    case 'root': return `root(${child(node.index, 'script')}, ${child(node.body)})`;
    case 'delim': return delimiter(node.left) + child(node.body) + delimiter(node.right);
    case 'matrix': return node.environment + '[' + node.rows.map(row => row.map(cell => child(cell)).join(', ')).join('; ') + ']';
    case 'accent': return `${node.name}(${child(node.body)})`;
  }
}

function children(node: FormulaNode): FormulaNode[] {
  switch (node.kind) {
    case 'atom': return [];
    case 'row': return node.elements;
    case 'frac': case 'binom': return [node.first, node.second];
    case 'overset': case 'underset': return [node.placed, node.base];
    case 'root': return [node.index, node.body];
    case 'script': return [node.base, node.sub, node.sup].filter(child => child !== null);
    case 'matrix': return node.rows.flat();
    default: return [node.body];
  }
}

function collectWarnings(formula: Formula, references: Map<string,string>): void {
  for (const token of formula.tokens) {
    if (token.kind === 'identifier' && COMMAND_NAMES.has(token.value)) {
      formula.warnings.push({ column: token.column, message: `${token.value} is a command name; write \\${token.value}` });
    }
  }
  const pairs = new Map([['(', ')'], ['[', ']'], ['|', '|'], ['\\{', '\\}']]);
  const visit = (node: FormulaNode): void => {
    if (node.kind === 'atom' && node.atom === 'reference' && !references.has(node.value)) {
      formula.warnings.push({ column: node.column, message: `undefined reference "${node.value}"` });
    }
    if (node.kind === 'delim' && node.left !== '.' && node.right !== '.' && pairs.get(node.left) !== node.right) {
      formula.warnings.push({ column: node.rightColumn, message: `\\left${node.left} closed by \\right${node.right}` });
    }
    children(node).forEach(visit);
  };
  formula.elements.forEach(visit);
  formula.warnings.sort((a, b) => a.column - b.column);
}

function diagnostic(lines: string[], formula: Formula, issue: {column: number; message: string}, warning = false): void {
  lines.push(`formula ${formula.number}, column ${issue.column}: ${warning ? 'warning: ' : ''}${issue.message}`);
  lines.push('  ' + formula.source, ' '.repeat(issue.column + 1) + '^');
}

function writeReports(formulas: Formula[], params: Params, references: Map<string,string>): void {
  const typesetter = new Typesetter(params, references), rendered = [], boxReport = [], trees = [], errors = [];
  const kinds = new Map<string,number>();
  let valid = 0, boxCount = 0, maxDepth = 0, warningCount = 0, overfullCount = 0;
  for (const formula of formulas) {
    const heading = 'formula ' + formula.number;
    if (formula.error) {
      rendered.push(heading + '\n(error)'); boxReport.push(heading + ': error'); trees.push(heading + ': error');
      diagnostic(errors, formula, formula.error);
      continue;
    }
    valid++;
    const result = placeFormula(formula, typesetter, params);
    rendered.push([heading, ...result.rendered].join('\n'));
    boxReport.push(`${heading}: lines=${result.lineCount} width=${result.width} height=${result.height} boxes=${result.placements.length} depth=${result.depth}`);
    boxReport.push(...boxLines(result.placements));
    boxCount += result.placements.length; maxDepth = Math.max(maxDepth, result.depth);
    for (const entry of result.placements) {
      const kind = entry.box.description.split(' ')[0];
      kinds.set(kind, (kinds.get(kind) || 0) + 1);
    }
    trees.push(heading + ': ' + formula.elements.map(tree).join(' '));
    const notation = linearRow(formula.elements, 'normal', params, references).replace(/ +$/, '');
    trees.push('  linear:' + (notation === '' ? '' : ' ' + notation));
    if (formula.tagString !== null) trees.push('  tag: ' + formula.tagString);
    collectWarnings(formula, references);
    for (const warning of formula.warnings) diagnostic(errors, formula, warning, true);
    warningCount += formula.warnings.length;
    for (const line of result.overfull) errors.push(`${heading}: line ${line.number} is overfull (width ${line.width} > ${params.width})`);
    overfullCount += result.overfull.length;
  }
  boxReport.push(`summary: boxes=${boxCount} max_depth=${maxDepth}`);
  for (const kind of Array.from(kinds.keys()).sort()) boxReport.push(`  ${kind}: ${kinds.get(kind)}`);
  errors.push(`formulas=${formulas.length} rendered=${valid} errors=${formulas.length - valid} warnings=${warningCount} overfull=${overfullCount}`);
  mkdirSync('output', { recursive: true });
  writeFileSync('output/rendered.txt', rendered.join('\n\n') + '\n', 'ascii');
  writeFileSync('output/boxes.txt', boxReport.join('\n') + '\n', 'ascii');
  writeFileSync('output/trees.txt', trees.join('\n') + '\n', 'ascii');
  writeFileSync('output/errors.txt', errors.join('\n') + '\n', 'ascii');
}

function main(): void {
  const params = Object.fromEntries(inputLines('params.txt').map(line => {
    const [name, value] = line.split(' '); return [name, Number(value)];
  })) as unknown as Params;
  const formulas = parseFormulas(inputLines('formulas.txt'));
  const references = equationReferences(formulas);
  writeReports(formulas, params, references);
}

main();
