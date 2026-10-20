import { pairKey, count, type Counts, type LogEntry, type Relation } from './dfg.ts';

export interface Pair { A: string[]; B: string[] }
export function compareSequences(a: string[], b: string[]): number { for (let i = 0; i < Math.min(a.length, b.length); i++) if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1; return a.length - b.length; }
export const comparePairs = (a: Pair, b: Pair): number => compareSequences(a.A, b.A) || compareSequences(a.B, b.B);
export function extendPair(pair: Pair, activity: string, side: 'A' | 'B', relation: Relation): Pair | null {
    const own = pair[side]; if (own.includes(activity) || relation(activity, activity) !== '#' || own.some(other => relation(activity, other) !== '#')) return null;
    if (side === 'A' && pair.B.some(other => relation(activity, other) !== '->') || side === 'B' && pair.A.some(other => relation(other, activity) !== '->')) return null;
    return { A: side === 'A' ? [...pair.A, activity].sort() : pair.A, B: side === 'B' ? [...pair.B, activity].sort() : pair.B };
}
export function triangleCounts(log: LogEntry[]): Counts {
    const triangles: Counts = new Map(); for (const { trace, weight } of log) for (let i = 0; i + 2 < trace.length; i++) if (trace[i] !== trace[i + 1] && trace[i] === trace[i + 2]) { const key = pairKey(trace[i], trace[i + 1]); triangles.set(key, (triangles.get(key) ?? 0) + weight); } return triangles;
}
export function alphaPlusRelation(counts: Counts, triangles: Counts): Relation {
    const causal = (a: string, b: string): boolean => count(counts, a, b) > 0 && (count(counts, b, a) === 0 || a !== b && count(triangles, a, b) > 0 && count(triangles, b, a) > 0);
    return (a, b) => causal(a, b) ? '->' : causal(b, a) ? '<-' : count(counts, a, b) > 0 && count(counts, b, a) > 0 ? '||' : '#';
}
