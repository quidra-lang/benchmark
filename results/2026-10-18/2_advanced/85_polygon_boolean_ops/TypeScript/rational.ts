function gcd(a: bigint, b: bigint): bigint {
  if (a < 0n) a = -a;
  while (b !== 0n) { const remainder = a % b; a = b; b = remainder; }
  return a;
}

export class Fraction {
  n: bigint;
  d: bigint;
  constructor(numerator: number | bigint, denominator: number | bigint = 1n) {
    let n = BigInt(numerator), d = BigInt(denominator);
    if (d < 0n) { n = -n; d = -d; }
    const divisor = gcd(n, d);
    this.n = n / divisor; this.d = d / divisor;
  }
  add(other: Fraction): Fraction { return new Fraction(this.n * other.d + other.n * this.d, this.d * other.d); }
  sub(other: Fraction): Fraction { return new Fraction(this.n * other.d - other.n * this.d, this.d * other.d); }
  mul(other: Fraction): Fraction { return new Fraction(this.n * other.n, this.d * other.d); }
  div(other: Fraction): Fraction { return new Fraction(this.n * other.d, this.d * other.n); }
  compare(other: Fraction): number {
    const difference = this.n * other.d - other.n * this.d;
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
  }
  sign(): number { return this.n < 0n ? -1 : this.n > 0n ? 1 : 0; }
  value(): number { return Number(this.n) / Number(this.d); }
  round(): bigint {
    const numerator = 2n * this.n + this.d, denominator = 2n * this.d;
    const quotient = numerator / denominator;
    return numerator < 0n && numerator % denominator !== 0n ? quotient - 1n : quotient;
  }
  toString(): string { return this.d === 1n ? String(this.n) : `${this.n}/${this.d}`; }
}

export interface Point { x: Fraction; y: Fraction }
export const ONE = new Fraction(1);
export const point = (x: Fraction | bigint | number, y: Fraction | bigint | number): Point => ({ x: x instanceof Fraction ? x : new Fraction(x), y: y instanceof Fraction ? y : new Fraction(y) });
export const add = (a: Point, b: Point): Point => point(a.x.add(b.x), a.y.add(b.y));
export const subtract = (a: Point, b: Point): Point => point(a.x.sub(b.x), a.y.sub(b.y));
export const scale = (p: Point, factor: Fraction): Point => point(p.x.mul(factor), p.y.mul(factor));
export const determinant = (a: Point, b: Point): Fraction => a.x.mul(b.y).sub(a.y.mul(b.x));
export const cross = (origin: Point, a: Point, b: Point): Fraction => determinant(subtract(a, origin), subtract(b, origin));
export const equal = (a: Point, b: Point): boolean => a.x.compare(b.x) === 0 && a.y.compare(b.y) === 0;
export const pointOrder = (a: Point, b: Point): number => a.y.compare(b.y) || a.x.compare(b.x);
export const pointKey = (p: Point): string => `${p.x.n}/${p.x.d},${p.y.n}/${p.y.d}`;
export const pointText = (p: Point): string => `(${p.x},${p.y})`;
export const segmentText = (a: Point, b: Point): string => `${pointText(a)}-${pointText(b)}`;

