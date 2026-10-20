export function sum(values: Iterable<number>) { let total = 0; for (const v of values) total += v; return total; }
export const mean = (values: number[]) => sum(values) / values.length;
export function sampleVariance(values: number[]) { const average = mean(values); let total = 0; for (const v of values) { const d = v - average; total += d * d; } return total / (values.length - 1); }
export interface Decomposition { trend: (number | null)[]; defined: number[]; add: number[]; mult: number[]; residualAdd: (number | null)[]; residualMult: (number | null)[] }
export function decompose(values: number[], season: number): Decomposition {
    const half = season / 2, trend: (number | null)[] = Array(values.length).fill(null), defined: number[] = [];
    const add: number[] = Array(season).fill(0), mult: number[] = Array(season).fill(0), counts: number[] = Array(season).fill(0);
    for (let t = half; t < values.length - half; t++) {
        let total = 0.5 * values[t - half];
        for (let i = t - half + 1; i < t + half; i++) total += values[i];
        total += 0.5 * values[t + half]; const tr = total / season; trend[t] = tr; defined.push(t);
        add[t % season] += values[t] - tr; mult[t % season] += values[t] / tr; counts[t % season]++;
    }
    for (let j = 0; j < season; j++) { add[j] /= counts[j]; mult[j] /= counts[j]; }
    const addMean = mean(add), multMean = mean(mult);
    for (let j = 0; j < season; j++) { add[j] -= addMean; mult[j] /= multMean; }
    const residualAdd: (number | null)[] = Array(values.length).fill(null), residualMult: (number | null)[] = Array(values.length).fill(null);
    for (const t of defined) { residualAdd[t] = values[t] - trend[t]! - add[t % season]; residualMult[t] = values[t] / (trend[t]! * mult[t % season]); }
    return { trend, defined, add, mult, residualAdd, residualMult };
}
export function regression(values: number[]) {
    const center = (values.length + 1) / 2, average = mean(values);
    let numerator = 0, denominator = 0;
    for (let t = 0; t < values.length; t++) { const d = t + 1 - center; numerator += d * (values[t] - average); denominator += d * d; }
    const slope = numerator / denominator; return { intercept: average - slope * center, slope };
}
