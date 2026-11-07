import { div } from './report.ts';

export interface Signals {
  lowpass: number[];
  bandpass: number[];
  derivative: number[];
  squared: number[];
  integrated: number[];
}
export function filter(signal: number[]): Signals {
  const c: number[] = [];
  const lowpass: number[] = [];
  const bandpass: number[] = [];
  const derivative: number[] = [];
  const squared: number[] = [];
  const integrated: number[] = [];
  const at = (values: number[], i: number): number => (i < 0 ? 0 : values[i]);
  let highpassSum = 0;
  let windowSum = 0;
  for (let n = 0; n < signal.length; n++) {
    c.push(
      2 * at(c, n - 1) - at(c, n - 2) + signal[n] - 2 * at(signal, n - 6) + at(signal, n - 12),
    );
    lowpass.push(div(c[n], 32));
    highpassSum += lowpass[n] - at(lowpass, n - 32);
    bandpass.push(at(lowpass, n - 16) - div(highpassSum, 32));
    derivative.push(
      div(2 * bandpass[n] + at(bandpass, n - 1) - at(bandpass, n - 3) - 2 * at(bandpass, n - 4), 8),
    );
    squared.push(derivative[n] * derivative[n]);
    windowSum += squared[n] - at(squared, n - 30);
    integrated.push(div(windowSum, 30));
  }
  return { lowpass, bandpass, derivative, squared, integrated };
}
