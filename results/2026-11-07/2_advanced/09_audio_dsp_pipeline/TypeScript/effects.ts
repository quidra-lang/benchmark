import { ClipCounter, floorDiv, rdiv, type Generated } from './signals.ts';
export function gain(input: readonly number[], numerator: number, denominator: number): Generated {
  const clips = new ClipCounter();
  const samples = input.map((value) => clips.apply(rdiv(value * numerator, denominator)));
  return { samples, clipped: clips.count };
}
export function mix(
  inputs: readonly (readonly number[])[],
  weights: number[],
  denominator: number,
): Generated {
  const length = Math.max(...inputs.map((input) => input.length));
  const clips = new ClipCounter();
  const samples: number[] = [];
  for (let i = 0; i < length; i++) {
    let value = 0;
    for (let k = 0; k < inputs.length; k++) value += weights[k] * (inputs[k][i] ?? 0);
    samples.push(clips.apply(rdiv(value, denominator)));
  }
  return { samples, clipped: clips.count };
}
export function delay(input: readonly number[], length: number): number[] {
  return Array<number>(length).fill(0).concat(input);
}
export function echo(
  input: readonly number[],
  delay: number,
  numerator: number,
  denominator: number,
  tail: number,
): Generated {
  const samples = [...input, ...Array<number>(tail).fill(0)];
  const clips = new ClipCounter();
  for (let i = delay; i < samples.length; i++) {
    samples[i] = clips.apply(samples[i] + rdiv(numerator * samples[i - delay], denominator));
  }
  return { samples, clipped: clips.count };
}
export function resample(input: readonly number[], oldRate: number, newRate: number): number[] {
  const length = floorDiv((input.length - 1) * newRate, oldRate) + 1;
  const samples: number[] = [];
  for (let j = 0; j < length; j++) {
    const position = j * oldRate;
    const p = floorDiv(position, newRate);
    const q = position - p * newRate;
    samples.push(q === 0 ? input[p] : input[p] + rdiv((input[p + 1] - input[p]) * q, newRate));
  }
  return samples;
}
export function fade(input: readonly number[], fadeIn: number, fadeOut: number): number[] {
  const samples = [...input];
  for (let i = 0; i < fadeIn; i++) samples[i] = rdiv(samples[i] * i, fadeIn);
  for (let i = input.length - fadeOut; i < input.length; i++) {
    samples[i] = rdiv(samples[i] * (input.length - 1 - i), fadeOut);
  }
  return samples;
}
