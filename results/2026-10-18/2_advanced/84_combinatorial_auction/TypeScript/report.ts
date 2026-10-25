import { mkdirSync, writeFileSync } from 'node:fs';
import type { Item } from './types.ts';

export class Fraction {
  numerator: bigint; denominator: bigint;
  constructor(numerator: number | bigint | string, denominator: number | bigint | string = 1) {
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

  static from(value: number | bigint | string | Fraction): Fraction {
    return value instanceof Fraction ? value : new Fraction(value);
  }

  add(value: number | bigint | string | Fraction): Fraction {
    const other = Fraction.from(value);
    return new Fraction(this.numerator * other.denominator + other.numerator * this.denominator,
      this.denominator * other.denominator);
  }

  subtract(value: number | bigint | string | Fraction): Fraction {
    const other = Fraction.from(value);
    return new Fraction(this.numerator * other.denominator - other.numerator * this.denominator,
      this.denominator * other.denominator);
  }

  multiply(value: number | bigint | string | Fraction): Fraction {
    const other = Fraction.from(value);
    return new Fraction(this.numerator * other.numerator, this.denominator * other.denominator);
  }

  divide(value: number | bigint | string | Fraction): Fraction {
    const other = Fraction.from(value);
    return new Fraction(this.numerator * other.denominator, this.denominator * other.numerator);
  }

  compare(value: number | bigint | string | Fraction): number {
    const other = Fraction.from(value);
    const difference = this.numerator * other.denominator - other.numerator * this.denominator;
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
  }

  toString(): string {
    return this.denominator === 1n ? String(this.numerator) : `${this.numerator}/${this.denominator}`;
  }
}

export function bundle(mask: number, items: Item[]): string {
  return items.filter(item => (mask & item.bit) !== 0).map(item => item.name).join('+') || '-';
}

export function writeFiles(files: Record<string,string[]>): void {
  mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

