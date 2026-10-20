import type { Row } from './dataset.ts';

export interface Fraction { numerator: number; denominator: number }
export interface Statistics {
    n: number;
    counts: number[];
    sumSquares: number;
    majority: number;
    error: number;
}
export function majority(counts: number[]): number {
    let best = 0;
    for (let i = 1; i < counts.length; i++) if (counts[i] > counts[best]) best = i;
    return best;
}
export function statistics(rows: Row[], classes: number): Statistics {
    const counts: number[] = Array(classes).fill(0);
    for (const row of rows) counts[row.label]++;
    const predicted = majority(counts);
    return { n: rows.length, counts, sumSquares: counts.reduce((sum, c) => sum + c * c, 0),
        majority: predicted, error: rows.length - counts[predicted] };
}
export function evaluationValue(left: Statistics, right: Statistics): Fraction {
    return { numerator: left.sumSquares * right.n + right.sumSquares * left.n,
        denominator: left.n * right.n };
}
export function compareFractions(a: Fraction, b: Fraction): number {
    // All integer cross products are below 2^53 under the task's bounds.
    const left = a.numerator * b.denominator;
    const right = b.numerator * a.denominator;
    return left < right ? -1 : left > right ? 1 : 0;
}
export function improves(value: Fraction, stats: Statistics): boolean {
    return value.numerator * stats.n > stats.sumSquares * value.denominator;
}
export function impurityDecrease(parent: Statistics, left: Statistics, right: Statistics): number {
    const l = left.sumSquares / left.n;
    const r = right.sumSquares / right.n;
    const p = parent.sumSquares / parent.n;
    return (l + r) - p;
}
