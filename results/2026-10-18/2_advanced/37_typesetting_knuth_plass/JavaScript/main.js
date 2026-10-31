'use strict';

const fs = require('node:fs');
const { BODY_KINDS, parseDocument } = require('./document_parser');
const { Dictionary } = require('./hyphenation');
const lineBreaker = require('./line_breaker');
const { choosePages } = require('./page_builder');
const renderer = require('./renderer');

function readLines(filename) {
  const text = fs.readFileSync(filename, 'ascii');
  return text === '' ? [] : text.slice(0, -1).split('\n');
}

function compareText(first, second) {
  return first < second ? -1 : first > second ? 1 : 0;
}

function registerDocument(document) {
  document.labels = new Map();
  document.entries = new Map();
  document.headings = [];
  document.tables = [];
  document.bodies = [];
  let chapter = 0;
  let section = 0;
  let tableNumber = 0;
  for (let index = 0; index < document.blocks.length; index++) {
    const block = document.blocks[index];
    const previous = document.blocks[index - 1];
    if (block.kind === 'h1') {
      chapter++;
      section = 0;
      block.number = String(chapter);
      if (index > 0) block.pageBreak = true;
    } else if (block.kind === 'h2') {
      section++;
      block.number = `${chapter}.${section}`;
    } else if (block.kind === 'enum') {
      block.number = previous?.kind === 'enum' ? previous.number + 1 : 1;
    } else if (block.kind === 'table' && block.caption !== '') {
      block.number = ++tableNumber;
      document.tables.push(block);
    }
    if (block.kind === 'h1' || block.kind === 'h2') document.headings.push(block);
    if (block.label !== undefined && block.label !== null) {
      if (document.labels.has(block.label)) {
        document.warnings.push({ line: block.line, message: `duplicate label ${block.label}` });
        block.label = null;
      } else document.labels.set(block.label, block);
    }
    if (block.kind === 'paragraph' && (previous?.kind === 'h1' || previous?.kind === 'h2')) block.indent = 0;
    if (BODY_KINDS.has(block.kind)) {
      block.bodyNumber = document.bodies.length + 1;
      document.bodies.push(block);
    }
  }
  for (const entry of document.bibliography) {
    if (document.entries.has(entry.key)) document.warnings.push({ line: entry.line, message: `duplicate bibliography key ${entry.key}` });
    else document.entries.set(entry.key, { ...entry, cited: false });
  }
}

function parseBodyLine(document, bodyLine) {
  const tokens = [];
  const text = bodyLine.text;
  const warn = message => document.warnings.push({ line: bodyLine.line, message });
  let position = 0;
  while (position < text.length) {
    const opening = text.indexOf('{', position);
    if (opening < 0) {
      tokens.push(text.slice(position));
      break;
    }
    if (opening > position) tokens.push(text.slice(position, opening));
    const closing = text.indexOf('}', opening + 1);
    if (closing < 0) {
      warn('unclosed brace');
      tokens.push(text.slice(opening));
      break;
    }
    const content = text.slice(opening + 1, closing);
    const colon = content.indexOf(':');
    const kind = colon < 0 ? content : content.slice(0, colon);
    const argument = colon < 0 ? '' : content.slice(colon + 1);
    if (colon < 0 || argument === '' || !['ref', 'page', 'fn', 'idx', 'cite'].includes(kind)) {
      warn(`bad command {${content}}`);
    } else {
      const command = { kind, argument };
      if ((kind === 'ref' || kind === 'page') && !document.labels.has(argument)) warn(`undefined label ${argument}`);
      if (kind === 'cite') {
        for (const key of argument.split(',')) {
          const entry = document.entries.get(key);
          if (entry) entry.cited = true;
          else warn(`undefined citation ${key}`);
        }
      }
      if (kind === 'fn') {
        command.number = document.footnotes.length + 1;
        document.footnotes.push({ number: command.number, text: argument });
      } else if (kind === 'idx') {
        command.number = document.indexMarks.length + 1;
        document.indexMarks.push({ number: command.number, phrase: argument });
      }
      tokens.push(command);
    }
    position = closing + 1;
  }
  return tokens;
}

