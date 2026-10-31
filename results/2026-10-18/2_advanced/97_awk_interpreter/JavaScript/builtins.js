'use strict';

const { number, string, toNumber, toString } = require('./values_fields');

class RuntimeFault extends Error {
  constructor(position, message) { super(message); this.position = position; }
}
const fail = (position, message) => { throw new RuntimeFault(position, message); };
const digit = character => character !== undefined && character >= '0' && character <= '9';

function format(values, position) {
  const template = toString(values[0]);
  let result = '', index = 0, argument = 1;
  while (index < template.length) {
    if (template[index] !== '%') { result += template[index++]; continue; }
    index++;
    if (template[index] === '%') { result += '%'; index++; continue; }
    let left = false, zero = false;
    while (template[index] === '-' || template[index] === '0') { if (template[index++] === '-') left = true; else zero = true; }
    let start = index;
    while (digit(template[index])) index++;
    const width = index === start ? 0 : Number(template.slice(start, index));
    let precision = null;
    if (template[index] === '.') {
      start = ++index; while (digit(template[index])) index++;
      precision = index === start ? 0 : Number(template.slice(start, index));
    }
    const conversion = template[index++];
    if (conversion === undefined || !'discxo'.includes(conversion)) fail(position, 'invalid format');
    if (argument === values.length) fail(position, 'not enough arguments');
    const value = values[argument++];
    let body;
    if ('dixo'.includes(conversion)) {
      const numeric = toNumber(value), negative = numeric < 0, radix = conversion === 'x' ? 16 : conversion === 'o' ? 8 : 10;
      let digits = Math.abs(numeric).toString(radix);
      if (precision !== null) digits = precision === 0 && numeric === 0 ? '' : digits.padStart(precision, '0');
      body = (negative ? '-' : '') + digits;
      if (body.length < width) {
        if (left) body = body.padEnd(width, ' ');
        else if (zero && precision === null) body = (negative ? '-' : '') + digits.padStart(width - Number(negative), '0');
        else body = body.padStart(width, ' ');
      }
    } else {
      if (conversion === 's') {
        body = toString(value); if (precision !== null) body = body.slice(0, precision);
      } else if (value.kind === 'number' || value.kind === 'strnum') {
        const code = toNumber(value);
        if (code !== 10 && (code < 32 || code > 126)) fail(position, 'invalid character code');
        body = String.fromCharCode(code);
      } else body = toString(value).slice(0, 1);
      body = left ? body.padEnd(width, ' ') : body.padStart(width, ' ');
    }
    result += body;
  }
  return result;
}

function builtin(name, values, position) {
  if (name === 'sprintf') return string(format(values, position));
  if (name === 'int') return number(toNumber(values[0]));
  const value = toString(values[0]);
  if (name === 'substr') {
    const start = toNumber(values[1]), end = values.length === 3 ? start + toNumber(values[2]) : value.length + 1;
    const first = Math.max(1, start), limit = Math.min(value.length + 1, end);
    return string(limit > first ? value.slice(first - 1, limit - 1) : '');
  }
  if (name === 'index') {
    const search = toString(values[1]); return number(search === '' ? 0 : value.indexOf(search) + 1);
  }
  return string(name === 'toupper' ? value.replace(/[a-z]/g, character => character.toUpperCase()) : value.replace(/[A-Z]/g, character => character.toLowerCase()));
}

module.exports = { RuntimeFault, fail, format, builtin };
