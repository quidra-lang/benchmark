import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { parseDocument, isBody } from './document_parser.ts';
import type { ParsedDocument, Block, BodyToken, SourceLine, BibliographyEntry, Alignment } from './document_parser.ts';
import { Dictionary } from './hyphenation.ts';
import { optimal, greedy } from './line_breaker.ts';
import { choosePages } from './page_builder.ts';
import { displayLine, tableRows, runningHead, pageLines } from './renderer.ts';

export interface Parameters {
  line_penalty: number; hyphen_penalty: number; double_hyphen_demerit: number; final_hyphen_demerit: number;
  fitness_demerit: number; overfull_penalty: number; left_min: number; right_min: number;
  orphan_lines: number; widow_lines: number; underfull_slack: number; underfull_page: number;
}
type Method = 'kp' | 'greedy';
interface Entry extends BibliographyEntry { cited: boolean; base: string; label: string }
interface IndexEntry { name: string; marks: number[]; crossReferences: Set<string>; children: Map<string, IndexEntry> }
type IndexTemplate = { kind: 'group'; text: string } | { kind: 'entry'; entry: IndexEntry; child: boolean };
interface Document extends ParsedDocument {
  labels: Map<string, Block>; entries: Map<string, Entry>; headings: Block[]; tables: Block[]; bodies: Block[];
  footnotes: { number: number; text: string }[]; indexMarks: { number: number; phrase: string }[];
  cited: Entry[]; indexLines: IndexTemplate[];
}
interface BreakPoint { startWord: number; startPosition: number; endWord: number; endPosition: number; mid: boolean; hyphen: boolean }
export interface LineMetrics {
  a: number; b: number; firstWord: number; firstPosition: number; lastWord: number; lastPosition: number;
  length: number; capacity: number; slack: number; gaps: number; last: boolean; mid: boolean;
}
export interface LineProblem { words: string[]; points: BreakPoint[]; measure(a: number, b: number): LineMetrics }
interface Mark { kind: 'fn' | 'idx'; number: number; word: number; position: number }
type DynamicLine = { kind: 'listing'; target: number; left: string; width: number }
  | { kind: 'index'; entry: IndexEntry; child: boolean };
export interface PageLine { text: string; marks: Mark[]; footnotes: number[]; blockStart?: Block; dynamic?: DynamicLine }
export interface BrokenLine extends LineMetrics, PageLine { pieces: string[] }
export interface BrokenText { lines: BrokenLine[]; cost: number }
export interface LayoutBlock { type: 'heading' | 'solid' | 'flow'; list: boolean; lines: PageLine[]; pageBreak: boolean }
export interface RawPage { content: PageLine[]; footnotes: number[]; height: number; endsByForce: boolean; blank: boolean }
export interface Page extends RawPage {
  serial: number; chapterStart: boolean; bodyNumber: number; display: string; header: string; footer: string; body: string[];
}
interface Layout {
  blocks: LayoutBlock[]; bodies: Map<number, BrokenText>;
  references: Map<number, { entry: Entry; broken: BrokenText }[]>; footnotes: Map<number, BrokenText>;
}
interface Numbered {
  pages: Page[]; blockPages: Map<number, Page>; indexPages: Map<number, number>; frontMatter: number; labelValues: Map<string, string>;
}
type Result = Layout & Numbered;

const readLines = (filename: string): string[] => readFileSync(filename, 'ascii').split('\n').slice(0, -1);
const compareText = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;

