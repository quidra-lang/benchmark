import { strictBase64 } from './mime.ts';

export interface SourceLine { text: string; number: number }
export interface Field { name: string; value: string }
export interface Header { fields: Field[]; invalid: number[] }
export const strip = (text: string) => text.replace(/^[ \t]+|[ \t]+$/g, '');
export const collapse = (text: string) => strip(text.replace(/[ \t]+/g, ' '));
export function parseHeaders(lines: SourceLine[]): Header {
  const fields: Field[] = [], invalid: number[] = [];
  let previous: Field | undefined;
  for (const line of lines) {
    if (/^[ \t]/.test(line.text)) {
      if (previous) previous.value += line.text;
      else invalid.push(line.number);
      continue;
    }
    const colon = line.text.indexOf(':');
    if (colon <= 0 || /[^\x21-\x7e]/.test(line.text.slice(0, colon))) {
      invalid.push(line.number); previous = undefined;
    } else {
      previous = { name: line.text.slice(0, colon).toLowerCase(), value: line.text.slice(colon + 1) };
      fields.push(previous);
    }
  }
  for (const field of fields) field.value = strip(field.value);
  return { fields, invalid };
}
export function field(fields: Field[], name: string): string | undefined { return fields.find(f => f.name === name.toLowerCase())?.value; }
export function removeComments(text: string): string | undefined {
  let depth = 0, output = '';
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (depth === 0) {
      if (c === '(') { depth = 1; output += ' '; } else output += c;
    } else if (c === '\\') i++;
    else if (c === '(') depth++;
    else if (c === ')') depth--;
  }
  return depth === 0 ? output : undefined;
}
export interface DecodedWord { text: string; success: boolean; error: boolean }
export function decodeWord(word: string): DecodedWord {
  const original = { text: word, success: false, error: false };
  if (word.length < 4 || !word.startsWith('=?') || !word.endsWith('?=')) return original;
  const pieces = word.slice(2, -2).split('?');
  if (pieces.length !== 3 || pieces.some(piece => piece === '')) return original;
  const [charset, encoding, data] = pieces;
  let decoded: string | undefined;
  if (charset.toLowerCase() === 'us-ascii') {
    if (encoding.toLowerCase() === 'b') decoded = strictBase64(data);
    else if (encoding.toLowerCase() === 'q') {
      decoded = '';
      for (let i = 0; i < data.length; i++) {
        if (data[i] === '_') decoded += ' ';
        else if (data[i] === '=') {
          const hex = data.slice(i + 1, i + 3);
          if (!/^[0-9A-Fa-f]{2}$/.test(hex)) { decoded = undefined; break; }
          decoded += String.fromCharCode(parseInt(hex, 16)); i += 2;
        } else decoded += data[i];
      }
    }
  }
  if (decoded === undefined || /[^\x20-\x7e]/.test(decoded)) return { ...original, error: true };
  return { text: decoded, success: true, error: false };
}
export function unstructured(text: string): { text: string; error: boolean } {
  const words = strip(text).split(/[ \t]+/).filter(Boolean);
  let output = '', previousSuccess = false, error = false;
  words.forEach((word, i) => {
    const decoded = decodeWord(word);
    if (i && !(previousSuccess && decoded.success)) output += ' ';
    output += decoded.text; previousSuccess = decoded.success; error ||= decoded.error;
  });
  return { text: collapse(output), error };
}
export interface Token { kind: string; text: string; preceded: boolean }
export function tokenize(text: string, variant: 'address' | 'mime'): Token[] | undefined {
  const tokens: Token[] = [];
  const specials = variant === 'address' ? '<>:;@,.' : '/;=';
  const isWord = (c: string) => variant === 'address' ? /^[A-Za-z0-9!#$%&'*+\/=?^_`{|}~-]$/.test(c) :
    c.charCodeAt(0) >= 33 && c.charCodeAt(0) <= 126 && !'()<>@,;:\\"/[]?='.includes(c);
  let i = 0, preceded = false;
  while (i < text.length) {
    const c = text[i];
    if (c === ' ' || c === '\t') { preceded = true; i++; continue; }
    if (c === '(') {
      preceded = true; let depth = 1; i++;
      while (i < text.length && depth > 0) {
        if (text[i] === '\\') i += 2;
        else { if (text[i] === '(') depth++; else if (text[i] === ')') depth--; i++; }
      }
      if (depth) return undefined;
      continue;
    }
    let kind: string, value = '';
    if (c === '"') {
      kind = 'quoted'; i++;
      while (i < text.length && text[i] !== '"') {
        if (text[i] === '\\') { i++; if (i >= text.length) return undefined; }
        value += text[i++];
      }
      if (i >= text.length) return undefined;
      i++;
    } else if (specials.includes(c)) { kind = c; value = c; i++; }
    else if (isWord(c)) {
      kind = 'word';
      while (i < text.length && isWord(text[i])) value += text[i++];
    } else return undefined;
    tokens.push({ kind, text: value, preceded }); preceded = false;
  }
  return tokens;
}
export interface ParameterValue { type: string; subtype: string; parameters: Map<string, string> }
export function parameters(text: string, subtype: boolean): ParameterValue | undefined {
  const tokens = tokenize(text, 'mime');
  if (!tokens || tokens[0]?.kind !== 'word') return undefined;
  const value: ParameterValue = { type: tokens[0].text.toLowerCase(), subtype: '', parameters: new Map() };
  let i = 1;
  if (subtype) {
    if (tokens[i]?.kind !== '/' || tokens[i + 1]?.kind !== 'word') return undefined;
    value.subtype = tokens[i + 1].text.toLowerCase(); i += 2;
  }
  while (i < tokens.length) {
    if (tokens[i]?.kind !== ';' || tokens[i + 1]?.kind !== 'word' || tokens[i + 2]?.kind !== '=' ||
      (tokens[i + 3]?.kind !== 'word' && tokens[i + 3]?.kind !== 'quoted')) return undefined;
    const name = tokens[i + 1].text.toLowerCase();
    if (!value.parameters.has(name)) value.parameters.set(name, tokens[i + 3].text);
    i += 4;
  }
  return value;
}
