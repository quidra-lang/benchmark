'use strict';

function gcd(a, b) {
  if (a < 0n) a = -a;
  while (b !== 0n) { const remainder = a % b; a = b; b = remainder; }
  return a;
}

class Fraction {
  constructor(numerator, denominator = 1n) {
    let n = BigInt(numerator), d = BigInt(denominator);
    if (d < 0n) { n = -n; d = -d; }
    const divisor = gcd(n, d);
    this.n = n / divisor; this.d = d / divisor;
  }
  add(other) { return new Fraction(this.n * other.d + other.n * this.d, this.d * other.d); }
  sub(other) { return new Fraction(this.n * other.d - other.n * this.d, this.d * other.d); }
  mul(other) { return new Fraction(this.n * other.n, this.d * other.d); }
  div(other) { return new Fraction(this.n * other.d, this.d * other.n); }
  compare(other) {
    const difference = this.n * other.d - other.n * this.d;
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
  }
  sign() { return this.n < 0n ? -1 : this.n > 0n ? 1 : 0; }
  value() { return Number(this.n) / Number(this.d); }
  round() {
    const numerator = 2n * this.n + this.d, denominator = 2n * this.d;
    const quotient = numerator / denominator;
    return numerator < 0n && numerator % denominator !== 0n ? quotient - 1n : quotient;
  }
  toString() { return this.d === 1n ? String(this.n) : `${this.n}/${this.d}`; }
}

const ONE = new Fraction(1);
const point = (x, y) => ({ x: x instanceof Fraction ? x : new Fraction(x), y: y instanceof Fraction ? y : new Fraction(y) });
const add = (a, b) => point(a.x.add(b.x), a.y.add(b.y));
const subtract = (a, b) => point(a.x.sub(b.x), a.y.sub(b.y));
const scale = (p, factor) => point(p.x.mul(factor), p.y.mul(factor));
const determinant = (a, b) => a.x.mul(b.y).sub(a.y.mul(b.x));
const cross = (origin, a, b) => determinant(subtract(a, origin), subtract(b, origin));
const equal = (a, b) => a.x.compare(b.x) === 0 && a.y.compare(b.y) === 0;
const pointOrder = (a, b) => a.y.compare(b.y) || a.x.compare(b.x);
const pointKey = p => `${p.x.n}/${p.x.d},${p.y.n}/${p.y.d}`;
const pointText = p => `(${p.x},${p.y})`;
const segmentText = (a, b) => `${pointText(a)}-${pointText(b)}`;

module.exports = { Fraction, ONE, point, add, subtract, scale, determinant, cross, equal, pointOrder, pointKey, pointText, segmentText };
