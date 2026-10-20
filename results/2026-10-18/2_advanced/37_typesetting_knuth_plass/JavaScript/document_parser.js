'use strict';

const BODY_KINDS = new Set(['paragraph', 'item', 'enum', 'quote', 'term']);
const DIRECTIVES = new Set(['width', 'indent', 'align', 'page', 'header', 'footer', 'newpage', 'hyphenation', 'bib',
  'title', 'author', 'h1', 'h2', 'item', 'enum', 'quote', 'term', 'table', 'verbatim', 'toc', 'lot', 'index', 'bibliography']);
const PREAMBLE = new Set(['page', 'header', 'footer']);
const EMPTY_ARGUMENT = new Set(['newpage', 'verbatim', 'toc', 'lot', 'index', 'bibliography']);
const NONEMPTY_ARGUMENT = new Set(['title', 'author', 'h1', 'h2', 'item', 'enum', 'quote']);

function splitFirst(text, separator) {
  const index = text.indexOf(separator);
  return index < 0 ? [text, ''] : [text.slice(0, index), text.slice(index + separator.length)];
}

function bibliographyEntry(argument) {
  const [key, rest] = splitFirst(argument, ' ');
  const parts = rest.split('|');
  if (!/^[a-z0-9]+$/.test(key) || parts.length !== 3 || parts[0] === '' || !/^[0-9]{4}$/.test(parts[1]) || parts[2] === '') return null;
  return { key, author: parts[0], year: parts[1], title: parts[2] };
}

function validArgument(name, argument) {
  if (name === 'width' || name === 'indent' || name === 'page') {
    const [minimum, maximum] = { width: [20, 80], indent: [0, 8], page: [10, 100] }[name];
    return /^[0-9]{1,9}$/.test(argument) && Number(argument) >= minimum && Number(argument) <= maximum;
  }
  if (name === 'align') return ['left', 'right', 'center', 'justify'].includes(argument);
  if (name === 'header' || name === 'footer') return argument.split('|').length === 3;
  if (EMPTY_ARGUMENT.has(name)) return argument === '';
  if (NONEMPTY_ARGUMENT.has(name)) return argument !== '';
  if (name === 'hyphenation') return argument.split(' ').every(word => /^[a-z]+(?:-[a-z]+)*$/.test(word));
  if (name === 'bib') return bibliographyEntry(argument) !== null;
  if (name === 'term') {
    const position = argument.indexOf('|');
    return position > 0 && position < argument.length - 1;
  }
  if (name === 'table') return /^[lrc]+$/.test(splitFirst(argument, ' ')[0]);
  return false;
}

function labeled(text) {
  const position = text.lastIndexOf(' {#');
  if (position >= 0 && text.endsWith('}')) return { text: text.slice(0, position), label: text.slice(position + 3, -1) };
  return { text, label: null };
}

function parseDocument(lines) {
  const document = { blocks: [], warnings: [], dictionaryWords: [], bibliography: [], pageWidth: null,
    pageHeight: 40, header: ['', '', ''], footer: ['', '', ''] };
  const settings = { width: 60, indent: 0, align: 'left' };
  const accepted = new Set();
  let open = null;
  let inner = null;
  let pendingBreak = false;
  function create(kind, line) {
    const block = { id: document.blocks.length, kind, line, ...settings, pageBreak: pendingBreak };
    pendingBreak = false;
    if (document.pageWidth === null) document.pageWidth = settings.width;
    document.blocks.push(block);
    return block;
  }
  for (let index = 0; index < lines.length; index++) {
    const text = lines[index];
    const line = index + 1;
    if (inner !== null) {
      if (text === '.end') inner = null;
      else inner.inner.push({ line, text });
      continue;
    }
    if (text === '') {
      open = null;
      continue;
    }
    if (!text.startsWith('.')) {
      if (open === null) {
        open = create('paragraph', line);
        open.bodyLines = [];
      }
      open.bodyLines.push({ line, text });
      continue;
    }
    open = null;
    const [name, argument] = splitFirst(text.slice(1), ' ');
    let warning = null;
    if (!DIRECTIVES.has(name)) warning = `unknown directive .${name}`;
    else if (!validArgument(name, argument)) warning = `bad argument for .${name}`;
    else if (PREAMBLE.has(name) && document.blocks.length) warning = `.${name} ignored after the preamble`;
    else if (PREAMBLE.has(name) && accepted.has(name)) warning = `duplicate .${name}`;
    if (warning !== null) {
      document.warnings.push({ line, message: warning });
      continue;
    }
    if (name === 'width' || name === 'indent') settings[name] = Number(argument);
    else if (name === 'align') settings.align = argument;
    else if (PREAMBLE.has(name)) {
      accepted.add(name);
      if (name === 'page') document.pageHeight = Number(argument);
      else document[name] = argument.split('|');
    } else if (name === 'newpage') pendingBreak = true;
    else if (name === 'hyphenation') document.dictionaryWords.push(...argument.split(' '));
    else if (name === 'bib') document.bibliography.push({ line, ...bibliographyEntry(argument) });
    else {
      const block = create(name, line);
      if (BODY_KINDS.has(name)) {
        let body = argument;
        if (name === 'term') [block.term, body] = splitFirst(argument, '|');
        block.bodyLines = [{ line, text: body }];
        open = block;
      } else if (name === 'h1' || name === 'h2') Object.assign(block, labeled(argument));
      else if (name === 'title' || name === 'author') block.text = argument;
      else if (name === 'table' || name === 'verbatim') {
        if (name === 'table') {
          const [columns, caption] = splitFirst(argument, ' ');
          const value = labeled(caption);
          block.columns = columns;
          block.caption = value.text;
          block.label = value.label;
        }
        block.inner = [];
        inner = block;
      }
    }
  }
  if (inner !== null) document.warnings.push({ line: inner.line, message: `unterminated ${inner.kind}` });
  if (document.pageWidth === null) document.pageWidth = 60;
  return document;
}

module.exports = { BODY_KINDS, parseDocument };
