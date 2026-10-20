import { ClipCounter, floorDiv, rdiv, type Generated } from './signals.ts';
export function fir(input: readonly number[], divisor: number, taps: number[]): Generated {
  const clips = new ClipCounter(), samples: number[] = [];
  for (let n = 0; n < input.length; n++) {
    let value = 0; for (let k = 0; k < taps.length; k++) value += taps[k] * (input[n - k] ?? 0);
    samples.push(clips.apply(floorDiv(value, divisor)));
  }
  return { samples, clipped: clips.count };
}
export function biquad(input: readonly number[], coefficients: number[]): Generated {
  const clips = new ClipCounter(); let samples = [...input];
  for (let start = 0; start < coefficients.length; start += 5) {
    const [b0, b1, b2, a1, a2] = coefficients.slice(start, start + 5), output: number[] = [];
    for (let n = 0; n < samples.length; n++) {
      const value = b0 * samples[n] + b1 * (samples[n - 1] ?? 0) + b2 * (samples[n - 2] ?? 0)
        - a1 * (output[n - 1] ?? 0) - a2 * (output[n - 2] ?? 0);
      output.push(clips.apply(floorDiv(value, 16384)));
    }
    samples = output;
  }
  return { samples, sections: floorDiv(coefficients.length, 5), clipped: clips.count };
}
export function movingAverage(input: readonly number[], width: number): number[] {
  const samples: number[] = []; let sum = 0;
  for (let n = 0; n < input.length; n++) { sum += input[n]; if (n >= width) sum -= input[n - width]; samples.push(rdiv(sum, width)); }
  return samples;
}
export function dcBlock(input: readonly number[], numerator: number, denominator: number): Generated {
  const clips = new ClipCounter(), samples: number[] = [];
  for (let n = 0; n < input.length; n++) samples.push(clips.apply(input[n] - (input[n - 1] ?? 0) + rdiv(numerator * (samples[n - 1] ?? 0), denominator)));
  return { samples, clipped: clips.count };
}
