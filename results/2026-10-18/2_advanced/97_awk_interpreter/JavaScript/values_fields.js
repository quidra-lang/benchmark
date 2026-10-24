'use strict';

const uninitialized = { kind: 'uninitialized' };
const number = value => ({ kind: 'number', number: value === 0 ? 0 : value });
const string = value => ({ kind: 'string', string: value });
const asciiCompare = (a, b) => a < b ? -1 : a > b ? 1 : 0;

function toNumber(value) {
  if (value.kind === 'number' || value.kind === 'strnum') return value.number;
  if (value.kind === 'uninitialized') return 0;
  const found = /^[ \t\n]*([+-]?\d+)/.exec(value.string);
  return found === null ? 0 : Number(found[1]);
}

function toString(value) {
  if (value.kind === 'uninitialized') return '';
  return value.kind === 'number' ? String(value.number) : value.string;
}

function inputValue(value) {
  return /^[ \t\n]*[+-]?\d+[ \t\n]*$/.test(value) ? { kind: 'strnum', string: value, number: toNumber(string(value)) } : string(value);
}

function truth(value) { return value.kind === 'string' ? value.string !== '' : toNumber(value) !== 0; }
function compare(a, b) {
  if (a.kind !== 'string' && b.kind !== 'string') return Math.sign(toNumber(a) - toNumber(b));
  return asciiCompare(toString(a), toString(b));
}

function orderedKeys(array) {
  const integer = key => /^(0|-?[1-9]\d*)$/.exec(key)?.[0] === key;
  return Array.from(array.keys()).sort((a, b) => {
    const left = integer(a), right = integer(b);
    return left && right ? Number(a) - Number(b) : left ? -1 : right ? 1 : asciiCompare(a, b);
  });
}

function splitString(value, separator) {
  if (separator === ' ') return value.match(/[^ \t\n]+/g) || [];
  if (separator === '') return Array.from(value);
  return value === '' ? [] : value.split(separator);
}

class Fields {
  constructor(setting, fail) { this.setting = setting; this.fail = fail; this.record = string(''); this.values = new Map(); this.count = 0; }
  setRecord(value) {
    this.record = inputValue(value);
    const pieces = splitString(value, toString(this.setting('FS')));
    this.values = new Map(pieces.map((piece, i) => [i + 1, inputValue(piece)])); this.count = pieces.length;
  }
  read(index) {
    if (index === 0) return this.record;
    return index > this.count ? uninitialized : this.values.get(index) || string('');
  }
  rebuild() {
    const separator = toString(this.setting('OFS')), parts = [];
    let previous = 0;
    for (const [index, value] of Array.from(this.values).sort((a, b) => a[0] - b[0])) {
      if (separator !== '') parts.push(separator.repeat(index - previous - Number(previous === 0)));
      parts.push(toString(value)); previous = index;
    }
    if (separator !== '' && this.count > 0) parts.push(separator.repeat(this.count - previous - Number(previous === 0)));
    this.record = inputValue(parts.join(''));
  }
  write(index, value) {
    if (index === 0) { this.setRecord(toString(value)); return; }
    this.count = Math.max(this.count, index); this.values.set(index, value); this.rebuild();
  }
  resize(value, position) {
    const count = toNumber(value);
    if (count < 0) this.fail(position, 'negative NF');
    if (count < this.count) for (const index of this.values.keys()) if (index > count) this.values.delete(index);
    this.count = count;
    this.rebuild();
  }
}

function display(value) {
  if (value.kind === 'uninitialized') return '(uninitialized)';
  if (value.kind === 'number') return toString(value);
  let result = '"';
  for (const character of value.string) {
    if (character === '"') result += '\\"';
    else if (character === '\\') result += '\\\\';
    else if (character === '\n') result += '\\n';
    else if (character === '\t') result += '\\t';
    else {
      const code = character.charCodeAt(0);
      result += code >= 32 && code <= 126 ? character : '\\' + code.toString(8).padStart(3, '0');
    }
  }
  return result + '"' + (value.kind === 'strnum' ? ' (strnum)' : '');
}

module.exports = { uninitialized, number, string, toNumber, toString, inputValue, truth, compare, asciiCompare, orderedKeys, splitString, Fields, display };
