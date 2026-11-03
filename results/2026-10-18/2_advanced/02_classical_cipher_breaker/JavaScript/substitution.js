'use strict';

const {letterValue} = require('./scoring');

function mod(value, modulus) {
  return ((value % modulus) + modulus) % modulus;
}

function affineInverse(multiplier) {
  for (let inverse = 1; inverse <= 25; inverse++) {
    if ((multiplier * inverse) % 26 === 1) return inverse;
  }
  throw new RangeError('The affine multiplier is not invertible.');
}

function substitute(cipher, key, text, decrypt) {
  let transform;
  if (cipher === 'caesar') {
    const shift = Number(key) * (decrypt ? -1 : 1);
    transform = value => mod(value + shift, 26);
  } else if (cipher === 'affine') {
    const [multiplier, offset] = key.split(',').map(Number);
    const inverse = decrypt ? affineInverse(multiplier) : 0;
    transform = decrypt
      ? value => mod(inverse * (value - offset), 26)
      : value => mod(multiplier * value + offset, 26);
  } else if (cipher === 'vigenere') {
    const shifts = Array.from(key, character => character.charCodeAt(0) - 65);
    const direction = decrypt ? -1 : 1;
    transform = (value, index) => mod(value + direction * shifts[index % shifts.length], 26);
  } else if (cipher === 'autokey') {
    const shifts = Array.from(key, character => character.charCodeAt(0) - 65);
    const plaintext = [];
    const direction = decrypt ? -1 : 1;
    transform = (value, index) => {
      const shift = index < shifts.length ? shifts[index] : plaintext[index - shifts.length];
      const result = mod(value + direction * shift, 26);
      plaintext.push(decrypt ? result : value);
      return result;
    };
  } else {
    throw new RangeError('Unknown substitution cipher.');
  }
  const output = [];
  let letterIndex = 0;
  for (const character of text) {
    const value = letterValue(character);
    if (value < 0) {
      output.push(character);
    } else {
      const base = character.charCodeAt(0) >= 97 ? 97 : 65;
      output.push(String.fromCharCode(base + transform(value, letterIndex)));
      letterIndex++;
    }
  }
  return output.join('');
}

module.exports = {mod, affineInverse, substitute};
