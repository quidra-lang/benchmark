'use strict';

function buildSquare(key) {
  const seen = new Set();
  const square = [];
  for (const character of key + 'ABCDEFGHIKLMNOPQRSTUVWXYZ') {
    if (!seen.has(character)) {
      seen.add(character);
      square.push(character);
    }
  }
  return square.join('');
}

function validCiphertext(text) {
  const normalized = text.replaceAll('J', 'I');
  if (normalized.length % 2 !== 0) return false;
  for (let index = 0; index < normalized.length; index += 2) {
    if (normalized[index] === normalized[index + 1]) return false;
  }
  return true;
}

function preparePairs(text) {
  const pairs = [];
  let index = 0;
  while (index < text.length) {
    const first = text[index];
    if (index + 1 < text.length && first !== text[index + 1]) {
      pairs.push(first + text[index + 1]);
      index += 2;
    } else {
      pairs.push(first + (first === 'X' ? 'Q' : 'X'));
      index++;
    }
  }
  return pairs;
}

function playfair(text, key, decrypt) {
  const square = buildSquare(key);
  const locations = new Map();
  for (let index = 0; index < square.length; index++) {
    locations.set(square[index], [Math.floor(index / 5), index % 5]);
  }
  const normalized = text.replaceAll('J', 'I');
  const pairs = [];
  if (decrypt) {
    for (let index = 0; index < normalized.length; index += 2) {
      pairs.push(normalized.slice(index, index + 2));
    }
  } else {
    pairs.push(...preparePairs(normalized));
  }
  const step = decrypt ? 4 : 1;
  const output = [];
  for (const pair of pairs) {
    const [rowA, columnA] = locations.get(pair[0]);
    const [rowB, columnB] = locations.get(pair[1]);
    if (rowA === rowB) {
      output.push(square[rowA * 5 + (columnA + step) % 5]);
      output.push(square[rowB * 5 + (columnB + step) % 5]);
    } else if (columnA === columnB) {
      output.push(square[((rowA + step) % 5) * 5 + columnA]);
      output.push(square[((rowB + step) % 5) * 5 + columnB]);
    } else {
      output.push(square[rowA * 5 + columnB]);
      output.push(square[rowB * 5 + columnA]);
    }
  }
  return output.join('');
}

module.exports = {buildSquare, validCiphertext, preparePairs, playfair};