function checkDocument(document) {
  document.footnotes = [];
  document.indexMarks = [];
  for (const block of document.blocks) {
    if (block.kind === 'table') {
      const rows = [];
      for (const inner of block.inner) {
        const cells = inner.text.split('|').map(value => value.trim());
        if (cells.length !== block.columns.length) {
          document.warnings.push({ line: inner.line, message: `table row has ${cells.length} cells, expected ${block.columns.length}` });
        }
        cells.length = Math.min(cells.length, block.columns.length);
        while (cells.length < block.columns.length) cells.push('');
        rows.push(cells);
      }
      block.tableLines = renderer.tableRows(rows, block.columns);
      if (block.caption !== '') block.tableLines.unshift(`Table ${block.number}. ${block.caption}`);
      let maximum = 0;
      for (const line of block.tableLines) maximum = Math.max(maximum, line.length);
      if (maximum > block.width) document.warnings.push({ line: block.line, message: `table too wide by ${maximum - block.width}` });
    } else if (block.kind === 'verbatim') {
      for (const inner of block.inner) {
        if (inner.text.length > block.width) document.warnings.push({ line: inner.line, message: `verbatim line too long by ${inner.text.length - block.width}` });
      }
    } else if (BODY_KINDS.has(block.kind)) {
      block.body = [];
      for (let index = 0; index < block.bodyLines.length; index++) {
        if (index > 0) block.body.push(' ');
        block.body.push(...parseBodyLine(document, block.bodyLines[index]));
      }
    }
  }
  for (const entry of document.entries.values()) {
    if (!entry.cited) document.warnings.push({ line: entry.line, message: `unused bibliography entry ${entry.key}` });
  }
  document.warnings.sort((a, b) => a.line - b.line);
}

function bibliographyLabels(document) {
  const entries = [...document.entries.values()].filter(entry => entry.cited);
  for (const entry of entries) {
    const surnames = entry.author.split(' and ');
    let stem;
    if (surnames.length === 1) stem = surnames[0].slice(0, 3);
    else if (surnames.length <= 4) stem = surnames.map(name => name[0]).join('');
    else stem = surnames.slice(0, 3).map(name => name[0]).join('') + '+';
    entry.base = stem + entry.year.slice(-2);
  }
  entries.sort((a, b) => compareText(a.base, b.base) || compareText(a.author, b.author) || compareText(a.title, b.title) || compareText(a.key, b.key));
  for (let start = 0; start < entries.length;) {
    let end = start + 1;
    while (end < entries.length && entries[end].base === entries[start].base) end++;
    for (let index = start; index < end; index++) {
      entries[index].label = entries[index].base + (end - start === 1 ? '' : String.fromCharCode(97 + index - start));
    }
    start = end;
  }
  document.cited = entries;
}

function prepareIndex(document) {
  const parents = new Map();
  const makeEntry = name => ({ name, marks: [], crossReferences: new Set(), children: new Map() });
  for (const mark of document.indexMarks) {
    const bar = mark.phrase.indexOf('|');
    const entryPart = bar < 0 ? mark.phrase : mark.phrase.slice(0, bar);
    const crossReference = bar < 0 ? null : mark.phrase.slice(bar + 1);
    const exclamation = entryPart.indexOf('!');
    const parentName = exclamation < 0 ? entryPart : entryPart.slice(0, exclamation);
    if (!parents.has(parentName)) parents.set(parentName, makeEntry(parentName));
    let entry = parents.get(parentName);
    if (exclamation >= 0) {
      const childName = entryPart.slice(exclamation + 1);
      if (!entry.children.has(childName)) entry.children.set(childName, makeEntry(childName));
      entry = entry.children.get(childName);
    }
    if (crossReference === null) entry.marks.push(mark.number);
    else entry.crossReferences.add(crossReference);
  }
  const order = (a, b) => compareText(a.name.toLowerCase(), b.name.toLowerCase()) || compareText(a.name, b.name);
  const lines = [];
  let previousGroup = null;
  for (const parent of [...parents.values()].sort(order)) {
    const group = /[A-Za-z]/.test(parent.name[0]) ? parent.name[0].toUpperCase() : 'Symbols';
    if (group !== previousGroup) lines.push({ text: group });
    previousGroup = group;
    lines.push({ entry: parent, child: false });
    for (const child of [...parent.children.values()].sort(order)) lines.push({ entry: child, child: true });
  }
  document.indexLines = lines;
}

