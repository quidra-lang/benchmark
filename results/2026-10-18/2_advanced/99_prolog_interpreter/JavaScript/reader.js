'use strict';

const terms = require('./terms');
const symbolCharacters = new Set('+-*/\\^<>=~:.?@#&$');
const infix = new Map();
for (const [priority, association, names] of [
  [1200, 'xfx', [':-']], [1100, 'xfy', [';']], [1050, 'xfy', ['->']], [1000, 'xfy', [',']],
  [700, 'xfx', ['=', '\\=', '==', '\\==', 'is', '=:=', '=\\=', '<', '>', '=<', '>=', '=..']],
  [500, 'yfx', ['+', '-']], [400, 'yfx', ['*', '/', '//', 'mod', 'rem']]
]) {
  for (const name of names) infix.set(name, {priority,
    left: association === 'yfx' ? priority : priority - 1,
    right: association === 'xfy' ? priority : priority - 1});
}
const prefix = new Map([['\\+', 900], ['-', 200]]);
const operatorNames = new Set([...infix.keys(), ...prefix.keys()]);

function tokenize(text, file, startColumn = 1) {
  const tokens = [];
  let index = 0;
  let line = 1;
  let column = startColumn;
  let whitespace = true;
  function advance(length) {
    const end = index + length;
    while (index < end) {
      if (text[index++] === '\n') { line++; column = 1; }
      else column++;
    }
  }
  function emit(kind, length, value = null, quoted = false, message = null) {
    tokens.push({kind, text: text.slice(index, index + length), value, quoted, message,
      whitespace, position: {file, line, column}});
    advance(length);
    whitespace = false;
  }
  while (index < text.length) {
    const character = text[index];
    if (character === ' ' || character === '\n') { advance(1); whitespace = true; continue; }
    if (character === '%') {
      let end = index;
      while (end < text.length && text[end] !== '\n') end++;
      advance(end - index);
      whitespace = true;
      continue;
    }
    if (/[0-9]/.test(character)) {
      let end = index + 1;
      while (end < text.length && /[0-9]/.test(text[end])) end++;
      const value = Number(text.slice(index, end));
      if (value > 2147483647) emit('invalid', end - index, null, false, 'integer too large');
      else emit('integer', end - index, value);
    } else if (/[A-Za-z_]/.test(character)) {
      let end = index + 1;
      while (end < text.length && /[A-Za-z0-9_]/.test(text[end])) end++;
      emit(/[a-z]/.test(character) ? 'name' : 'variable', end - index, text.slice(index, end));
    } else if (symbolCharacters.has(character)) {
      let end = index + 1;
      while (end < text.length && symbolCharacters.has(text[end])) end++;
      const word = text.slice(index, end);
      const ending = word === '.' && (end === text.length || [' ', '\n', '%'].includes(text[end]));
      emit(ending ? 'end' : 'name', end - index, word);
    } else if (character === '!' || character === ';') emit('name', 1, character);
    else if (',|()[]'.includes(character)) emit('punctuation', 1, character);
    else if (character === "'") {
      let end = index + 1;
      let value = '';
      let invalid = false;
      let closed = false;
      const escapes = {n: '\n', t: '\t', '\\': '\\', "'": "'"};
      while (end < text.length && text[end] !== '\n') {
        if (text[end] === "'") {
          if (text[end + 1] === "'") { value += "'"; end += 2; }
          else { end++; closed = true; break; }
        } else if (text[end] === '\\') {
          if (end + 1 === text.length || text[end + 1] === '\n') end++;
          else {
            if (Object.hasOwn(escapes, text[end + 1])) value += escapes[text[end + 1]];
            else invalid = true;
            end += 2;
          }
        } else value += text[end++];
      }
      if (!closed) emit('invalid', end - index, null, false, 'unterminated quoted atom');
      else if (invalid) emit('invalid', end - index, null, false, 'undefined escape sequence');
      else emit('name', end - index, value, true);
    } else emit('invalid', 1, null, false, `illegal character '${character}'`);
  }
  tokens.push({kind: 'eof', text: '', value: null, quoted: false, whitespace,
    position: {file, line, column}});
  return tokens;
}

function syntaxMessage(token) {
  if (token.kind === 'invalid') return token.message;
  if (token.kind === 'eof') return 'unexpected end of file';
  if (token.kind === 'end') return 'unexpected end of clause';
  if (token.kind === 'name' && !token.quoted && infix.has(token.value)) return 'operator priority clash';
  return `unexpected "${token.text}"`;
}

class ParseError extends Error {
  constructor(token, index, message = syntaxMessage(token)) {
    super(message);
    Object.assign(this, {token, index});
  }
}

