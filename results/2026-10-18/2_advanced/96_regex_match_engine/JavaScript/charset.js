'use strict';

function digit(code) { return code >= 48 && code <= 57; }
function letter(code) { return (code >= 65 && code <= 90) || (code >= 97 && code <= 122); }
function word(code) { return letter(code) || digit(code) || code === 95; }
function swapCase(code) { return code >= 65 && code <= 90 ? code + 32 : code - 32; }

const digits = new Set();
const words = new Set();
const spaces = new Set([9, 10, 11, 12, 13, 32]);
for (let code = 0; code < 128; code++) {
  if (digit(code)) digits.add(code);
  if (word(code)) words.add(code);
}

function complement(set) {
  const result = new Set();
  for (let code = 0; code < 128; code++) if (!set.has(code)) result.add(code);
  return result;
}

function shorthand(character) {
  const lower = character === 'd' || character === 'D' ? 'd' : character === 'w' || character === 'W' ? 'w' : 's';
  const set = lower === 'd' ? digits : lower === 'w' ? words : spaces;
  return {set, negated: character !== lower};
}

function same(first, second, flags) {
  return first === second || (flags.includes('i') && letter(first) && swapCase(first) === second);
}

function classMatches(set, negated, code, flags) {
  const present = set.has(code) || (flags.includes('i') && letter(code) && set.has(swapCase(code)));
  return present !== negated;
}

function consumes(instruction, text, position, flags) {
  if (position >= text.length) return false;
  const code = text.charCodeAt(position);
  if (instruction.op === 'CHAR') return same(code, instruction.character, flags);
  if (instruction.op === 'ANY') return flags.includes('s') || code !== 10;
  return classMatches(instruction.set, instruction.negated, code, flags);
}

function assertion(kind, text, position, flags) {
  if (kind === 'BOL') return position === 0 || (flags.includes('m') && text[position - 1] === '\n');
  if (kind === 'EOL') return position === text.length || (flags.includes('m') && text[position] === '\n');
  const before = position > 0 && word(text.charCodeAt(position - 1));
  const after = position < text.length && word(text.charCodeAt(position));
  return kind === 'WORD' ? before !== after : before === after;
}

module.exports = {digit, letter, word, swapCase, digits, words, spaces, complement, shorthand,
  same, classMatches, consumes, assertion};
