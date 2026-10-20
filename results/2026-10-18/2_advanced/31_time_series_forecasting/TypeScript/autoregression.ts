import { mean } from './decomposition.ts';
export const DIFFERENCES = ['none', 'first', 'seasonal', 'both'] as const;
export type Difference = typeof DIFFERENCES[number];
export interface ARState { values: number[]; differenced: number[]; difference: Difference; offset: number; average: number; coefficients: number[] }
export function difference(values: number[], kind: Difference, season: number) {
    const offset = kind === 'none' ? 0 : kind === 'first' ? 1 : kind === 'seasonal' ? season : season + 1, result: number[] = [];
    for (let t = offset; t < values.length; t++) {
        if (kind === 'none') result.push(values[t]); else if (kind === 'first') result.push(values[t] - values[t - 1]);
        else if (kind === 'seasonal') result.push(values[t] - values[t - season]); else result.push((values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1]));
    }
    return { values: result, offset };
}
export function autocorrelation(values: number[], maximumLag: number) {
    const average = mean(values), deltas = values.map(v => v - average); let squares = 0;
    for (const d of deltas) squares += d * d;
    const variance = squares / values.length, correlations = [1];
    for (let lag = 1; lag <= maximumLag; lag++) { let total = 0; for (let i = 0; i < values.length - lag; i++) total += deltas[i] * deltas[i + lag]; correlations.push(total / values.length / variance); }
    return { mean: average, variance, correlations };
}
export function durbinLevinson(correlations: number[]) {
    const rows: number[][] = [[]], variances = [1], partial = [0];
    for (let k = 1; k < correlations.length; k++) {
        const previous = rows[k - 1]; let total = 0;
        for (let j = 1; j < k; j++) total += previous[j - 1] * correlations[k - j];
        const theta = (correlations[k] - total) / variances[k - 1], row: number[] = [];
        for (let j = 1; j < k; j++) row.push(previous[j - 1] - theta * previous[k - j - 1]);
        row.push(theta); rows.push(row); variances.push(variances[k - 1] * (1 - theta * theta)); partial.push(theta);
    }
    return { rows, variances, partial };
}
export function residuals(values: number[], average: number, coefficients: number[]) {
    const result: number[] = [];
    for (let i = coefficients.length; i < values.length; i++) { let total = 0; for (let j = 1; j <= coefficients.length; j++) total += coefficients[j - 1] * (values[i - j] - average); result.push(values[i] - average - total); }
    return result;
}
export function forecast(model: ARState, origin: number, steps: number, season: number) {
    const differenced = model.differenced.slice(0, origin - model.offset), appended: number[] = [], original = model.values.slice(0, origin), result: number[] = [];
    for (let k = 0; k < steps; k++) { let total = 0; for (let j = 1; j <= model.coefficients.length; j++) total += model.coefficients[j - 1] * (differenced[differenced.length - j] - model.average); const v = model.average + total; differenced.push(v); appended.push(v); }
    for (const v of appended) {
        let next = v; const end = original.length;
        if (model.difference === 'first') next = v + original[end - 1]; else if (model.difference === 'seasonal') next = v + original[end - season];
        else if (model.difference === 'both') next = v + original[end - 1] + original[end - season] - original[end - season - 1];
        original.push(next); result.push(next);
    }
    return result;
}
export function ljungBox(values: number[], lags: number[]) {
    const { correlations } = autocorrelation(values, Math.max(...lags));
    return lags.map(lag => {
        let total = 0; for (let k = 1; k <= lag; k++) total += correlations[k] * correlations[k] / (values.length - k);
        const q = values.length * (values.length + 2) * total, x = q / 2; let term = 1, terms = term;
        for (let i = 1; i <= lag / 2 - 1; i++) { term = term * x / i; terms += term; }
        return { lag, q, p: Math.exp(-x) * terms };
    });
}
