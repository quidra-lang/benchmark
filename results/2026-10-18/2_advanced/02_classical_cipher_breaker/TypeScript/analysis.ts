export interface Repeat { trigram: string; positions: number[]; gaps: number[]; gcd: number }
export interface Kasiski { repeats: Repeat[]; gaps: number[] }
export interface Period { length: number; columns: number[]; average: number; kasiski: number }

export function counts(text: string): number[] {
  const result = Array<number>(26).fill(0);
  for (const c of text) result[c.charCodeAt(0) - 65]++;
  return result;
}
export function ioc(text: string): number {
  const sum = counts(text).reduce((total, count) => total + count * (count - 1), 0);
  return Math.floor(100000 * sum / (text.length * (text.length - 1)));
}
export function columns(text: string, length: number): string[] {
  const result = Array<string>(length).fill('');
  for (let i = 0; i < text.length; i++) result[i % length] += text[i];
  return result;
}
function gcd(a: number, b: number): number { while (b) [a, b] = [b, a % b]; return a; }
export function kasiski(text: string): Kasiski {
  const positions = new Map<string, number[]>();
  for (let i = 0; i + 2 < text.length; i++) {
    const trigram = text.slice(i, i + 3);
    const list = positions.get(trigram) ?? [];
    list.push(i + 1); positions.set(trigram, list);
  }
  const repeats: Repeat[] = [];
  for (const trigram of [...positions.keys()].sort()) {
    const at = positions.get(trigram)!;
    if (at.length < 2) continue;
    const gaps = at.slice(1).map((p, i) => p - at[i]);
    repeats.push({ trigram, positions: at, gaps, gcd: gaps.reduce(gcd) });
  }
  return { repeats, gaps: repeats.flatMap(repeat => repeat.gaps) };
}
export function periods(text: string, maximum: number, examination: Kasiski): Period[] {
  return Array.from({ length: maximum }, (_, i) => {
    const length = i + 1, values = columns(text, length).map(ioc);
    return { length, columns: values, average: Math.floor(values.reduce((a, b) => a + b, 0) / length),
      kasiski: examination.gaps.filter(gap => gap % length === 0).length };
  });
}
export function percentage(count: number, total: number): string {
  const value = Math.floor((2000 * count + total) / (2 * total));
  return `${Math.floor(value / 10)}.${value % 10}`;
}
export function pairCounts(text: string, step: number): Map<string, number> {
  const result = new Map<string, number>();
  for (let i = 0; i + 1 < text.length; i += step) {
    const pair = text.slice(i, i + 2); result.set(pair, (result.get(pair) ?? 0) + 1);
  }
  return result;
}
export function topPairs(pairs: Map<string, number>): string {
  return [...pairs].sort(([a, x], [b, y]) => y - x || (a < b ? -1 : a > b ? 1 : 0))
    .slice(0, 10).map(([pair, count]) => `${pair}:${count}`).join(' ');
}
