'use strict';

function character(code) {
  if (code >= 33 && code <= 126 && ![92, 93, 94, 45].includes(code)) return String.fromCharCode(code);
  return '\\x' + code.toString(16).toUpperCase().padStart(2, '0');
}

function setNotation(set, negated = false) {
  const parts = [];
  for (let start = 0; start < 128; start++) {
    if (!set.has(start)) continue;
    let end = start;
    while (end + 1 < 128 && set.has(end + 1)) end++;
    if (end === start) parts.push(character(start));
    else if (end === start + 1) parts.push(character(start), character(end));
    else parts.push(character(start) + '-' + character(end));
    start = end;
  }
  return '[' + (negated ? '^' : '') + parts.join('') + ']';
}

function instruction(value) {
  if (value.op === 'CHAR') return 'CHAR ' + character(value.character);
  if (value.op === 'CLASS') return 'CLASS ' + setNotation(value.set, value.negated);
  if (value.op === 'SPLIT') return `SPLIT ${value.x}, ${value.y}`;
  if (value.op === 'JMP') return 'JMP ' + value.x;
  if (value.op === 'SAVE' || value.op === 'BACKREF') return value.op + ' ' + value.group;
  if (value.op === 'ASSERT') return 'ASSERT ' + value.assertion;
  if (value.op === 'LOOK') return `LOOK ${value.kind} ${value.x}`;
  return value.op;
}

function quote(value) {
  let result = '"';
  for (const character_ of value) {
    if (character_ === '\\') result += '\\\\';
    else if (character_ === '"') result += '\\"';
    else if (character_ === '\n') result += '\\n';
    else if (character_ === '\t') result += '\\t';
    else result += character_;
  }
  return result + '"';
}

module.exports = {character, setNotation, instruction, quote};
