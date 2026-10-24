'use strict';

const { DecodingError } = require('./bitio');

function tokenize(data, offsetBits, lengthBits) {
  const window = 2 ** offsetBits;
  const lookahead = 2 ** lengthBits + 2;
  const previous = Array(data.length).fill(-1);
  const latest = new Map();
  // Only equal three-byte prefixes can produce a match token.
  for (let index = 0; index + 2 < data.length; index++) {
    const key = data[index] * 65536 + data[index + 1] * 256 + data[index + 2];
    previous[index] = latest.get(key) ?? -1;
    latest.set(key, index);
  }
  const tokens = [];
  let position = 0;
  while (position < data.length) {
    const maximum = Math.min(lookahead, data.length - position);
    let bestLength = 2;
    let bestDistance = 0;
    let candidate = maximum >= 3 ? previous[position] : -1;
    // Previous occurrences are visited from nearest to farthest, preserving ties.
    while (candidate >= 0 && position - candidate <= window) {
      const distance = position - candidate;
      let length = 3;
      while (length < maximum && data[position + length] === data[position + length - distance]) length++;
      if (length > bestLength) {
        bestLength = length;
        bestDistance = distance;
      }
      if (length === maximum) break;
      candidate = previous[candidate];
    }
    if (bestDistance > 0) {
      tokens.push({ distance: bestDistance, length: bestLength });
      position += bestLength;
    } else tokens.push({ literal: data[position++] });
  }
  return tokens;
}

function copyMatch(output, distance, length, originalLength) {
  if (distance > output.length) throw new DecodingError('bad_offset');
  if (output.length + length > originalLength) throw new DecodingError('overrun');
  for (let index = 0; index < length; index++) output.push(output[output.length - distance]);
}

module.exports = { tokenize, copyMatch };