function registerDocument(parsed: ParsedDocument): Document {
  const document: Document = { ...parsed, labels: new Map(), entries: new Map(), headings: [], tables: [], bodies: [],
    footnotes: [], indexMarks: [], cited: [], indexLines: [] };
  let chapter = 0, section = 0, tableNumber = 0;
  document.blocks.forEach((block, index) => {
    const previous = document.blocks[index - 1];
    if (block.kind === 'h1') {
      chapter++; section = 0; block.number = String(chapter);
      if (index > 0) block.pageBreak = true;
    } else if (block.kind === 'h2') { section++; block.number = `${chapter}.${section}`; }
    else if (block.kind === 'enum') block.number = String(previous?.kind === 'enum' ? Number(previous.number) + 1 : 1);
    else if (block.kind === 'table' && block.caption !== '') { block.number = String(++tableNumber); document.tables.push(block); }
    if (block.kind === 'h1' || block.kind === 'h2') document.headings.push(block);
    if (block.label !== null) {
      if (document.labels.has(block.label)) {
        document.warnings.push({ line: block.line, message: `duplicate label ${block.label}` }); block.label = null;
      } else document.labels.set(block.label, block);
    }
    if (block.kind === 'paragraph' && (previous?.kind === 'h1' || previous?.kind === 'h2')) block.indent = 0;
    if (isBody(block)) { block.bodyNumber = document.bodies.length + 1; document.bodies.push(block); }
  });
  for (const entry of document.bibliography) {
    if (document.entries.has(entry.key)) document.warnings.push({ line: entry.line, message: `duplicate bibliography key ${entry.key}` });
    else document.entries.set(entry.key, { ...entry, cited: false, base: '', label: '' });
  }
  return document;
}
function parseBodyLine(document: Document, bodyLine: SourceLine): BodyToken[] {
  const tokens: BodyToken[] = [], text = bodyLine.text;
  const warn = (message: string) => document.warnings.push({ line: bodyLine.line, message });
  let position = 0;
  while (position < text.length) {
    const opening = text.indexOf('{', position);
    if (opening < 0) { tokens.push(text.slice(position)); break; }
    if (opening > position) tokens.push(text.slice(position, opening));
    const closing = text.indexOf('}', opening + 1);
    if (closing < 0) { warn('unclosed brace'); tokens.push(text.slice(opening)); break; }
    const content = text.slice(opening + 1, closing), colon = content.indexOf(':');
    const kind = colon < 0 ? content : content.slice(0, colon), argument = colon < 0 ? '' : content.slice(colon + 1);
    if (colon < 0 || argument === '' || (kind !== 'ref' && kind !== 'page' && kind !== 'fn' && kind !== 'idx' && kind !== 'cite')) {
      warn(`bad command {${content}}`);
    } else {
      if ((kind === 'ref' || kind === 'page') && !document.labels.has(argument)) warn(`undefined label ${argument}`);
      if (kind === 'cite') for (const key of argument.split(',')) {
        const entry = document.entries.get(key);
        if (entry) entry.cited = true;
        else warn(`undefined citation ${key}`);
      }
      if (kind === 'fn') {
        const number = document.footnotes.length + 1;
        document.footnotes.push({ number, text: argument }); tokens.push({ kind, argument, number });
      } else if (kind === 'idx') {
        const number = document.indexMarks.length + 1;
        document.indexMarks.push({ number, phrase: argument }); tokens.push({ kind, argument, number });
      } else tokens.push({ kind, argument });
    }
    position = closing + 1;
  }
  return tokens;
}
function checkDocument(document: Document): void {
  for (const block of document.blocks) {
    if (block.kind === 'table') {
      const rows: string[][] = [];
      for (const inner of block.inner) {
        const cells = inner.text.split('|').map(value => value.trim());
        if (cells.length !== block.columns.length) document.warnings.push({ line: inner.line,
          message: `table row has ${cells.length} cells, expected ${block.columns.length}` });
        cells.length = Math.min(cells.length, block.columns.length);
        while (cells.length < block.columns.length) cells.push('');
        rows.push(cells);
      }
      block.tableLines = tableRows(rows, block.columns);
      if (block.caption !== '') block.tableLines.unshift(`Table ${block.number}. ${block.caption}`);
      const maximum = block.tableLines.reduce((width, line) => Math.max(width, line.length), 0);
      if (maximum > block.width) document.warnings.push({ line: block.line, message: `table too wide by ${maximum - block.width}` });
    } else if (block.kind === 'verbatim') {
      for (const inner of block.inner) if (inner.text.length > block.width) {
        document.warnings.push({ line: inner.line, message: `verbatim line too long by ${inner.text.length - block.width}` });
      }
    } else if (isBody(block)) {
      block.body = [];
      block.bodyLines.forEach((line, index) => {
        if (index > 0) block.body.push(' ');
        block.body.push(...parseBodyLine(document, line));
      });
    }
  }
  for (const entry of document.entries.values()) if (!entry.cited) {
    document.warnings.push({ line: entry.line, message: `unused bibliography entry ${entry.key}` });
  }
  document.warnings.sort((a, b) => a.line - b.line);
}
function bibliographyLabels(document: Document): void {
  const entries = [...document.entries.values()].filter(e => e.cited);
  for (const entry of entries) {
    const surnames = entry.author.split(' and ');
    const stem = surnames.length === 1 ? surnames[0].slice(0, 3) : surnames.length <= 4
      ? surnames.map(name => name[0]).join('') : surnames.slice(0, 3).map(name => name[0]).join('') + '+';
    entry.base = stem + entry.year.slice(-2);
  }
  entries.sort((a, b) => compareText(a.base, b.base) || compareText(a.author, b.author) || compareText(a.title, b.title) || compareText(a.key, b.key));
  for (let start = 0; start < entries.length;) {
    let end = start + 1;
    while (end < entries.length && entries[end].base === entries[start].base) end++;
    for (let i = start; i < end; i++) entries[i].label = entries[i].base + (end - start === 1 ? '' : String.fromCharCode(97 + i - start));
    start = end;
  }
  document.cited = entries;
}
function prepareIndex(document: Document): void {
  const parents = new Map<string, IndexEntry>();
  const makeEntry = (name: string): IndexEntry => ({ name, marks: [], crossReferences: new Set(), children: new Map() });
  for (const mark of document.indexMarks) {
    const bar = mark.phrase.indexOf('|'), entryPart = bar < 0 ? mark.phrase : mark.phrase.slice(0, bar);
    const crossReference = bar < 0 ? null : mark.phrase.slice(bar + 1), exclamation = entryPart.indexOf('!');
    const parentName = exclamation < 0 ? entryPart : entryPart.slice(0, exclamation);
    if (!parents.has(parentName)) parents.set(parentName, makeEntry(parentName));
    let entry = parents.get(parentName)!;
    if (exclamation >= 0) {
      const childName = entryPart.slice(exclamation + 1);
      if (!entry.children.has(childName)) entry.children.set(childName, makeEntry(childName));
      entry = entry.children.get(childName)!;
    }
    if (crossReference === null) entry.marks.push(mark.number);
    else entry.crossReferences.add(crossReference);
  }
  const order = (a: IndexEntry, b: IndexEntry) => compareText(a.name.toLowerCase(), b.name.toLowerCase()) || compareText(a.name, b.name);
  let previousGroup: string | null = null;
  for (const parent of [...parents.values()].sort(order)) {
    const group = /[A-Za-z]/.test(parent.name[0]) ? parent.name[0].toUpperCase() : 'Symbols';
    if (group !== previousGroup) document.indexLines.push({ kind: 'group', text: group });
    previousGroup = group;
    document.indexLines.push({ kind: 'entry', entry: parent, child: false });
    for (const child of [...parent.children.values()].sort(order)) document.indexLines.push({ kind: 'entry', entry: child, child: true });
  }
}
function citationText(document: Document, argument: string): string {
  const labels = new Set<string>();
  let missing = false;
  for (const key of argument.split(',')) {
    const entry = document.entries.get(key);
    if (entry) labels.add(entry.label);
    else missing = true;
  }
  const parts = [...labels].sort(compareText);
  if (missing) parts.push('?');
  return '[' + parts.join(', ') + ']';
}
function expandBody(document: Document, block: Block, pageValues: Map<string, string>) {
  let text = '';
  const offsets: { kind: 'fn' | 'idx'; number: number; offset: number }[] = [];
  for (const token of block.body) {
    if (typeof token === 'string') text += token;
    else if (token.kind === 'ref') text += document.labels.get(token.argument)?.number ?? '??';
    else if (token.kind === 'page') text += document.labels.has(token.argument) ? pageValues.get(token.argument)! : '??';
    else if (token.kind === 'cite') text += citationText(document, token.argument);
    else if (token.kind === 'fn') {
      offsets.push({ kind: 'fn', number: token.number, offset: text.length }); text += `[${token.number}]`;
    } else offsets.push({ kind: 'idx', number: token.number, offset: text.length - 1 });
  }
  const words: string[] = [], ranges: { start: number; end: number }[] = [];
  for (const match of text.matchAll(/[^ ]+/g)) {
    words.push(match[0]); ranges.push({ start: match.index, end: match.index + match[0].length });
  }
  let word = 0;
  const marks: Mark[] = offsets.map(mark => {
    while (mark.offset >= ranges[word].end) word++;
    return { kind: mark.kind, number: mark.number, word, position: mark.offset - ranges[word].start };
  });
  return { words, marks };
}
function lineProblem(words: string[], firstCapacity: number, laterCapacity: number, dictionary: Dictionary, parameters: Parameters): LineProblem {
  const offsets: number[] = [], points: BreakPoint[] = [{ startWord: 0, startPosition: 0, endWord: 0, endPosition: 0, mid: false, hyphen: false }];
  let offset = 0;
  words.forEach((word, i) => {
    offsets.push(offset); offset += word.length + 1;
    for (const split of dictionary.splitPoints(word, parameters.left_min, parameters.right_min)) points.push({
      startWord: i, startPosition: split.position, endWord: i, endPosition: split.position, mid: true, hyphen: split.hyphen });
    points.push({ startWord: i + 1, startPosition: 0, endWord: i, endPosition: word.length, mid: false, hyphen: false });
  });
  const measure = (a: number, b: number): LineMetrics => {
    const start = points[a], end = points[b];
    const length = offsets[end.endWord] + end.endPosition - offsets[start.startWord] - start.startPosition + Number(end.hyphen);
    const capacity = a === 0 ? firstCapacity : laterCapacity;
    return { a, b, firstWord: start.startWord, firstPosition: start.startPosition, lastWord: end.endWord,
      lastPosition: end.endPosition, length, capacity, slack: capacity - length, gaps: end.endWord - start.startWord,
      last: b === points.length - 1, mid: end.mid };
  };
  return { words, points, measure };
}
function breakText(words: string[], marks: Mark[], firstCapacity: number, laterCapacity: number, alignment: Alignment,
  prefix: (index: number) => string, dictionary: Dictionary, parameters: Parameters, method: Method): BrokenText {
  const problem = lineProblem(words, firstCapacity, laterCapacity, dictionary, parameters);
  const breaking = method === 'kp' ? optimal(problem, parameters) : greedy(problem, parameters), lines: BrokenLine[] = [];
  let start = 0;
  for (const end of breaking.breaks) {
    const metrics = problem.measure(start, end), pieces: string[] = [];
    for (let word = metrics.firstWord; word <= metrics.lastWord; word++) {
      const first = word === metrics.firstWord ? metrics.firstPosition : 0, last = word === metrics.lastWord ? metrics.lastPosition : words[word].length;
      pieces.push(words[word].slice(first, last).replaceAll('~', ' '));
    }
    if (problem.points[end].hyphen) pieces[pieces.length - 1] += '-';
    const contained = marks.filter(mark => mark.word >= metrics.firstWord && mark.word <= metrics.lastWord
      && (mark.word !== metrics.firstWord || mark.position >= metrics.firstPosition)
      && (mark.word !== metrics.lastWord || mark.position < metrics.lastPosition));
    const line: BrokenLine = { ...metrics, pieces, marks: contained, footnotes: contained.filter(m => m.kind === 'fn').map(m => m.number), text: '' };
    line.text = prefix(lines.length) + displayLine(line, alignment);
    lines.push(line); start = end;
  }
  return { lines, cost: breaking.cost };
}
function bodyStyle(block: Block): { first: number; later: number; prefix: (index: number) => string } {
  if (block.kind === 'paragraph') return { first: block.width - block.indent, later: block.width, prefix: i => i === 0 ? ' '.repeat(block.indent) : '' };
  if (block.kind === 'item') return { first: block.width - 2, later: block.width - 2, prefix: i => i === 0 ? '- ' : '  ' };
  if (block.kind === 'enum') return { first: block.width - 4, later: block.width - 4, prefix: i => i === 0 ? block.number.padStart(2, ' ') + '. ' : '    ' };
  if (block.kind === 'quote') return { first: block.width - 8, later: block.width - 8, prefix: () => '    ' };
  return { first: block.width - 12, later: block.width - 12, prefix: i => i === 0 && block.term.length <= 10 ? block.term.padEnd(12, ' ') : ' '.repeat(12) };
}
const plainLines = (strings: string[]): PageLine[] => strings.map(text => ({ text, marks: [], footnotes: [] }));
function typesetBlocks(document: Document, dictionary: Dictionary, parameters: Parameters, method: Method, pageValues: Map<string, string>): Layout {
  const layout: Layout = { blocks: [], bodies: new Map(), references: new Map(), footnotes: new Map() };
  for (const note of document.footnotes) {
    const prefix = `[${note.number}] `, capacity = document.pageWidth - prefix.length;
    layout.footnotes.set(note.number, breakText(note.text.split(' ').filter(Boolean), [], capacity, capacity, 'left',
      i => i === 0 ? prefix : ' '.repeat(prefix.length), dictionary, parameters, method));
  }
  const add = (source: Block, type: LayoutBlock['type'], list: boolean, lines: PageLine[], first: boolean) => {
    if (first) lines[0].blockStart = source;
    layout.blocks.push({ type, list, lines, pageBreak: first && source.pageBreak });
  };
  for (const block of document.blocks) {
    if (isBody(block)) {
      const expanded = expandBody(document, block, pageValues), style = bodyStyle(block);
      const broken = breakText(expanded.words, expanded.marks, style.first, style.later, block.align, style.prefix, dictionary, parameters, method);
      layout.bodies.set(block.id, broken);
      const lines = block.kind === 'term' && block.term.length > 10 ? [...plainLines([block.term]), ...broken.lines] : broken.lines;
      add(block, 'flow', ['item', 'enum', 'term'].includes(block.kind), lines, true);
    } else if (block.kind === 'title' || block.kind === 'author') {
      const text = block.kind === 'title' ? block.text.toUpperCase() : block.text;
      add(block, 'heading', false, plainLines([' '.repeat(Math.floor((block.width - text.length) / 2)) + text]), true);
    } else if (block.kind === 'h1' || block.kind === 'h2') {
      const text = `${block.number} ${block.kind === 'h1' ? block.text.toUpperCase() : block.text}`;
      add(block, 'heading', false, plainLines([text, (block.kind === 'h1' ? '=' : '-').repeat(text.length)]), true);
    } else if (block.kind === 'table') add(block, 'solid', false, plainLines(block.tableLines), true);
    else if (block.kind === 'verbatim') add(block, 'flow', false, plainLines(block.inner.map(line => line.text)), true);
    else if (block.kind === 'toc' || block.kind === 'lot') {
      const contents = block.kind === 'toc';
      add(block, 'heading', false, plainLines(contents ? ['CONTENTS', '========'] : ['TABLES', '======']), true);
      const targets = contents ? document.headings : document.tables;
      const lines: PageLine[] = targets.map(target => ({ text: '', marks: [], footnotes: [], dynamic: { kind: 'listing', target: target.id,
        left: contents ? `${target.kind === 'h2' ? '  ' : ''}${target.number} ${target.text}` : `Table ${target.number}. ${target.caption}`, width: block.width } }));
      add(block, 'flow', false, lines, false);
    } else if (block.kind === 'index') {
      add(block, 'heading', false, plainLines(['INDEX', '=====']), true);
      const lines: PageLine[] = document.indexLines.map(item => item.kind === 'entry'
        ? { text: '', marks: [], footnotes: [], dynamic: { kind: 'index', entry: item.entry, child: item.child } } : plainLines([item.text])[0]);
      add(block, 'flow', false, lines, false);
    } else if (block.kind === 'bibliography') {
      add(block, 'heading', false, plainLines(['REFERENCES', '==========']), true);
      const prefixWidth = document.cited.reduce((w, e) => Math.max(w, e.label.length + 3), 0), entries: { entry: Entry; broken: BrokenText }[] = [];
      for (const entry of document.cited) {
        const text = `${entry.author}. ${entry.year}. ${entry.title}`, prefix = `[${entry.label}]`.padEnd(prefixWidth, ' ');
        const capacity = block.width - prefixWidth;
        const broken = breakText(text.split(' ').filter(Boolean), [], capacity, capacity, 'left',
          i => i === 0 ? prefix : ' '.repeat(prefixWidth), dictionary, parameters, method);
        entries.push({ entry, broken }); add(block, 'flow', true, broken.lines, false);
      }
      layout.references.set(block.id, entries);
    }
  }
  return layout;
}

