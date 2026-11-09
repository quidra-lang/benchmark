import type { Process, SimEvent, Copy } from './processes.ts';

export function advance(process: Process, sender: SimEvent | null = null): void {
  if (sender !== null) {
    process.L = Math.max(process.L, sender.L);
    for (let i = 0; i < process.V.length; i++) process.V[i] = Math.max(process.V[i], sender.V[i]);
  }
  process.L++;
  process.V[process.index]++;
}
export const lessEqual = (a: number[], b: number[]): boolean =>
  a.every((value, i) => value <= b[i]);
export function relation(a: number[], b: number[]): '->' | '<-' | '||' {
  const equal = a.every((v, i) => v === b[i]);
  return !equal && lessEqual(a, b) ? '->' : !equal && lessEqual(b, a) ? '<-' : '||';
}
export function deliverable(copy: Copy, counters: number[]): boolean {
  return copy.message.stamp.every((v, i) =>
    i === copy.source ? v === counters[i] + 1 : v <= counters[i],
  );
}
export function missingProcesses(copy: Copy, counters: number[]): number[] {
  const missing: number[] = [];
  for (let i = 0; i < counters.length; i++) {
    if (copy.message.stamp[i] > counters[i] + Number(i === copy.source)) missing.push(i);
  }
  return missing;
}
export const vector = (values: number[]): string => values.join(',');
