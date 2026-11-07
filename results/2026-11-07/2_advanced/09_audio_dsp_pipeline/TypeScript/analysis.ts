import { floorDiv, peak } from './signals.ts';
export interface Measurements {
  peak: number;
  sum: number;
  energy: number;
  rms: number;
  zero_crossings: number;
  clipped: number;
}
export function isqrt(value: number): number {
  const n = BigInt(value);
  if (n < 2n) return Number(n);
  let estimate = n;
  let next = (n + 1n) / 2n;
  while (next < estimate) {
    estimate = next;
    next = (estimate + n / estimate) / 2n;
  }
  return Number(estimate);
}
export function energy(samples: readonly number[]): number {
  let total = 0;
  for (const x of samples) total += x * x;
  return total;
}
export const rms = (samples: readonly number[]) => isqrt(floorDiv(energy(samples), samples.length));
export function zeroCrossings(samples: readonly number[]): number {
  let count = 0;
  for (let i = 1; i < samples.length; i++) if (samples[i - 1] < 0 !== samples[i] < 0) count++;
  return count;
}
export function clipped(samples: readonly number[]): number {
  let count = 0;
  for (const x of samples) if (x === -32768 || x === 32767) count++;
  return count;
}
export function measure(samples: readonly number[]): Measurements {
  let sum = 0;
  for (const x of samples) sum += x;
  const power = energy(samples);
  return {
    peak: peak(samples),
    sum,
    energy: power,
    rms: isqrt(floorDiv(power, samples.length)),
    zero_crossings: zeroCrossings(samples),
    clipped: clipped(samples),
  };
}
export function crest(samples: readonly number[], measured = measure(samples)): string {
  if (measured.energy === 0) return 'none';
  const numerator = BigInt(measured.peak * measured.peak * samples.length);
  const denominator = BigInt(measured.energy);
  let a = numerator;
  let b = denominator;
  while (b !== 0n) [a, b] = [b, a % b];
  return `${numerator / a}/${denominator / a}`;
}
export function autocorrelation(samples: readonly number[], lag: number): number {
  let value = 0;
  for (let n = 0; n < samples.length - lag; n++) value += samples[n] * samples[n + lag];
  return value;
}
export function pitchLag(samples: readonly number[], low: number, high: number): number | null {
  let bestLag = low;
  let bestValue = autocorrelation(samples, low);
  for (let lag = low + 1; lag <= high; lag++) {
    const value = autocorrelation(samples, lag);
    if (value > bestValue) {
      bestLag = lag;
      bestValue = value;
    }
  }
  return bestValue > 0 ? bestLag : null;
}
