import { readFileSync } from 'node:fs';
export class Signal {
  constructor(readonly name: string, readonly rate: number, readonly samples: readonly number[],
    readonly origin = 'input', readonly ingredients: readonly Signal[] = []) {}
}
export interface Generated { samples: number[]; clipped?: number; sections?: number; sourcePeak?: number; muted?: number; minGain?: number; reduced?: number }
export function floorDiv(numerator: number, denominator: number): number {
  let n = BigInt(numerator), d = BigInt(denominator);
  if (d < 0n) { n = -n; d = -d; }
  const quotient = n / d;
  return Number(n < 0n && n % d !== 0n ? quotient - 1n : quotient);
}
export const ceilDiv = (a: number, b: number) => -floorDiv(-a, b);
export const mod = (a: number, b: number) => a - b * floorDiv(a, b);
export const rdiv = (a: number, b: number) => floorDiv(2 * a + b, 2 * b);
export const sat = (value: number) => Math.max(-32768, Math.min(32767, value));
export class ClipCounter {
  count = 0;
  apply(value: number): number { if (value < -32768 || value > 32767) this.count++; return sat(value); }
}
export function peak(samples: readonly number[]): number {
  let maximum = 0; for (const value of samples) maximum = Math.max(maximum, Math.abs(value)); return maximum;
}
export function readSignals(path: string): Signal[] {
  const lines = readFileSync(path, 'ascii').slice(0, -1).split('\n'), signals: Signal[] = [];
  let position = 0;
  while (position < lines.length) {
    const [, name, rate, length] = lines[position++].split(' '), samples: number[] = [];
    while (samples.length < Number(length)) samples.push(...lines[position++].split(' ').map(Number));
    signals.push(new Signal(name, Number(rate), samples));
  }
  return signals;
}
export function formatSignal(signal: Signal): string[] {
  const lines = [`SIGNAL ${signal.name} ${signal.rate} ${signal.samples.length}`];
  for (let i = 0; i < signal.samples.length; i += 16) lines.push(signal.samples.slice(i, i + 16).join(' ')); return lines;
}
export function impulse(count: number, position: number, amplitude: number): number[] {
  const samples = Array<number>(count).fill(0); samples[position] = amplitude; return samples;
}
export function step(count: number, position: number, amplitude: number): number[] {
  return Array.from({ length: count }, (_, i) => i >= position ? amplitude : 0);
}
export function noise(count: number, seed: number): number[] {
  const samples: number[] = []; let state = seed;
  for (let i = 0; i < count; i++) { state = mod(48271 * state, 2147483647); samples.push(mod(state, 65536) - 32768); }
  return samples;
}
