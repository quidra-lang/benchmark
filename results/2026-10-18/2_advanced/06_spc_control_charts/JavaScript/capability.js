'use strict';

function confidenceInterval(value, count, coefficient) {
  const delta = coefficient * Math.sqrt(1 / (9 * count) + value * value / (2 * (count - 1)));
  return [value - delta, value + delta];
}

function computeCapability(groups, samples, spec, constants) {
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
  const sigmaWithin = (ranges / groups.length) / constants.d2;
  const sigmaSbar = (deviations / groups.length) / constants.c4;
  let squaredDeviations = 0;
  for (const sample of samples) {
    const difference = sample.value - mean;
    squaredDeviations += difference * difference;
  }
  const sigmaOverall = Math.sqrt(squaredDeviations / (count - 1));
  const cp = (spec.usl - spec.lsl) / (6 * sigmaWithin);
  const cpu = (spec.usl - mean) / (3 * sigmaWithin);
  const cpl = (mean - spec.lsl) / (3 * sigmaWithin);
  const cpk = Math.min(cpu, cpl);
  const pp = (spec.usl - spec.lsl) / (6 * sigmaOverall);
  const ppu = (spec.usl - mean) / (3 * sigmaOverall);
  const ppl = (mean - spec.lsl) / (3 * sigmaOverall);
  const ppk = Math.min(ppu, ppl);
  const offset = mean - spec.target;
  const cpm = (spec.usl - spec.lsl) / (6 * Math.sqrt(sigmaOverall * sigmaOverall + offset * offset));
  let below = 0;
  let above = 0;
  const outOfSpec = [];
  for (const sample of samples) {
    if (sample.value < spec.lsl) {
      below++;
      outOfSpec.push({...sample, side: 'low'});
    } else if (sample.value > spec.usl) {
      above++;
      outOfSpec.push({...sample, side: 'high'});
    }
  }
  const ppm = (1000000 * (below + above)) / count;
  const verdict = cpk >= 1.33 ? 'capable' : cpk >= 1.00 ? 'marginal' : 'incapable';
  return {mean, sigmaWithin, sigmaSbar, sigmaOverall, cp, cpu, cpl, cpk, pp, ppu, ppl, ppk, cpm,
    cpkCI: confidenceInterval(cpk, count, spec.ci_z),
    ppkCI: confidenceInterval(ppk, count, spec.ci_z), below, above, ppm, verdict, outOfSpec};
}

function frequencyDistribution(samples, spec) {
  const width = spec.histogram_bin;
  let minimum = spec.lsl;
  let maximum = spec.usl;
  for (const sample of samples) {
    minimum = Math.min(minimum, sample.value);
    maximum = Math.max(maximum, sample.value);
  }
  const low = width * Math.floor(minimum / width);
  const high = width * Math.floor(maximum / width) + width;
  const frequencies = Array((high - low) / width).fill(0);
  for (const sample of samples) frequencies[Math.floor((sample.value - low) / width)]++;
  let top = 0;
  for (const frequency of frequencies) top = Math.max(top, frequency);
  return frequencies.map((frequency, index) => {
    const lower = low + index * width;
    const upper = lower + width - 1;
    const marks = [];
    for (const [mark, value] of [['lsl', spec.lsl], ['target', spec.target], ['usl', spec.usl]]) {
      if (value >= lower && value <= upper) marks.push(mark);
    }
    return {lower, upper, frequency, marks, barLength: Math.floor((50 * frequency + top - 1) / top)};
  });
}

module.exports = {computeCapability, frequencyDistribution};
