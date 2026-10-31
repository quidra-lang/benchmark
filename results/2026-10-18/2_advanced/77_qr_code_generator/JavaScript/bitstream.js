'use strict';

const ALPHANUMERIC = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

function append(bits, value, width) {
  for (let bit = width - 1; bit >= 0; bit--) bits.push(Math.floor(value / 2 ** bit) % 2);
}

function fromCodewords(codewords) {
  const bits = [];
  for (const value of codewords) append(bits, value, 8);
  return bits;
}

function toCodewords(bits) {
  const codewords = [];
  for (let i = 0; i < bits.length; i += 8) {
    let value = 0;
    for (let j = 0; j < 8; j++) value = 2 * value + bits[i + j];
    codewords.push(value);
  }
  return codewords;
}

class BitReader {
  constructor(bits) { this.bits = bits; this.position = 0; }
  get remaining() { return this.bits.length - this.position; }
  read(width) {
    let value = 0;
    for (let i = 0; i < width; i++) value = 2 * value + this.bits[this.position++];
    return value;
  }
}

const binary = (value, width) => value.toString(2).padStart(width, '0');

module.exports = { ALPHANUMERIC, append, fromCodewords, toCodewords, BitReader, binary };