class Reader {
  constructor(tokens) { this.tokens = tokens; this.index = 0; this.variables = new Map(); }
  current() { return this.tokens[this.index]; }
  fail(token = this.current(), index = this.index, message) { throw new ParseError(token, index, message); }
  punctuation(value) { return this.current().kind === 'punctuation' && this.current().value === value; }
  take(value) {
    if (!this.punctuation(value)) return false;
    this.index++;
    return true;
  }
  expect(value) { if (!this.take(value)) this.fail(); }
  variable(token) {
    let record = this.variables.get(token.value);
    if (record === undefined) {
      record = {name: token.value, count: 0, variable: terms.variable()};
      this.variables.set(token.value, record);
    }
    record.count++;
    return token.value === '_' ? terms.variable() : record.variable;
  }
  canStart(token) {
    if (token.kind === 'integer' || token.kind === 'variable') return true;
    if (token.kind === 'punctuation') return token.value === '(' || token.value === '[';
    return token.kind === 'name' && (token.quoted || !infix.has(token.value) || prefix.has(token.value));
  }
  infixToken(token) {
    return (token.kind === 'name' && !token.quoted && infix.has(token.value)) ||
      (token.kind === 'punctuation' && token.value === ',');
  }
  term(limit) {
    // Parentheses can nest far deeper than the resulting term, so parsing uses continuations.
    const pending = [{kind: 'read', limit}];
    let result;
    while (pending.length > 0) {
      const frame = pending.pop();
      if (frame.kind === 'infix') {
        const token = this.current();
        if (!this.infixToken(token)) continue;
        const operator = infix.get(token.value);
        if (operator.priority > frame.limit || result.priority > operator.left) continue;
        this.index++;
        pending.push(frame, {kind: 'combine', name: token.value, left: result.term, priority: operator.priority},
          {kind: 'read', limit: operator.right});
        continue;
      }
      if (frame.kind === 'combine') {
        result = {term: terms.compound(frame.name, [frame.left, result.term]), priority: frame.priority};
        continue;
      }
      if (frame.kind === 'parenthesis') {
        this.expect(')');
        result = {term: result.term, priority: 0};
        continue;
      }
      if (frame.kind === 'prefix') {
        result = {term: terms.compound(frame.name, [result.term]), priority: frame.priority};
        continue;
      }
      if (frame.kind === 'arguments' || frame.kind === 'list') {
        frame.elements.push(result.term);
        if (this.take(',')) pending.push(frame, {kind: 'read', limit: 999});
        else if (frame.kind === 'arguments') {
          this.expect(')');
          result = {term: terms.compound(frame.name, frame.elements), priority: 0};
        } else if (this.take('|')) pending.push({kind: 'tail', elements: frame.elements}, {kind: 'read', limit: 999});
        else {
          this.expect(']');
          result = {term: terms.list(frame.elements), priority: 0};
        }
        continue;
      }
      if (frame.kind === 'tail') {
        this.expect(']');
        result = {term: terms.list(frame.elements, result.term), priority: 0};
        continue;
      }
      pending.push({kind: 'infix', limit: frame.limit});
      const index = this.index;
      const token = this.current();
      this.index++;
      if (token.kind === 'integer') result = {term: terms.integer(token.value), priority: 0};
      else if (token.kind === 'variable') result = {term: this.variable(token), priority: 0};
      else if (token.kind === 'punctuation' && token.value === '(') {
        pending.push({kind: 'parenthesis'}, {kind: 'read', limit: 1200});
      } else if (token.kind === 'punctuation' && token.value === '[') {
        if (this.take(']')) result = {term: terms.empty, priority: 0};
        else pending.push({kind: 'list', elements: []}, {kind: 'read', limit: 999});
      } else if (token.kind === 'name') {
        if (this.punctuation('(') && !this.current().whitespace) {
          this.index++;
          pending.push({kind: 'arguments', name: token.value, elements: []}, {kind: 'read', limit: 999});
        } else if (!token.quoted && token.value === '-' && this.current().kind === 'integer' && !this.current().whitespace) {
          result = {term: terms.integer(-this.tokens[this.index++].value), priority: 0};
        } else if (!token.quoted && prefix.has(token.value) && this.canStart(this.current())) {
          const priority = prefix.get(token.value);
          if (priority > frame.limit) this.fail(token, index, 'operator priority clash');
          pending.push({kind: 'prefix', name: token.value, priority}, {kind: 'read', limit: priority});
        } else result = {term: terms.atom(token.value), priority: 0};
      } else this.fail(token, index);
    }
    return result;
  }
  clause(query = false) {
    this.variables = new Map();
    const line = this.current().position.line;
    const term = this.term(1200).term;
    if (this.current().kind !== 'end') this.fail();
    this.index++;
    if (query && this.current().kind !== 'eof') this.fail();
    return {term, line, variables: [...this.variables.values()]};
  }
  recover(error) {
    this.index = error.index;
    while (this.current().kind !== 'end' && this.current().kind !== 'eof') this.index++;
    if (this.current().kind === 'end') this.index++;
  }
}

module.exports = {symbolCharacters, infix, prefix, operatorNames, tokenize, syntaxMessage, ParseError, Reader};
