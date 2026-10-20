export type Fraction = readonly [number, number];
export interface Confusion { tp: number; fp: number; tn: number; fn: number; correct: number; predictions: number[] }
export interface ROCPoint { threshold: number; tp: number; fp: number }

export function real(value: number | null, decimals = 4): string {
    if (value === null) return '-';
    if (Math.abs(value) >= 1e21) return BigInt(value).toString() + '.' + '0'.repeat(decimals);
    const text = value.toFixed(decimals);
    return Number(text) === 0 ? (0).toFixed(decimals) : text;
}
export function ratio(numerator: number | bigint, denominator: number | bigint): string {
    const a = BigInt(numerator), b = BigInt(denominator);
    if (b === 0n) return '-';
    const q = (20000n * a + b) / (2n * b);
    return `${q / 10000n}.${(q % 10000n).toString().padStart(4, '0')}`;
}
export function fraction([numerator, denominator]: Fraction): string {
    const n = BigInt(numerator), d = BigInt(denominator);
    let a = n, b = d;
    while (b !== 0n) [a, b] = [b, a % b];
    return `${n / a}/${d / a} ${ratio(n, d)}`;
}
export function compareFractions(first: Fraction, second: Fraction): number {
    const difference = BigInt(first[0]) * BigInt(second[1]) - BigInt(second[0]) * BigInt(first[1]);
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
}
export function confusion(probabilities: number[], targets: number[], threshold: number): Confusion {
    const result: Confusion = { tp: 0, fp: 0, tn: 0, fn: 0, correct: 0, predictions: [] };
    for (let i = 0; i < probabilities.length; i++) {
        const predicted = Number(probabilities[i] >= threshold); result.predictions.push(predicted);
        if (predicted === targets[i]) result.correct++;
        if (predicted === 1) result[targets[i] === 1 ? 'tp' : 'fp']++;
        else result[targets[i] === 1 ? 'fn' : 'tn']++;
    }
    return result;
}
export function auc(scores: number[], targets: number[]): Fraction {
    const order = scores.map((_, i) => i).sort((a, b) => scores[a] - scores[b] || a - b);
    let positives = 0, ranks = 0;
    for (let start = 0; start < order.length;) {
        let end = start + 1;
        while (end < order.length && scores[order[end]] === scores[order[start]]) end++;
        const doubledRank = start + 1 + end;
        for (let i = start; i < end; i++) if (targets[order[i]] === 1) { positives++; ranks += doubledRank; }
        start = end;
    }
    return [ranks - positives * (positives + 1), 2 * positives * (scores.length - positives)];
}
export function rocPoints(probabilities: number[], targets: number[]): ROCPoint[] {
    const order = probabilities.map((_, i) => i).sort((a, b) => probabilities[b] - probabilities[a] || a - b), points: ROCPoint[] = [];
    let tp = 0, fp = 0;
    for (let start = 0; start < order.length;) {
        let end = start + 1;
        while (end < order.length && probabilities[order[end]] === probabilities[order[start]]) end++;
        for (let i = start; i < end; i++) { if (targets[order[i]] === 1) tp++; else fp++; }
        points.push({ threshold: probabilities[order[start]], tp, fp }); start = end;
    }
    return points;
}
