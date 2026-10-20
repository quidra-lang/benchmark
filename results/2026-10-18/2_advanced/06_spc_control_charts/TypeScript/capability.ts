import type { Constants, Sample, Spec } from './dataset.ts';
import type { Group } from './variable_charts.ts';
export function computeCapability(
  groups: Group[],
  samples: Sample[],
  spec: Spec,
  constants: Constants,
) {
  let total = 0;
  let ranges = 0;
  let deviations = 0;
  for (const sample of samples) total += sample.value;
  for (const group of groups) {
    ranges += group.range;
    deviations += group.sd;
  }
  const count = samples.length;
  const mean = total / count;
  const sigmaWithin = ranges / groups.length / constants.d2;
  const sigmaSbar = deviations / groups.length / constants.c4;
  let squares = 0;
  for (const sample of samples) {
    const difference = sample.value - mean;
    squares += difference * difference;
  }
  const sigmaOverall = Math.sqrt(squares / (count - 1));
  const cp = (spec.usl - spec.lsl) / (6 * sigmaWithin);
  const cpu = (spec.usl - mean) / (3 * sigmaWithin);
  const cpl = (mean - spec.lsl) / (3 * sigmaWithin);
  const cpk = Math.min(cpu, cpl);
  const pp = (spec.usl - spec.lsl) / (6 * sigmaOverall);
  const ppu = (spec.usl - mean) / (3 * sigmaOverall);
  const ppl = (mean - spec.lsl) / (3 * sigmaOverall);
  const ppk = Math.min(ppu, ppl);
  const offset = mean - spec.target;
  const cpm =
    (spec.usl - spec.lsl) / (6 * Math.sqrt(sigmaOverall * sigmaOverall + offset * offset));
  const interval = (value: number) => {
    const delta = spec.ci_z * Math.sqrt(1 / (9 * count) + (value * value) / (2 * (count - 1)));
    return [value - delta, value + delta];
  };
  const outOfSpec: (Sample & { side: 'low' | 'high' })[] = [];
  let below = 0;
  let above = 0;
  for (const sample of samples) {
    if (sample.value < spec.lsl) {
      below++;
      outOfSpec.push({ ...sample, side: 'low' });
    } else if (sample.value > spec.usl) {
      above++;
      outOfSpec.push({ ...sample, side: 'high' });
    }
  }
  return {
    mean,
    sigmaWithin,
    sigmaSbar,
    sigmaOverall,
    cp,
    cpu,
    cpl,
    cpk,
    pp,
    ppu,
    ppl,
    ppk,
    cpm,
    cpkCI: interval(cpk),
    ppkCI: interval(ppk),
    below,
    above,
    ppm: (1000000 * (below + above)) / count,
    verdict: cpk >= 1.33 ? 'capable' : cpk >= 1 ? 'marginal' : 'incapable',
    outOfSpec,
  };
}
export function frequencyDistribution(samples: Sample[], spec: Spec) {
  const width = spec.histogram_bin;
  let minimum = spec.lsl;
  let maximum = spec.usl;
  for (const sample of samples) {
    minimum = Math.min(minimum, sample.value);
    maximum = Math.max(maximum, sample.value);
  }
  const low = width * Math.floor(minimum / width);
  const high = width * Math.floor(maximum / width) + width;
  const frequencies: number[] = Array((high - low) / width).fill(0);
  for (const sample of samples) frequencies[Math.floor((sample.value - low) / width)]++;
  const top = Math.max(...frequencies);
  return frequencies.map((frequency, i) => {
    const lower = low + i * width;
    const upper = lower + width - 1;
    const marks: string[] = [];
    for (const [mark, value] of [
      ['lsl', spec.lsl],
      ['target', spec.target],
      ['usl', spec.usl],
    ] satisfies [string, number][]) {
      if (lower <= value && value <= upper) marks.push(mark);
    }
    return {
      lower,
      upper,
      frequency,
      marks,
      barLength: Math.floor((50 * frequency + top - 1) / top),
    };
  });
}
