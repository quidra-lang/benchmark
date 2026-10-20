export type Alignment = 'left' | 'right' | 'center' | 'justify';
export type BodyKind = 'paragraph' | 'item' | 'enum' | 'quote' | 'term';
export type BlockKind = BodyKind | 'title' | 'author' | 'h1' | 'h2' | 'table' | 'verbatim' | 'toc' | 'lot' | 'index' | 'bibliography';
export interface SourceLine { line: number; text: string }
export interface Warning { line: number; message: string }
export interface BibliographyEntry { line: number; key: string; author: string; year: string; title: string }
export type BodyToken = string | { kind: 'ref' | 'page' | 'cite'; argument: string }
  | { kind: 'fn' | 'idx'; argument: string; number: number };
export interface Block {
  id: number; kind: BlockKind; line: number; width: number; indent: number; align: Alignment; pageBreak: boolean;
  text: string; label: string | null; number: string; term: string; caption: string; columns: string;
  bodyLines: SourceLine[]; inner: SourceLine[]; body: BodyToken[]; tableLines: string[]; bodyNumber: number;
}
export interface ParsedDocument {
  blocks: Block[]; warnings: Warning[]; dictionaryWords: string[]; bibliography: BibliographyEntry[];
  pageWidth: number; pageHeight: number; header: string[]; footer: string[];
}
export const isBody = (block: Block): boolean => ['paragraph', 'item', 'enum', 'quote', 'term'].includes(block.kind);
const BLOCK_KINDS: BlockKind[] = ['title', 'author', 'h1', 'h2', 'item', 'enum', 'quote', 'term', 'table', 'verbatim', 'toc', 'lot', 'index', 'bibliography'];
const DIRECTIVES = new Set(['width', 'indent', 'align', 'page', 'header', 'footer', 'newpage', 'hyphenation', 'bib', ...BLOCK_KINDS]);
const PREAMBLE = new Set(['page', 'header', 'footer']);

export function splitFirst(text: string, separator: string): [string, string] {
  const index = text.indexOf(separator);
  return index < 0 ? [text, ''] : [text.slice(0, index), text.slice(index + separator.length)];
}
function bibliographyEntry(argument: string): Omit<BibliographyEntry, 'line'> | null {
  const [key, rest] = splitFirst(argument, ' '), parts = rest.split('|');
  if (!/^[a-z0-9]+$/.test(key) || parts.length !== 3 || parts[0] === '' || !/^[0-9]{4}$/.test(parts[1]) || parts[2] === '') return null;
  return { key, author: parts[0], year: parts[1], title: parts[2] };
}
function validArgument(name: string, argument: string): boolean {
  if (name === 'width' || name === 'indent' || name === 'page') {
    const [minimum, maximum] = name === 'width' ? [20, 80] : name === 'indent' ? [0, 8] : [10, 100];
    return /^[0-9]{1,9}$/.test(argument) && Number(argument) >= minimum && Number(argument) <= maximum;
  }
  if (name === 'align') return ['left', 'right', 'center', 'justify'].includes(argument);
  if (name === 'header' || name === 'footer') return argument.split('|').length === 3;
  if (['newpage', 'verbatim', 'toc', 'lot', 'index', 'bibliography'].includes(name)) return argument === '';
  if (['title', 'author', 'h1', 'h2', 'item', 'enum', 'quote'].includes(name)) return argument !== '';
  if (name === 'hyphenation') return argument.split(' ').every(word => /^[a-z]+(?:-[a-z]+)*$/.test(word));
  if (name === 'bib') return bibliographyEntry(argument) !== null;
  if (name === 'term') { const at = argument.indexOf('|'); return at > 0 && at < argument.length - 1; }
  if (name === 'table') return /^[lrc]+$/.test(splitFirst(argument, ' ')[0]);
  return false;
}
function labeled(text: string): { text: string; label: string | null } {
  const position = text.lastIndexOf(' {#');
  return position >= 0 && text.endsWith('}')
    ? { text: text.slice(0, position), label: text.slice(position + 3, -1) } : { text, label: null };
}

export function parseDocument(lines: string[]): ParsedDocument {
  const document: ParsedDocument = { blocks: [], warnings: [], dictionaryWords: [], bibliography: [],
    pageWidth: 60, pageHeight: 40, header: ['', '', ''], footer: ['', '', ''] };
  let width = 60, indent = 0, align: Alignment = 'left';
  const accepted = new Set<string>();
  let open: Block | null = null, inner: Block | null = null, pendingBreak = false;
  const create = (kind: BlockKind, line: number): Block => {
    const block: Block = { id: document.blocks.length, kind, line, width, indent, align, pageBreak: pendingBreak,
      text: '', label: null, number: '', term: '', caption: '', columns: '', bodyLines: [], inner: [], body: [], tableLines: [], bodyNumber: 0 };
    pendingBreak = false;
    if (!document.blocks.length) document.pageWidth = width;
    document.blocks.push(block);
    return block;
  };
  for (let index = 0; index < lines.length; index++) {
    const text = lines[index], line = index + 1;
    if (inner !== null) {
      if (text === '.end') inner = null;
      else inner.inner.push({ line, text });
      continue;
    }
    if (text === '') { open = null; continue; }
    if (!text.startsWith('.')) {
      if (open === null) open = create('paragraph', line);
      open.bodyLines.push({ line, text });
      continue;
    }
    open = null;
    const [name, argument] = splitFirst(text.slice(1), ' ');
    let warning: string | null = null;
    if (!DIRECTIVES.has(name)) warning = `unknown directive .${name}`;
    else if (!validArgument(name, argument)) warning = `bad argument for .${name}`;
    else if (PREAMBLE.has(name) && document.blocks.length) warning = `.${name} ignored after the preamble`;
    else if (PREAMBLE.has(name) && accepted.has(name)) warning = `duplicate .${name}`;
    if (warning !== null) { document.warnings.push({ line, message: warning }); continue; }
    if (name === 'width') width = Number(argument);
    else if (name === 'indent') indent = Number(argument);
    else if (name === 'align') {
      if (argument === 'left' || argument === 'right' || argument === 'center' || argument === 'justify') align = argument;
    } else if (PREAMBLE.has(name)) {
      accepted.add(name);
      if (name === 'page') document.pageHeight = Number(argument);
      else if (name === 'header') document.header = argument.split('|');
      else document.footer = argument.split('|');
    } else if (name === 'newpage') pendingBreak = true;
    else if (name === 'hyphenation') document.dictionaryWords.push(...argument.split(' '));
    else if (name === 'bib') document.bibliography.push({ line, ...bibliographyEntry(argument)! });
    else {
      const block = create(BLOCK_KINDS.find(kind => kind === name)!, line);
      if (isBody(block)) {
        let body = argument;
        if (name === 'term') [block.term, body] = splitFirst(argument, '|');
        block.bodyLines.push({ line, text: body }); open = block;
      } else if (name === 'h1' || name === 'h2') Object.assign(block, labeled(argument));
      else if (name === 'title' || name === 'author') block.text = argument;
      else if (name === 'table' || name === 'verbatim') {
        if (name === 'table') {
          const [columns, caption] = splitFirst(argument, ' '), value = labeled(caption);
          block.columns = columns; block.caption = value.text; block.label = value.label;
        }
        inner = block;
      }
    }
  }
  if (inner !== null) document.warnings.push({ line: inner.line, message: `unterminated ${inner.kind}` });
  return document;
}
