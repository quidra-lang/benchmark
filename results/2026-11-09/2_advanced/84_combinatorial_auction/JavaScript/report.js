'use strict';

const fs = require('node:fs');

class Fraction {
  constructor(numerator, denominator = 1) {
    let n = BigInt(numerator);
    let d = BigInt(denominator);
    if (d < 0n) {
      n = -n;
      d = -d;
    }
    let a = n < 0n ? -n : n;
    let b = d;
    while (b !== 0n) [a, b] = [b, a % b];
    this.numerator = n / a;
    this.denominator = d / a;
  }

  static from(value) {
    return value instanceof Fraction ? value : new Fraction(value);
  }

  add(value) {
    const other = Fraction.from(value);
    return new Fraction(this.numerator * other.denominator + other.numerator * this.denominator,
      this.denominator * other.denominator);
  }

  subtract(value) {
    const other = Fraction.from(value);
    return new Fraction(this.numerator * other.denominator - other.numerator * this.denominator,
      this.denominator * other.denominator);
  }

  multiply(value) {
    const other = Fraction.from(value);
    return new Fraction(this.numerator * other.numerator, this.denominator * other.denominator);
  }

  divide(value) {
    const other = Fraction.from(value);
    return new Fraction(this.numerator * other.denominator, this.denominator * other.numerator);
  }

  compare(value) {
    const other = Fraction.from(value);
    const difference = this.numerator * other.denominator - other.numerator * this.denominator;
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
  }

  toString() {
    return this.denominator === 1n ? String(this.numerator) : `${this.numerator}/${this.denominator}`;
  }
}

function bundle(mask, items) {
  return items.filter(item => (mask & item.bit) !== 0).map(item => item.name).join('+') || '-';
}

function writeFiles(files) {
  fs.mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

module.exports = {Fraction, bundle, writeFiles};
