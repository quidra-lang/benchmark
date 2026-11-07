import { peak, rdiv, type Generated } from './signals.ts';
export function envelope(input: readonly number[], attack: number, release: number): number[] {
  const samples: number[] = [];
  let level = 0;
  for (const sample of input) {
    const amplitude = Math.min(Math.abs(sample), 32767);
    const coefficient = amplitude > level ? attack : release;
    level += rdiv((amplitude - level) * coefficient, 32768);
    samples.push(level);
  }
  return samples;
}
export function normalize(input: readonly number[], target: number): Generated {
  const sourcePeak = peak(input);
  return {
    samples:
      sourcePeak === 0 ? [...input] : input.map((sample) => rdiv(sample * target, sourcePeak)),
    sourcePeak,
  };
}
export function gate(input: readonly number[], threshold: number, hold: number): Generated {
  const samples: number[] = [];
  let lastLarge = -hold - 1;
  let muted = 0;
  for (let n = 0; n < input.length; n++) {
    if (Math.abs(input[n]) >= threshold) lastLarge = n;
    const open = n - lastLarge <= hold;
    if (!open) muted++;
    samples.push(open ? input[n] : 0);
  }
  return { samples, muted };
}
export function compress(
  input: readonly number[],
  threshold: number,
  ratioNumerator: number,
  ratioDenominator: number,
  attack: number,
  release: number,
): Generated {
  const levels = envelope(input, attack, release);
  const samples: number[] = [];
  let gain = 32768;
  let minGain = 32768;
  let reduced = 0;
  for (let n = 0; n < input.length; n++) {
    const level = levels[n];
    let target = 32768;
    if (level > threshold) {
      const desired = threshold + rdiv((level - threshold) * ratioDenominator, ratioNumerator);
      target = rdiv(desired * 32768, level);
    }
    gain = target < gain ? target : gain + rdiv((target - gain) * release, 32768);
    minGain = Math.min(minGain, gain);
    if (gain < 32768) reduced++;
    samples.push(rdiv(input[n] * gain, 32768));
  }
  return { samples, minGain, reduced };
}
