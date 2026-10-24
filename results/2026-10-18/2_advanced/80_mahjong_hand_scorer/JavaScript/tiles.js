'use strict';

const suits = 'mpsz';
const winds = 'ESWN';
const orphans = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33];
const green = new Set([19, 20, 21, 23, 25, 32]);

function parse(text, allowEmpty = false) {
  if (allowEmpty && text === '-') return [];
  if (text.length === 0) return null;
  const result = [];
  let position = 0;
  while (position < text.length) {
    const start = position;
    while (position < text.length && text[position] >= '0' && text[position] <= '9') position++;
    if (position === start || position === text.length) return null;
    const suit = suits.indexOf(text[position]);
    if (suit === -1) return null;
    for (let index = start; index < position; index++) {
      const digit = Number(text[index]);
      if (suit === 3 && (digit < 1 || digit > 7)) return null;
      result.push({kind: 9 * suit + (digit === 0 ? 5 : digit) - 1, red: digit === 0});
    }
    position++;
  }
  return result;
}

function name(kind) {
  return String(kind % 9 + 1) + suits[Math.floor(kind / 9)];
}

function block(kinds) {
  const sorted = kinds.slice().sort((a, b) => a - b);
  return sorted.map(kind => kind % 9 + 1).join('') + suits[Math.floor(sorted[0] / 9)];
}

function counts(values) {
  const result = Array(34).fill(0);
  for (const tile of values) result[tile.kind]++;
  return result;
}

function honor(kind) {
  return kind >= 27;
}

function terminal(kind) {
  return kind < 27 && (kind % 9 === 0 || kind % 9 === 8);
}

function yaochuu(kind) {
  return honor(kind) || terminal(kind);
}

function simple(kind) {
  return kind < 27 && !terminal(kind);
}

function nextIndicator(kind) {
  if (kind < 27) return 9 * Math.floor(kind / 9) + (kind + 1) % 9;
  if (kind < 31) return 27 + (kind - 26) % 4;
  return 31 + (kind - 30) % 3;
}

function windKind(wind) {
  return 27 + winds.indexOf(wind);
}

module.exports = {suits, winds, orphans, green, parse, name, block, counts,
  honor, terminal, yaochuu, simple, nextIndicator, windKind};
