export interface LogEntry {
  trace: string[];
  weight: number;
}
export type Counts = Map<string, number>;
export type Symbol = '->' | '<-' | '||' | '#';
export type Relation = (first: string, second: string) => Symbol;
export const pairKey = (first: string, second: string): string => first + '\0' + second;
export const count = (counts: Counts, first: string, second: string): number =>
  counts.get(pairKey(first, second)) ?? 0;
export function countFollows(log: LogEntry[]): Counts {
  const counts: Counts = new Map();
  for (const { trace, weight } of log) {
    for (let i = 1; i < trace.length; i++) {
      const key = pairKey(trace[i - 1], trace[i]);
      counts.set(key, (counts.get(key) ?? 0) + weight);
    }
  }
  return counts;
}
export function basicRelation(counts: Counts, first: string, second: string): Symbol {
  const forward = count(counts, first, second) > 0;
  const reverse = count(counts, second, first) > 0;
  return forward ? (reverse ? '||' : '->') : reverse ? '<-' : '#';
}
export function table(rows: (string | number)[][], width: number): string[] {
  return [
    '    ' + rows.map((_, i) => String(i + 1).padStart(width)).join(''),
    ...rows.map(
      (row, i) => String(i + 1).padStart(4) + row.map((v) => String(v).padStart(width)).join(''),
    ),
  ];
}
export function footprint(activities: string[], relation: Relation): string[] {
  return [
    ...activities.map((a, i) => `ACTIVITY ${i + 1} ${a}`),
    ...table(
      activities.map((a) => activities.map((b) => relation(a, b))),
      4,
    ),
  ];
}
