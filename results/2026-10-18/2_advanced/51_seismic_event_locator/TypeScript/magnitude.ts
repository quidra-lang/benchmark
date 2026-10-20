export const log10 = (x: number) => Math.log(x) / 2.302585092994046;
export function median(values: number[]) { if (!values.length) return null; const a = values.toSorted((x, y) => x - y), i = Math.floor(a.length / 2); return a.length % 2 ? a[i] : (a[i - 1] + a[i]) / 2; }
export function localMagnitude(amplitude: number, r: number, coefficients: number[]) { const [a, b, c] = coefficients; return log10(amplitude) + a * log10(r / 100) + b * (r - 100) + c; }
export function durationMagnitude(duration: number, r: number, coefficients: number[]) { const [a, b, c] = coefficients; return a + b * log10(duration / 100) + c * r; }
export const magnitudeClass = (h: number) => Math.floor((h + 5) / 10);
export function frequencyStatistics(classes: number[]) {
    const frequencies = new Map<number, number>(); for (const t of classes) frequencies.set(t, (frequencies.get(t) ?? 0) + 1);
    const ordered = [...frequencies.keys()].sort((a, b) => a - b); let completeness = ordered[0];
    for (const t of ordered) if (frequencies.get(t)! > frequencies.get(completeness)!) completeness = t;
    let count = 0, total = 0; for (const t of classes) if (t >= completeness) { count++; total += t; }
    const mc = completeness / 10, mean = total / (10 * count), b = 0.4342944819032518 / (mean - (mc - 0.05));
    return { frequencies, minimum: ordered[0], maximum: ordered[ordered.length - 1], completeness, count, b, sigma: b / Math.sqrt(count), a: log10(count) + b * mc };
}