function citationText(document, argument) {
  const labels = new Set();
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

function expandBody(document, block, pageValues) {
  let text = '';
  const marks = [];
  for (const token of block.body) {
    if (typeof token === 'string') text += token;
    else if (token.kind === 'ref') text += document.labels.has(token.argument) ? String(document.labels.get(token.argument).number) : '??';
    else if (token.kind === 'page') text += document.labels.has(token.argument) ? pageValues.get(token.argument) : '??';
    else if (token.kind === 'cite') text += citationText(document, token.argument);
    else if (token.kind === 'fn') {
      marks.push({ kind: 'fn', number: token.number, offset: text.length });
      text += `[${token.number}]`;
    } else if (token.kind === 'idx') marks.push({ kind: 'idx', number: token.number, offset: text.length - 1 });
  }
  const words = [];
  const ranges = [];
  for (const match of text.matchAll(/[^ ]+/g)) {
    words.push(match[0]);
    ranges.push({ start: match.index, end: match.index + match[0].length });
  }
  let word = 0;
  for (const mark of marks) {
    while (mark.offset >= ranges[word].end) word++;
    mark.word = word;
    mark.position = mark.offset - ranges[word].start;
  }
  return { words, marks };
}

function lineProblem(words, firstCapacity, laterCapacity, dictionary, parameters) {
  const offsets = [];
  const points = [{ startWord: 0, startPosition: 0, mid: false, hyphen: false }];
  let offset = 0;
  for (let word = 0; word < words.length; word++) {
    offsets.push(offset);
    offset += words[word].length + 1;
    for (const split of dictionary.splitPoints(words[word], parameters.left_min, parameters.right_min)) {
      points.push({ startWord: word, startPosition: split.position, endWord: word, endPosition: split.position, mid: true, hyphen: split.hyphen });
    }
    points.push({ startWord: word + 1, startPosition: 0, endWord: word, endPosition: words[word].length, mid: false, hyphen: false });
  }
  function measure(a, b) {
    const start = points[a];
    const end = points[b];
    const length = offsets[end.endWord] + end.endPosition - offsets[start.startWord] - start.startPosition + Number(end.hyphen);
    const capacity = a === 0 ? firstCapacity : laterCapacity;
    return { a, b, firstWord: start.startWord, firstPosition: start.startPosition, lastWord: end.endWord,
      lastPosition: end.endPosition, length, capacity, slack: capacity - length,
      gaps: end.endWord - start.startWord, last: b === points.length - 1, mid: end.mid };
  }
  return { words, points, measure };
}

function breakText(words, marks, firstCapacity, laterCapacity, alignment, prefix, dictionary, parameters, method) {
  const problem = lineProblem(words, firstCapacity, laterCapacity, dictionary, parameters);
  const breaking = method === 'kp' ? lineBreaker.optimal(problem, parameters) : lineBreaker.greedy(problem, parameters);
  const lines = [];
  let start = 0;
  for (const end of breaking.breaks) {
    const line = problem.measure(start, end);
    line.pieces = [];
    for (let word = line.firstWord; word <= line.lastWord; word++) {
      const first = word === line.firstWord ? line.firstPosition : 0;
      const last = word === line.lastWord ? line.lastPosition : words[word].length;
      line.pieces.push(words[word].slice(first, last).replaceAll('~', ' '));
    }
    if (problem.points[end].hyphen) line.pieces[line.pieces.length - 1] += '-';
    line.marks = marks.filter(mark => mark.word >= line.firstWord && mark.word <= line.lastWord
      && (mark.word !== line.firstWord || mark.position >= line.firstPosition)
      && (mark.word !== line.lastWord || mark.position < line.lastPosition));
    line.footnotes = line.marks.filter(mark => mark.kind === 'fn').map(mark => mark.number);
    line.text = prefix(lines.length) + renderer.displayLine(line, alignment);
    lines.push(line);
    start = end;
  }
  return { lines, cost: breaking.cost };
}

function bodyStyle(block) {
  if (block.kind === 'paragraph') return { first: block.width - block.indent, later: block.width, prefix: index => index === 0 ? ' '.repeat(block.indent) : '' };
  if (block.kind === 'item') return { first: block.width - 2, later: block.width - 2, prefix: index => index === 0 ? '- ' : '  ' };
  if (block.kind === 'enum') return { first: block.width - 4, later: block.width - 4, prefix: index => index === 0 ? String(block.number).padStart(2, ' ') + '. ' : '    ' };
  if (block.kind === 'quote') return { first: block.width - 8, later: block.width - 8, prefix: () => '    ' };
  return { first: block.width - 12, later: block.width - 12,
    prefix: index => index === 0 && block.term.length <= 10 ? block.term.padEnd(12, ' ') : ' '.repeat(12) };
}

function plainLines(strings) {
  return strings.map(text => ({ text, marks: [], footnotes: [] }));
}

function typesetBlocks(document, dictionary, parameters, method, pageValues) {
  const blocks = [];
  const bodies = new Map();
  const references = new Map();
  const footnotes = new Map();
  for (const note of document.footnotes) {
    const prefix = `[${note.number}] `;
    const capacity = document.pageWidth - prefix.length;
    footnotes.set(note.number, breakText(note.text.split(' ').filter(Boolean), [], capacity, capacity, 'left',
      index => index === 0 ? prefix : ' '.repeat(prefix.length), dictionary, parameters, method));
  }
  function add(source, type, list, lines, first) {
    if (first) lines[0].blockStart = source;
    blocks.push({ type, list, lines, pageBreak: Boolean(first && source.pageBreak) });
  }
  for (const block of document.blocks) {
    if (BODY_KINDS.has(block.kind)) {
      const expanded = expandBody(document, block, pageValues);
      const style = bodyStyle(block);
      const broken = breakText(expanded.words, expanded.marks, style.first, style.later, block.align,
        style.prefix, dictionary, parameters, method);
      bodies.set(block.id, broken);
      const lines = block.kind === 'term' && block.term.length > 10 ? [...plainLines([block.term]), ...broken.lines] : broken.lines;
      add(block, 'flow', ['item', 'enum', 'term'].includes(block.kind), lines, true);
    } else if (block.kind === 'title' || block.kind === 'author') {
      const text = block.kind === 'title' ? block.text.toUpperCase() : block.text;
      add(block, 'heading', false, plainLines([' '.repeat(Math.floor((block.width - text.length) / 2)) + text]), true);
    } else if (block.kind === 'h1' || block.kind === 'h2') {
      const text = `${block.number} ${block.kind === 'h1' ? block.text.toUpperCase() : block.text}`;
      add(block, 'heading', false, plainLines([text, (block.kind === 'h1' ? '=' : '-').repeat(text.length)]), true);
    } else if (block.kind === 'table') {
      add(block, 'solid', false, plainLines(block.tableLines), true);
    } else if (block.kind === 'verbatim') {
      add(block, 'flow', false, plainLines(block.inner.map(line => line.text)), true);
    } else if (block.kind === 'toc' || block.kind === 'lot') {
      const contents = block.kind === 'toc';
      add(block, 'heading', false, plainLines(contents ? ['CONTENTS', '========'] : ['TABLES', '======']), true);
      const targets = contents ? document.headings : document.tables;
      const lines = targets.map(target => {
        const left = contents ? `${target.kind === 'h2' ? '  ' : ''}${target.number} ${target.text}` : `Table ${target.number}. ${target.caption}`;
        return { text: '', marks: [], footnotes: [], dynamic: { kind: 'listing', target: target.id, left, width: block.width } };
      });
      add(block, 'flow', false, lines, false);
    } else if (block.kind === 'index') {
      add(block, 'heading', false, plainLines(['INDEX', '=====']), true);
      const lines = document.indexLines.map(item => item.entry
        ? { text: '', marks: [], footnotes: [], dynamic: { kind: 'index', entry: item.entry, child: item.child } }
        : plainLines([item.text])[0]);
      add(block, 'flow', false, lines, false);
    } else if (block.kind === 'bibliography') {
      add(block, 'heading', false, plainLines(['REFERENCES', '==========']), true);
      let prefixWidth = 0;
      for (const entry of document.cited) prefixWidth = Math.max(prefixWidth, entry.label.length + 3);
      const entries = [];
      for (const entry of document.cited) {
        const text = `${entry.author}. ${entry.year}. ${entry.title}`;
        const prefix = `[${entry.label}]`.padEnd(prefixWidth, ' ');
        const capacity = block.width - prefixWidth;
        const broken = breakText(text.split(' ').filter(Boolean), [], capacity, capacity, 'left',
          index => index === 0 ? prefix : ' '.repeat(prefixWidth), dictionary, parameters, method);
        entries.push({ entry, broken });
        add(block, 'flow', true, broken.lines, false);
      }
      references.set(block.id, entries);
    }
  }
  return { blocks, bodies, references, footnotes };
}

function roman(number) {
  return 'x'.repeat(Math.floor(number / 10)) + ['', 'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix'][number % 10];
}

function numberPages(document, rawPages) {
  const pages = [];
  const blockPages = new Map();
  for (const page of rawPages) {
    page.chapterStart = page.content[0]?.blockStart?.kind === 'h1';
    if (page.chapterStart && (pages.length + 1) % 2 === 0) {
      pages.push({ serial: pages.length + 1, blank: true, content: [], footnotes: [], height: 0, endsByForce: true });
    }
    page.serial = pages.length + 1;
    pages.push(page);
    for (const line of page.content) if (line.blockStart) blockPages.set(line.blockStart.id, page);
  }
  const firstChapter = document.headings.find(block => block.kind === 'h1');
  const frontMatter = firstChapter ? blockPages.get(firstChapter.id).serial - 1 : 0;
  const indexPages = new Map();
  for (const page of pages) {
    page.bodyNumber = page.serial - frontMatter;
    page.display = page.serial <= frontMatter ? roman(page.serial) : String(page.bodyNumber);
    for (const line of page.content) {
      for (const mark of line.marks) if (mark.kind === 'idx') indexPages.set(mark.number, page.bodyNumber);
    }
  }
  const labelValues = new Map();
  for (const [label, block] of document.labels) labelValues.set(label, blockPages.get(block.id).display);
  return { pages, blockPages, indexPages, frontMatter, labelValues };
}

function pageList(numbers) {
  const ordered = [...new Set(numbers)].sort((a, b) => a - b);
  const pieces = [];
  for (let start = 0; start < ordered.length;) {
    let end = start + 1;
    while (end < ordered.length && ordered[end] === ordered[end - 1] + 1) end++;
    if (end - start >= 3) pieces.push(`${ordered[start]}-${ordered[end - 1]}`);
    else for (let index = start; index < end; index++) pieces.push(String(ordered[index]));
    start = end;
  }
  return pieces.join(', ');
}

function indexText(entry, child, indexPages) {
  let text = (child ? '  ' : '') + entry.name;
  const pages = pageList(entry.marks.map(number => indexPages.get(number)));
  if (pages !== '') text += ', ' + pages;
  const references = [...entry.crossReferences].sort(compareText);
  if (references.length) text += ', see ' + references.join(', ');
  return text;
}

function renderPages(document, layout, numbered) {
  let chapter = '';
  let section = '';
  for (const page of numbered.pages) {
    if (page.blank) {
      page.body = Array(document.pageHeight).fill('');
      page.header = '';
      page.footer = '';
      continue;
    }
    for (const line of page.content) {
      const dynamic = line.dynamic;
      if (dynamic?.kind === 'listing') {
        const number = numbered.blockPages.get(dynamic.target).display;
        const dots = '.'.repeat(dynamic.width - dynamic.left.length - number.length - 2);
        line.text = `${dynamic.left} ${dots} ${number}`;
      } else if (dynamic?.kind === 'index') line.text = indexText(dynamic.entry, dynamic.child, numbered.indexPages);
      const block = line.blockStart;
      if (block?.kind === 'h1') {
        chapter = `${block.number} ${block.text}`;
        section = '';
      } else if (block?.kind === 'h2') section = `${block.number} ${block.text}`;
    }
    const values = { page: page.display, pages: String(numbered.pages.length - numbered.frontMatter), chapter, section };
    page.header = page.chapterStart ? '' : renderer.runningHead(document.header, values, document.pageWidth, page.serial);
    page.footer = renderer.runningHead(document.footer, values, document.pageWidth, page.serial);
    page.body = page.content.map(line => line.text).concat(Array(document.pageHeight - page.height).fill(''));
    if (page.footnotes.length) {
      page.body.push('----------');
      for (const number of page.footnotes) for (const line of layout.footnotes.get(number).lines) page.body.push(line.text);
    }
  }
}

function layoutDocument(document, dictionary, parameters, method) {
  let current = new Map([...document.labels.keys()].map(label => [label, '??']));
  while (true) {
    const layout = typesetBlocks(document, dictionary, parameters, method, current);
    const rawPages = choosePages(layout.blocks, document.pageHeight, parameters, layout.footnotes);
    const numbered = numberPages(document, rawPages);
    let unchanged = true;
    for (const [label, value] of numbered.labelValues) if (current.get(label) !== value) unchanged = false;
    if (unchanged) {
      renderPages(document, layout, numbered);
      return { ...layout, ...numbered };
    }
    current = numbered.labelValues;
  }
}

function layoutWarnings(document, layout, parameters, method) {
  const lines = [];
  function examine(name, broken, justify) {
    broken.lines.forEach((line, index) => {
      if (line.slack < 0) lines.push(`${method}: ${name} line ${index + 1}: overfull by ${-line.slack}`);
      else if (justify && !line.last && line.slack >= parameters.underfull_slack) {
        lines.push(`${method}: ${name} line ${index + 1}: underfull, slack ${line.slack}`);
      }
    });
  }
  let hyphenated = 0;
  for (const block of document.blocks) {
    if (BODY_KINDS.has(block.kind)) {
      const broken = layout.bodies.get(block.id);
      examine(`paragraph ${block.bodyNumber}`, broken, block.align === 'justify');
      for (const line of broken.lines) if (line.mid) hyphenated++;
    } else if (block.kind === 'bibliography') {
      for (const { entry, broken } of layout.references.get(block.id)) examine(`reference ${entry.label}`, broken, false);
    }
  }
  for (const note of document.footnotes) examine(`footnote ${note.number}`, layout.footnotes.get(note.number), false);
  for (const page of layout.pages) {
    if (page.blank || page.endsByForce) continue;
    const empty = document.pageHeight - page.height;
    if (empty >= parameters.underfull_page) lines.push(`${method}: page ${page.serial}: underfull, ${empty} empty lines`);
  }
  lines.push(`${method}: ${layout.pages.length} pages, ${hyphenated} hyphenated lines`);
  return lines;
}

function statistics(document, optimal, greedy) {
  const lines = ['paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy'];
  const totals = [0, 0, 0, 0];
  for (const block of document.bodies) {
    const first = optimal.bodies.get(block.id);
    const second = greedy.bodies.get(block.id);
    const values = [first.lines.length, first.cost, second.lines.length, second.cost];
    for (let index = 0; index < 4; index++) totals[index] += values[index];
    lines.push([block.bodyNumber, ...values].join(','));
  }
  lines.push(['total', ...totals].join(','));
  return lines;
}

function writeLines(filename, lines) {
  fs.writeFileSync(`output/${filename}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

function main() {
  const parameters = Object.fromEntries(readLines('input/params.txt').map(line => {
    const [name, value] = line.split(' ');
    return [name, Number(value)];
  }));
  const document = parseDocument(readLines('input/document.txt'));
  registerDocument(document);
  checkDocument(document);
  bibliographyLabels(document);
  prepareIndex(document);
  const dictionary = new Dictionary(readLines('input/hyphenation.txt'), document.dictionaryWords);
  const optimal = layoutDocument(document, dictionary, parameters, 'kp');
  const greedy = layoutDocument(document, dictionary, parameters, 'greedy');
  const log = document.warnings.map(warning => `line ${warning.line}: ${warning.message}`);
  log.push(...layoutWarnings(document, optimal, parameters, 'kp'), ...layoutWarnings(document, greedy, parameters, 'greedy'));
  fs.mkdirSync('output', { recursive: true });
  writeLines('pages.txt', renderer.pageLines(optimal.pages));
  writeLines('greedy_pages.txt', renderer.pageLines(greedy.pages));
  writeLines('stats.csv', statistics(document, optimal, greedy));
  writeLines('log.txt', log);
}

if (require.main === module) main();
