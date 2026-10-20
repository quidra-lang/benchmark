export interface Run { state: number; start: number; end: number }
export interface Segment { start: number; end: number }
export function fraction(n: number, d: number): string {
  if (d === 0) return '-'; if (d < 0) { n = -n; d = -d; } let a = Math.abs(n), b = d;
  while (b) [a, b] = [b, a % b]; return `${n / a}/${d / a}`;
}
export function matrix(k: number): number[][] { return Array.from({ length: k }, () => Array<number>(k).fill(0)); }
export function accumulate(c: number[][], actual: number[], predicted: number[]): void { actual.forEach((s, t) => c[s][predicted[t]]++); }
export function correct(a: number[], b: number[]): number { return a.filter((s, i) => s === b[i]).length; }
export function metricLines(c: number[][], states: string[]): string[] {
  const rows = c.map(r => r.reduce((s, v) => s + v, 0)), cols = states.map((_, j) => c.reduce((s, row) => s + row[j], 0));
  let total = 0, diagonal = 0, chance = 0;
  for (let i = 0; i < c.length; i++) { total += rows[i]; diagonal += c[i][i]; chance += rows[i] * cols[i]; }
  const width = Math.max(...c.flat().map(v => String(v).length));
  return [' ' + states.map(s => ' ' + s.padStart(width)).join(''), ...states.map((s, i) => s + c[i].map(v => ' ' + String(v).padStart(width)).join('')),
    `ACCURACY ${fraction(diagonal, total)}`, `KAPPA ${fraction(total * diagonal - chance, total * total - chance)}`,
    ...states.map((s, i) => `STATE ${s} precision ${fraction(c[i][i], cols[i])} recall ${fraction(c[i][i], rows[i])} f1 ${fraction(2 * c[i][i], cols[i] + rows[i])}`)];
}
export function runs(path: number[]): Run[] {
  const result: Run[] = [];
  path.forEach((state, t) => { if (t === 0 || path[t - 1] !== state) result.push({ state, start: t, end: t }); else result[result.length - 1].end = t; });
  return result;
}
export function overlaps(a: Segment, b: Segment): boolean { return a.start <= b.end && b.start <= a.end; }
export function boundaries(path: number[]): number[] { return path.map((_, t) => t).filter(t => t > 0 && path[t] !== path[t - 1]); }
export function boundaryMatches(a: number[], b: number[], tolerance: number): number { return a.filter(t => b.some(u => Math.abs(t - u) <= tolerance)).length; }
