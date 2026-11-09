'use strict';

class Rational {
  constructor(numerator = 0, denominator = 1) {
    let n = BigInt(numerator);
    let d = BigInt(denominator);
    if (d < 0n) {
      n = -n;
      d = -d;
    }
    let first = n < 0n ? -n : n;
    let second = d;
    while (second !== 0n) [first, second] = [second, first % second];
    this.n = n / first;
    this.d = d / first;
  }

  static from(value) {
    return value instanceof Rational ? value : new Rational(value);
  }

  add(value) {
    const other = Rational.from(value);
    return new Rational(this.n * other.d + other.n * this.d, this.d * other.d);
  }

  subtract(value) {
    const other = Rational.from(value);
    return new Rational(this.n * other.d - other.n * this.d, this.d * other.d);
  }

  multiply(value) {
    const other = Rational.from(value);
    return new Rational(this.n * other.n, this.d * other.d);
  }

  divide(value) {
    const other = Rational.from(value);
    return new Rational(this.n * other.d, this.d * other.n);
  }

  negate() {
    return new Rational(-this.n, this.d);
  }

  abs() {
    return this.n < 0n ? this.negate() : this;
  }

  compare(value) {
    const other = Rational.from(value);
    const difference = this.n * other.d - other.n * this.d;
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
  }

  floor() {
    const quotient = this.n / this.d;
    return this.n < 0n && this.n % this.d !== 0n ? quotient - 1n : quotient;
  }

  ceil() {
    return -this.negate().floor();
  }

  toString() {
    return this.d === 1n ? String(this.n) : `${this.n}/${this.d}`;
  }
}

const zero = new Rational(0);
const one = new Rational(1);

function parseNumber(text) {
  if (text.includes('/')) {
    const [numerator, denominator] = text.split('/');
    return new Rational(numerator, denominator);
  }
  if (text.includes('.')) {
    const [whole, decimal] = text.split('.');
    return new Rational(whole + decimal, 10n ** BigInt(decimal.length));
  }
  return new Rational(text);
}

function approximate(value) {
  const numerator = value.n < 0n ? -value.n : value.n;
  const rounded = (2n * numerator * 1000000n + value.d) / (2n * value.d);
  const sign = value.n < 0n && rounded !== 0n ? '-' : '';
  return `${sign}${rounded / 1000000n}.${String(rounded % 1000000n).padStart(6, '0')}`;
}

function endpoint(value, lower) {
  return value === null ? lower ? '-inf' : 'inf' : String(value);
}

module.exports = {Rational, zero, one, parseNumber, approximate, endpoint};
