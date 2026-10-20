import { mkdirSync, writeFileSync } from 'node:fs';

export interface Rational { n: number; d: number }
export function ratio(n: number, d = 1): Rational { return { n, d }; }
export function compare(a: Rational, b: Rational): number {
    const left = a.n * b.d;
    const right = b.n * a.d;
    return left < right ? -1 : left > right ? 1 : 0;
}
export function floorRatio(n: number, d: number): number {
    const a = BigInt(n), b = BigInt(d);
    return Number(a / b - (a < 0n && a % b !== 0n ? 1n : 0n));
}
export function decimal(n: number, d: number, digits: number): string {
    const p = BigInt(n), q = BigInt(d), scale = 10n ** BigInt(digits);
    const m = (2n * scale * (p < 0n ? -p : p) + q) / (2n * q);
    return `${p < 0n && m > 0n ? '-' : ''}${m / scale}.${String(m % scale).padStart(digits, '0')}`;
}
export function hullArea(doubled: number): string {
    return `${floorRatio(doubled, 2)}.${doubled % 2 ? '5' : '0'}`;
}
export function writeReports(reports: Record<string, string[]>): void {
    mkdirSync('output', { recursive: true });
    for (const [name, lines] of Object.entries(reports)) writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}
