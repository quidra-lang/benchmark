export class Rational {
  n: bigint;
  d: bigint;
  constructor(numerator: string | number | bigint = 0, denominator: string | number | bigint = 1) {
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

  static from(value: Rational | string | number | bigint): Rational {
    return value instanceof Rational ? value : new Rational(value);
  }

  add(value: Rational | string | number | bigint): Rational {
    const other = Rational.from(value);
    return new Rational(this.n * other.d + other.n * this.d, this.d * other.d);
  }

  subtract(value: Rational | string | number | bigint): Rational {
    const other = Rational.from(value);
    return new Rational(this.n * other.d - other.n * this.d, this.d * other.d);
  }

  multiply(value: Rational | string | number | bigint): Rational {
    const other = Rational.from(value);
    return new Rational(this.n * other.n, this.d * other.d);
  }

  divide(value: Rational | string | number | bigint): Rational {
    const other = Rational.from(value);
    return new Rational(this.n * other.d, this.d * other.n);
  }

  negate(): Rational {
    return new Rational(-this.n, this.d);
  }

  abs(): Rational {
    return this.n < 0n ? this.negate() : this;
  }

  compare(value: Rational | string | number | bigint): number {
    const other = Rational.from(value);
    const difference = this.n * other.d - other.n * this.d;
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
  }

  floor(): bigint {
    const quotient = this.n / this.d;
    return this.n < 0n && this.n % this.d !== 0n ? quotient - 1n : quotient;
  }

  ceil(): bigint {
    return -this.negate().floor();
  }

  toString(): string {
    return this.d === 1n ? String(this.n) : `${this.n}/${this.d}`;
  }
}

export const zero = new Rational(0);
export const one = new Rational(1);

export function parseNumber(text: string): Rational {
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

export function approximate(value: Rational): string {
  const numerator = value.n < 0n ? -value.n : value.n;
  const rounded = (2n * numerator * 1000000n + value.d) / (2n * value.d);
  const sign = value.n < 0n && rounded !== 0n ? '-' : '';
  return `${sign}${rounded / 1000000n}.${String(rounded % 1000000n).padStart(6, '0')}`;
}

export function endpoint(value: Rational | null, lower: boolean): string {
  return value === null ? lower ? '-inf' : 'inf' : String(value);
}