const roman = (n: number): string => 'x'.repeat(Math.floor(n / 10)) + ['', 'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix'][n % 10];
function numberPages(document: Document, rawPages: RawPage[]): Numbered {
  const pages: Page[] = [], blockPages = new Map<number, Page>();
  for (const raw of rawPages) {
    const chapterStart = raw.content[0]?.blockStart?.kind === 'h1';
    if (chapterStart && (pages.length + 1) % 2 === 0) pages.push({ serial: pages.length + 1, blank: true, content: [], footnotes: [],
      height: 0, endsByForce: true, chapterStart: false, bodyNumber: 0, display: '', header: '', footer: '', body: [] });
    const page: Page = { ...raw, chapterStart, serial: pages.length + 1, bodyNumber: 0, display: '', header: '', footer: '', body: [] };
    pages.push(page);
    for (const line of page.content) if (line.blockStart) blockPages.set(line.blockStart.id, page);
  }
  const firstChapter = document.headings.find(b => b.kind === 'h1');
  const frontMatter = firstChapter ? blockPages.get(firstChapter.id)!.serial - 1 : 0, indexPages = new Map<number, number>();
  for (const page of pages) {
    page.bodyNumber = page.serial - frontMatter;
    page.display = page.serial <= frontMatter ? roman(page.serial) : String(page.bodyNumber);
    for (const line of page.content) for (const mark of line.marks) if (mark.kind === 'idx') indexPages.set(mark.number, page.bodyNumber);
  }
  const labelValues = new Map<string, string>();
  for (const [label, block] of document.labels) labelValues.set(label, blockPages.get(block.id)!.display);
  return { pages, blockPages, indexPages, frontMatter, labelValues };
}
function pageList(numbers: number[]): string {
  const ordered = [...new Set(numbers)].sort((a, b) => a - b), pieces: string[] = [];
  for (let start = 0; start < ordered.length;) {
    let end = start + 1;
    while (end < ordered.length && ordered[end] === ordered[end - 1] + 1) end++;
    if (end - start >= 3) pieces.push(`${ordered[start]}-${ordered[end - 1]}`);
    else for (let i = start; i < end; i++) pieces.push(String(ordered[i]));
    start = end;
  }
  return pieces.join(', ');
}
function indexText(entry: IndexEntry, child: boolean, indexPages: Map<number, number>): string {
  let text = (child ? '  ' : '') + entry.name;
  const pages = pageList(entry.marks.map(n => indexPages.get(n)!));
  if (pages !== '') text += ', ' + pages;
  const references = [...entry.crossReferences].sort(compareText);
  if (references.length) text += ', see ' + references.join(', ');
  return text;
}
function renderPages(document: Document, layout: Layout, numbered: Numbered): void {
  let chapter = '', section = '';
  for (const page of numbered.pages) {
    if (page.blank) { page.body = Array<string>(document.pageHeight).fill(''); page.header = page.footer = ''; continue; }
    for (const line of page.content) {
      const dynamic = line.dynamic;
      if (dynamic?.kind === 'listing') {
        const number = numbered.blockPages.get(dynamic.target)!.display, dots = '.'.repeat(dynamic.width - dynamic.left.length - number.length - 2);
        line.text = `${dynamic.left} ${dots} ${number}`;
      } else if (dynamic?.kind === 'index') line.text = indexText(dynamic.entry, dynamic.child, numbered.indexPages);
      const block = line.blockStart;
      if (block?.kind === 'h1') { chapter = `${block.number} ${block.text}`; section = ''; }
      else if (block?.kind === 'h2') section = `${block.number} ${block.text}`;
    }
    const values = { page: page.display, pages: String(numbered.pages.length - numbered.frontMatter), chapter, section };
    page.header = page.chapterStart ? '' : runningHead(document.header, values, document.pageWidth, page.serial);
    page.footer = runningHead(document.footer, values, document.pageWidth, page.serial);
    page.body = page.content.map(line => line.text).concat(Array<string>(document.pageHeight - page.height).fill(''));
    if (page.footnotes.length) {
      page.body.push('----------');
      for (const number of page.footnotes) for (const line of layout.footnotes.get(number)!.lines) page.body.push(line.text);
    }
  }
}
function layoutDocument(document: Document, dictionary: Dictionary, parameters: Parameters, method: Method): Result {
  let current = new Map([...document.labels.keys()].map(label => [label, '??']));
  while (true) {
    const layout = typesetBlocks(document, dictionary, parameters, method, current);
    const numbered = numberPages(document, choosePages(layout.blocks, document.pageHeight, parameters, layout.footnotes));
    if ([...numbered.labelValues].every(([label, value]) => current.get(label) === value)) {
      renderPages(document, layout, numbered);
      return { ...layout, ...numbered };
    }
    current = numbered.labelValues;
  }
}
function layoutWarnings(document: Document, layout: Result, parameters: Parameters, method: Method): string[] {
  const lines: string[] = [];
  const examine = (name: string, broken: BrokenText, justify: boolean) => {
    broken.lines.forEach((line, i) => {
      if (line.slack < 0) lines.push(`${method}: ${name} line ${i + 1}: overfull by ${-line.slack}`);
      else if (justify && !line.last && line.slack >= parameters.underfull_slack) lines.push(`${method}: ${name} line ${i + 1}: underfull, slack ${line.slack}`);
    });
  };
  let hyphenated = 0;
  for (const block of document.blocks) {
    if (isBody(block)) {
      const broken = layout.bodies.get(block.id)!;
      examine(`paragraph ${block.bodyNumber}`, broken, block.align === 'justify');
      for (const line of broken.lines) if (line.mid) hyphenated++;
    } else if (block.kind === 'bibliography') {
      for (const { entry, broken } of layout.references.get(block.id)!) examine(`reference ${entry.label}`, broken, false);
    }
  }
  for (const note of document.footnotes) examine(`footnote ${note.number}`, layout.footnotes.get(note.number)!, false);
  for (const page of layout.pages) {
    if (page.blank || page.endsByForce) continue;
    const empty = document.pageHeight - page.height;
    if (empty >= parameters.underfull_page) lines.push(`${method}: page ${page.serial}: underfull, ${empty} empty lines`);
  }
  return [...lines, `${method}: ${layout.pages.length} pages, ${hyphenated} hyphenated lines`];
}
function statistics(document: Document, kp: Result, greedy: Result): string[] {
  const lines = ['paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy'], totals = [0, 0, 0, 0];
  for (const block of document.bodies) {
    const first = kp.bodies.get(block.id)!, second = greedy.bodies.get(block.id)!;
    const values = [first.lines.length, first.cost, second.lines.length, second.cost];
    values.forEach((value, i) => { totals[i] += value; });
    lines.push([block.bodyNumber, ...values].join(','));
  }
  return [...lines, ['total', ...totals].join(',')];
}
function readParameters(): Parameters {
  const fields = new Map(readLines('input/params.txt').map(line => {
    const [name, value] = line.split(' ');
    return [name, Number(value)];
  }));
  return { line_penalty: fields.get('line_penalty')!, hyphen_penalty: fields.get('hyphen_penalty')!,
    double_hyphen_demerit: fields.get('double_hyphen_demerit')!, final_hyphen_demerit: fields.get('final_hyphen_demerit')!,
    fitness_demerit: fields.get('fitness_demerit')!, overfull_penalty: fields.get('overfull_penalty')!,
    left_min: fields.get('left_min')!, right_min: fields.get('right_min')!, orphan_lines: fields.get('orphan_lines')!,
    widow_lines: fields.get('widow_lines')!, underfull_slack: fields.get('underfull_slack')!, underfull_page: fields.get('underfull_page')! };
}
function main(): void {
  const parameters = readParameters(), document = registerDocument(parseDocument(readLines('input/document.txt')));
  checkDocument(document); bibliographyLabels(document); prepareIndex(document);
  const dictionary = new Dictionary(readLines('input/hyphenation.txt'), document.dictionaryWords);
  const kp = layoutDocument(document, dictionary, parameters, 'kp'), greedy = layoutDocument(document, dictionary, parameters, 'greedy');
  const log = document.warnings.map(w => `line ${w.line}: ${w.message}`);
  log.push(...layoutWarnings(document, kp, parameters, 'kp'), ...layoutWarnings(document, greedy, parameters, 'greedy'));
  const files: Record<string, string[]> = { 'pages.txt': pageLines(kp.pages), 'greedy_pages.txt': pageLines(greedy.pages),
    'stats.csv': statistics(document, kp, greedy), 'log.txt': log };
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(files)) writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
main();
