import { compareItemsets, itemsetKey } from './baskets.ts';
export class Fraction {
  readonly numerator: bigint;
  readonly denominator: bigint;
  constructor(numerator: number | bigint | string, denominator: number | bigint | string = 1) {
    let n = BigInt(numerator);
    let d = BigInt(denominator);
    if (d === 0n) throw new Error('zero denominator');
    if (d < 0n) {
      n = -n;
      d = -d;
    }
    let a = n < 0n ? -n : n;
    let b = d;
    while (b) [a, b] = [b, a % b];
    this.numerator = n / a;
    this.denominator = d / a;
  }
  compare(other: Fraction): number {
    const d = this.numerator * other.denominator - other.numerator * this.denominator;
    return d < 0n ? -1 : d > 0n ? 1 : 0;
  }
  subtract(other: Fraction): Fraction {
    return new Fraction(
      this.numerator * other.denominator - other.numerator * this.denominator,
      this.denominator * other.denominator,
    );
  }
  multiply(other: Fraction): Fraction {
    return new Fraction(this.numerator * other.numerator, this.denominator * other.denominator);
  }
  negate(): Fraction {
    return new Fraction(-this.numerator, this.denominator);
  }
}
export interface RuleMetrics {
  antecedent: string[];
  consequent: string[];
  count: number;
  support: Fraction;
  confidence: Fraction;
  lift: Fraction;
  leverage: Fraction;
  conviction: Fraction | null;
}
export interface Rule extends RuleMetrics {
  items: string[];
  improvement: Fraction;
  rank: number;
}
export function createRule(
  antecedent: string[],
  consequent: string[],
  nx: number,
  ny: number,
  nz: number,
  total: number,
): RuleMetrics {
  const x = BigInt(nx);
  const y = BigInt(ny);
  const z = BigInt(nz);
  const n = BigInt(total);
  return {
    antecedent,
    consequent,
    count: nz,
    support: new Fraction(z, n),
    confidence: new Fraction(z, x),
    lift: new Fraction(n * z, x * y),
    leverage: new Fraction(n * z - x * y, n * n),
    conviction: nx === nz ? null : new Fraction((n - y) * x, n * (x - z)),
  };
}
export const passes = (rule: RuleMetrics, confidence: Fraction, lift: Fraction) =>
  rule.confidence.compare(confidence) >= 0 && rule.lift.compare(lift) >= 0;
export function compareRules(a: RuleMetrics, b: RuleMetrics): number {
  return (
    b.confidence.compare(a.confidence) ||
    b.lift.compare(a.lift) ||
    b.count - a.count ||
    compareItemsets(a.antecedent, b.antecedent) ||
    compareItemsets(a.consequent, b.consequent)
  );
}
export const ruleKey = (rule: RuleMetrics) =>
  `${itemsetKey(rule.antecedent)}->${itemsetKey(rule.consequent)}`;
