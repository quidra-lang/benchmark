'use strict';

const types = ['ABS32', 'REL32', 'ABS16', 'HI16', 'LO16', 'GPREL16', 'CALL24'];
const specifications = {
  ABS32: {width: 4, lower: -(2 ** 31), upper: 2 ** 32},
  REL32: {width: 4, lower: -(2 ** 31), upper: 2 ** 31},
  ABS16: {width: 2, lower: -(2 ** 15), upper: 2 ** 16},
  HI16: {width: 2, lower: -(2 ** 31), upper: 2 ** 32},
  LO16: {width: 2, lower: null, upper: null},
  GPREL16: {width: 2, lower: -(2 ** 15), upper: 2 ** 15},
  CALL24: {width: 3, lower: -(2 ** 25), upper: 2 ** 25}
};

function mod(value, divisor) {
  return ((value % divisor) + divisor) % divisor;
}

function inRange(type, value) {
  const range = specifications[type];
  return range.lower === null || (range.lower <= value && value < range.upper);
}

function calculate(type, symbol, addend, position, gp) {
  let value = symbol + addend;
  if (type === 'REL32' || type === 'CALL24') value -= position;
  else if (type === 'GPREL16') value -= gp;
  const width = specifications[type].width;
  let field;
  if (type === 'HI16') field = mod(Math.floor((mod(value, 2 ** 32) + 32768) / 65536), 65536);
  else if (type === 'CALL24') field = mod(Math.floor(value / 4), 2 ** 24);
  else field = mod(value, 2 ** (8 * width));
  return {value, field, width, overflow: !inRange(type, value)};
}

function isUnpaired(relocations, index) {
  const current = relocations[index];
  if (current.type !== 'HI16') return false;
  const next = relocations[index + 1];
  return next === undefined || next.type !== 'LO16' || next.symbol !== current.symbol || next.addend !== current.addend;
}

function littleEndian(value, width) {
  const data = Buffer.alloc(width);
  for (let index = 0; index < width; index++) {
    data[index] = mod(value, 256);
    value = Math.floor(value / 256);
  }
  return data;
}

module.exports = {types, specifications, mod, inRange, calculate, isUnpaired, littleEndian};
