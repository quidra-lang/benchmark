'use strict';

const punctuators = new Set([
  '...', '<<=', '>>=', '->', '++', '--', '<<', '>>', '<=', '>=', '==', '!=',
  '&&', '||', '*=', '/=', '%=', '+=', '-=', '&=', '^=', '|=', '##',
  '[', ']', '(', ')', '{', '}', '.', '&', '*', '+', '-', '~', '!', '/', '%',
  '<', '>', '^', '|', '?', ':', ';', '=', ',', '#',
]);

function punct(token, spelling) {
  return token?.kind === 'punctuator' && token.spelling === spelling;
}

function copy(token) {
  return {...token, hide: new Set(token.hide)};
}

function readBasic(source, start = 0) {
  const first = source[start];
  if (first === undefined) return null;
  let end = start + 1;
  let kind;
  if (/[A-Za-z_]/.test(first)) {
    while (/[A-Za-z0-9_]/.test(source[end] ?? '')) end++;
    kind = 'identifier';
  } else if (/[0-9]/.test(first) || first === '.' && /[0-9]/.test(source[end] ?? '')) {
    while (end < source.length) {
      if (/[eEpP]/.test(source[end]) && /[+-]/.test(source[end + 1] ?? '')) end += 2;
      else if (/[A-Za-z0-9_.]/.test(source[end])) end++;
      else break;
    }
    kind = 'number';
  } else if (first === "'" || first === '"') {
    let cursor = end;
    while (cursor < source.length && source[cursor] !== '\n') {
      if (source[cursor] === first) {
        end = cursor + 1;
        kind = first === "'" ? 'character' : 'string';
        break;
      }
      if (source[cursor] === '\\' && source[cursor + 1] !== '\n') cursor += 2;
      else cursor++;
    }
  }
  if (!kind) {
    kind = 'other';
    for (const length of [3, 2, 1]) {
      const spelling = source.slice(start, start + length);
      if (spelling.length === length && punctuators.has(spelling)) {
        end = start + length;
        kind = 'punctuator';
        break;
      }
    }
  }
  return {kind, spelling: source.slice(start, end), length: end - start};
}

function scan(source, physical) {
  const lines = [];
  let tokens = [];
  let startLine = 1;
  let separated = true;
  for (let index = 0; index < source.length;) {
    if (source[index] === ' ') {
      separated = true;
      index++;
    } else if (source[index] === '\n') {
      const endLine = physical[index++];
      const name = punct(tokens[0], '#') && tokens[1]?.kind === 'identifier'
        ? tokens[1].spelling : null;
      lines.push({tokens, startLine, endLine, name});
      tokens = [];
      startLine = endLine + 1;
      separated = true;
    } else if (source.startsWith('/*', index)) {
      const closing = source.indexOf('*/', index + 2);
      index = closing < 0 ? source.length : closing + 2;
      separated = true;
    } else if (source.startsWith('//', index)) {
      const end = source.indexOf('\n', index + 2);
      index = end < 0 ? source.length : end;
      separated = true;
    } else {
      let read;
      if (tokens.length === 2 && tokens[0].spelling === '#'
          && tokens[1].spelling === 'include' && source[index] === '<') {
        const closing = source.indexOf('>', index + 1);
        const newline = source.indexOf('\n', index + 1);
        if (closing >= 0 && (newline < 0 || closing < newline)) {
          read = {kind: 'header', spelling: source.slice(index, closing + 1), length: closing + 1 - index};
        }
      }
      read ??= readBasic(source, index);
      tokens.push({kind: read.kind, spelling: read.spelling, line: physical[index],
        space: separated, hide: new Set()});
      index += read.length;
      separated = false;
    }
  }
  return {lines, remainder: tokens};
}

function lexFile(text) {
  const characters = [];
  const physical = [];
  let line = 1;
  for (let index = 0; index < text.length; index++) {
    if (text[index] === '\\' && text[index + 1] === '\n') {
      index++;
      line++;
    } else {
      characters.push(text[index]);
      physical.push(line);
      if (text[index] === '\n') line++;
    }
  }
  return {lines: scan(characters.join(''), physical).lines, physicalLines: line - 1};
}

function lexDefinition(text) {
  return scan(text, Array(text.length).fill(1)).remainder;
}

function render(tokens) {
  let result = '';
  for (let index = 0; index < tokens.length; index++) {
    if (index && tokens[index].space) result += ' ';
    result += tokens[index].spelling;
  }
  return result;
}

function singleToken(text) {
  if (text.startsWith('//') || text.startsWith('/*')) return null;
  const token = readBasic(text);
  return token?.length === text.length ? token.kind : null;
}

module.exports = {punct, copy, readBasic, lexFile, lexDefinition, render, singleToken};
