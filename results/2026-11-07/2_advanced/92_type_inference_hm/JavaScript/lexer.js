'use strict';

const keywords = new Set(['let', 'rec', 'and', 'in', 'fun', 'if', 'then', 'else', 'match', 'with', 'true', 'false', 'mod', 'val']);
const symbols = [';;', '->', '::', '||', '&&', '<=', '>=', '<>', ':', ';', '=', '<', '>', '+', '-', '*', '/', '^', '(', ')', '[', ']', ',', '|'];

function tokenize(text, file) {
  const tokens = [];
  let index = 0;
  let line = 1;
  let column = 1;
  function advance(length) {
    for (let end = index + length; index < end; index++) {
      if (text[index] === '\n') { line++; column = 1; }
      else column++;
    }
  }
  function token(kind, length, value, message) {
    tokens.push({kind, text: text.slice(index, index + length), value, message, position: {file, line, column}});
    advance(length);
  }
  while (index < text.length) {
    const character = text[index];
    if (character === ' ' || character === '\n') { advance(1); continue; }
    if (text.startsWith('(*', index)) {
      const end = text.indexOf('*)', index + 2);
      if (end === -1) { token('invalid', text.length - index, null, 'unterminated comment'); break; }
      advance(end + 2 - index);
      continue;
    }
    if (/[0-9]/.test(character)) {
      let end = index + 1;
      while (end < text.length && /[0-9]/.test(text[end])) end++;
      const value = Number(text.slice(index, end));
      if (value > 2147483647) token('invalid', end - index, null, 'integer literal too large');
      else token('int', end - index, value);
      continue;
    }
    if (/[A-Za-z_]/.test(character)) {
      let end = index + 1;
      while (end < text.length && /[A-Za-z0-9_']/.test(text[end])) end++;
      const word = text.slice(index, end);
      token(keywords.has(word) ? 'keyword' : 'name', end - index, word);
      continue;
    }
    if (character === "'" && index + 1 < text.length && /[a-z]/.test(text[index + 1])) {
      let end = index + 2;
      while (end < text.length && /[A-Za-z0-9_]/.test(text[end])) end++;
      token('typevar', end - index, text.slice(index, end));
      continue;
    }
    if (character === '"') {
      let end = index + 1;
      let value = '';
      let invalidEscape = false;
      const escapes = {n: '\n', t: '\t', '\\': '\\', '"': '"'};
      while (end < text.length && text[end] !== '"' && text[end] !== '\n') {
        if (text[end] === '\\' && end + 1 < text.length && text[end + 1] !== '\n') {
          const escaped = text[end + 1];
          if (Object.hasOwn(escapes, escaped)) value += escapes[escaped];
          else invalidEscape = true;
          end += 2;
        } else value += text[end++];
      }
      if (end === text.length || text[end] === '\n') token('invalid', end - index, null, 'unterminated string');
      else if (invalidEscape) token('invalid', end + 1 - index, null, 'invalid escape sequence');
      else token('string', end + 1 - index, value);
      continue;
    }
    const symbol = symbols.find(value => text.startsWith(value, index));
    if (symbol !== undefined) token('symbol', symbol.length, symbol);
    else token('invalid', 1, null, `illegal character '${character}'`);
  }
  tokens.push({kind: 'eof', text: '', position: {file, line, column}});
  return tokens;
}

module.exports = {tokenize};
