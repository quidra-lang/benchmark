import { logicalLines, type RawValue, type Segment } from './lexer.ts';

export type Statement =
  | { kind: 'assign' | 'append'; key: string; value: RawValue; line: number }
  | { kind: 'unset'; key: string; line: number }
  | { kind: 'inherit'; section: string; parent: string; line: number }
  | { kind: 'include'; document: string; line: number };
export interface ParseDiagnostic { line: number; code: string; message: string }
export interface ParsedDocument { statements: Statement[]; diagnostics: ParseDiagnostic[] }
const NAME = /^[a-z][a-z0-9_]*$/;
const SECTION = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/;
const trimSpaces = (text: string) => text.replace(/^ +| +$/g, '');

function trimSegments(segments: Segment[]): Segment[] {
  const result = segments.map(part => ({ ...part }));
  if (result.length && !result[0].quoted) result[0].text = result[0].text.replace(/^ +/, '');
  const last = result.at(-1);
  if (last && !last.quoted) last.text = last.text.replace(/ +$/, '');
  while (result.length && !result[0].quoted && result[0].text === '') result.shift();
  while (result.length && !result[result.length - 1].quoted && result[result.length - 1].text === '') result.pop();
  return result;
}

export function parseDocument(text: string): ParsedDocument {
  const statements: Statement[] = [], diagnostics: ParseDiagnostic[] = [], previous = new Map<string, number>();
  let current: string | null = null, base: string | null = null;
  const report = (line: number, code: string, message: string) => diagnostics.push({ line, code, message });
  for (const logical of logicalLines(text)) {
    const { line, error } = logical;
    if (error) { report(line, error.code, error.message); continue; }
    const parts = trimSegments(logical.segments);
    if (!parts.length) continue;
    const quoted = parts.some(part => part.quoted), plain = parts.map(part => part.text).join('');
    const first = parts[0].quoted ? null : parts[0].text[0];
    if (first === '[') {
      const interior = plain.slice(1, -1), colon = interior.indexOf(':');
      const name = trimSpaces(colon < 0 ? interior : interior.slice(0, colon));
      const parent = colon < 0 ? null : trimSpaces(interior.slice(colon + 1));
      const relative = name.startsWith('.');
      if (quoted || !plain.endsWith(']') || !SECTION.test(relative ? name.slice(1) : name)
          || (parent !== null && !SECTION.test(parent))) {
        report(line, 'E_SECTION', 'invalid section header'); current = null;
      } else if (relative && base === null) {
        report(line, 'E_SECTION', 'relative section without base'); current = null;
      } else {
        current = relative ? base + name : name;
        if (!relative) base = name;
        if (parent !== null) statements.push({ kind: 'inherit', section: current, parent, line });
      }
      continue;
    }
    if (first === '@') {
      const words = plain.split(/ +/);
      if (quoted || words.length !== 2 || !['@include', '@unset'].includes(words[0]) || !NAME.test(words[1])) {
        report(line, 'E_SYNTAX', 'invalid directive');
      } else if (words[0] === '@include') statements.push({ kind: 'include', document: words[1], line });
      else if (current === null) report(line, 'E_NO_SECTION', 'no current section');
      else statements.push({ kind: 'unset', key: `${current}.${words[1]}`, line });
      continue;
    }
    const at = parts.findIndex(part => !part.quoted && part.text.includes('='));
    if (at < 0) { report(line, 'E_SYNTAX', 'invalid line'); continue; }
    if (parts.slice(0, at).some(part => part.quoted)) { report(line, 'E_SYNTAX', 'invalid key'); continue; }
    const equals = parts[at].text.indexOf('=');
    let key = trimSpaces(parts.slice(0, at).map(part => part.text).join('') + parts[at].text.slice(0, equals));
    const append = key.endsWith('+');
    if (append) key = key.slice(0, -1).replace(/ +$/, '');
    if (!NAME.test(key)) { report(line, 'E_SYNTAX', 'invalid key'); continue; }
    const tail = trimSegments([{ ...parts[at], text: parts[at].text.slice(equals + 1) }, ...parts.slice(at + 1)]);
    const hasQuotes = tail.some(part => part.quoted);
    if (hasQuotes && (tail.length !== 1 || !tail[0].quoted)) { report(line, 'E_SYNTAX', 'invalid value'); continue; }
    if (current === null) { report(line, 'E_NO_SECTION', 'no current section'); continue; }
    key = `${current}.${key}`;
    const value: RawValue = hasQuotes ? { text: tail[0].text, literals: tail[0].literals }
      : { text: tail.map(part => part.text).join(''), literals: new Set() };
    if (!append) {
      if (previous.has(key)) report(line, 'W_DUPLICATE', `${key} already set at line ${previous.get(key)}`);
      previous.set(key, line);
    }
    statements.push({ kind: append ? 'append' : 'assign', key, value, line });
  }
  return { statements, diagnostics };
}
