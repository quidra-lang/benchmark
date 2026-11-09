import {
  complex,
  transform,
  packedReal,
  squaredMagnitude,
  multiply,
  conjugate,
  add,
  type Complex,
} from './fft.ts';

export function median(values: number[]): number {
  const sorted = values.slice().sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
export function localMaximum(values: number[], index: number): boolean {
  return (
    index > 0 &&
    index + 1 < values.length &&
    values[index] > values[index - 1] &&
    values[index] > values[index + 1]
  );
}
export function interpolate(values: number[], index: number, logarithmic = true) {
  if (!localMaximum(values, index)) return { position: index, value: values[index] };
  const convert = logarithmic ? Math.log : (value: number) => value;
  const alpha = convert(values[index - 1]);
  const beta = convert(values[index]);
  const gamma = convert(values[index + 1]);
  const delta = (alpha - gamma) / (2 * (alpha - 2 * beta + gamma));
  const value = beta - ((alpha - gamma) * delta) / 4;
  return { position: index + delta, value: logarithmic ? Math.exp(value) : value };
}
export function spectrum(signal: number[], window: number[]) {
  const length = window.length;
  const weighted = window.map((value, n) => signal[n] * value);
  const transformed = transform(weighted.map((value) => complex(value)));
  let total = 0;
  for (const value of window) total += value;
  const amplitudes = transformed
    .slice(0, Math.floor(length / 2) + 1)
    .map(
      (value, k) =>
        ((k === 0 || 2 * k === length ? 1 : 2) * Math.sqrt(squaredMagnitude(value))) / total,
    );
  return { weighted, transformed, amplitudes, total };
}
export interface Frame {
  start: number;
  weighted: number[];
  transformed: Complex[];
}
export function* frames(signal: number[], window: number[], hop: number): Generator<Frame> {
  for (let start = 0; start + window.length <= signal.length; start += hop) {
    const weighted = window.map((value, n) => signal[start + n] * value);
    yield { start, weighted, transformed: packedReal(weighted) };
  }
}
export type FrameObserver = (frame: Frame) => void;
export function welch(
  first: number[],
  second: number[],
  window: number[],
  sampleRate: number,
  observe: FrameObserver,
) {
  const bins = window.length / 2 + 1;
  const pxx = Array<number>(bins).fill(0);
  const pyy = pxx.slice();
  const pxy = Array.from({ length: bins }, () => complex());
  const other = frames(second, window, window.length / 2);
  let count = 0;
  for (const x of frames(first, window, window.length / 2)) {
    const y = other.next();
    if (y.done) throw new Error('Unequal channel lengths');
    observe(x);
    observe(y.value);
    count++;
    for (let k = 0; k < bins; k++) {
      pxx[k] += squaredMagnitude(x.transformed[k]);
      pyy[k] += squaredMagnitude(y.value.transformed[k]);
      pxy[k] = add(pxy[k], multiply(conjugate(x.transformed[k]), y.value.transformed[k]));
    }
  }
  let power = 0;
  for (const value of window) power += value * value;
  const psd = pxx.map(
    (value, k) => ((k === 0 || k === bins - 1 ? 1 : 2) * value) / (count * sampleRate * power),
  );
  return {
    count,
    psd,
    coherence: pxy.map((value, k) => squaredMagnitude(value) / (pxx[k] * pyy[k])),
    transfer: pxy.map((value, k) => complex(value.re / pxx[k], value.im / pxx[k])),
  };
}
