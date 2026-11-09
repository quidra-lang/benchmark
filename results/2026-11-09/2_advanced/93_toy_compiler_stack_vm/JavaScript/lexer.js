'use strict';

class CompileError extends Error {
  constructor(kind, position, message) { super(message); this.kind = kind; this.position = position; }
}

const positionCompare = (a, b) => a.line - b.line || a.column - b.column;
const KEYWORDS = new Set('int bool void true false if else while for break continue return print read'.split(' '));
const PAIRS = new Set(['<=', '>=', '==', '!=', '&&', '||']);
const letter = character => character !== undefined && /[A-Za-z_]/.test(character);
const digit = character => character !== undefined && character >= '0' && character <= '9';

function lex(lines) {
  const source = lines.map(line => line.text + '\n').join(''), tokens = [];
  let index = 0, line = lines[0].line, column = 1;
  const advance = end => {
    while (index < end) {
      if (source[index++] === '\n') { line++; column = 1; } else column++;
    }
  };
  while (index < source.length) {
    const start = index, position = { line, column }, character = source[index], pair = source.slice(index, index + 2);
    if (character === ' ' || character === '\n') { advance(index + 1); continue; }
    if (pair === '//') { advance(source.indexOf('\n', index)); continue; }
    if (pair === '/*') {
      const end = source.indexOf('*/', index + 2);
      if (end < 0) throw new CompileError('lexical', position, 'unterminated comment');
      advance(end + 2); continue;
    }
    if (letter(character)) {
      let end = index + 1;
      while (letter(source[end]) || digit(source[end])) end++;
      const text = source.slice(start, end);
      tokens.push({ kind: KEYWORDS.has(text) ? 'keyword' : 'identifier', text, position }); advance(end); continue;
    }
    if (digit(character)) {
      let end = index + 1;
      while (digit(source[end])) end++;
      const text = source.slice(start, end), value = Number(text);
      if (value > 2147483647) throw new CompileError('lexical', position, 'integer literal too large');
      tokens.push({ kind: 'integer', text, value, position }); advance(end); continue;
    }
    if (PAIRS.has(pair)) { tokens.push({ kind: 'symbol', text: pair, position }); advance(index + 2); continue; }
    if ('+-*/%<>=!(){}[],;'.includes(character)) {
      tokens.push({ kind: 'symbol', text: character, position }); advance(index + 1); continue;
    }
    throw new CompileError('lexical', position, `unexpected character '${character}'`);
  }
  const last = lines[lines.length - 1];
  tokens.push({ kind: 'end', text: '', position: { line: last.line, column: last.text.length + 1 } });
  return tokens;
}

module.exports = { CompileError, positionCompare, lex };
