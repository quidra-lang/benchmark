const { rdiv, peak } = require('./signals');

function envelope(input, attack, release) {
  const samples = [];
  let level = 0;
  for (const sample of input) {
    const amplitude = Math.min(Math.abs(sample), 32767);
    const coefficient = amplitude > level ? attack : release;
    level += rdiv((amplitude - level) * coefficient, 32768);
    samples.push(level);
  }
  return samples;
}

function normalize(input, target) {
  const sourcePeak = peak(input);
  const samples = sourcePeak === 0 ? input.slice() : input.map(sample => rdiv(sample * target, sourcePeak));
  return { samples, sourcePeak };
}

function gate(input, threshold, hold) {
  const samples = [];
  let lastLarge = -hold - 1;
  let muted = 0;
  for (let index = 0; index < input.length; index += 1) {
    if (Math.abs(input[index]) >= threshold) lastLarge = index;
    const open = index - lastLarge <= hold;
    if (!open) muted += 1;
    samples.push(open ? input[index] : 0);
  }
  return { samples, muted };
}

function compress(input, threshold, ratioNumerator, ratioDenominator, attack, release) {
  const levels = envelope(input, attack, release);
  const samples = [];
  let gain = 32768;
  let minGain = 32768;
  let reduced = 0;
  for (let index = 0; index < input.length; index += 1) {
    const level = levels[index];
    let target = 32768;
    if (level > threshold) {
      const desired = threshold + rdiv((level - threshold) * ratioDenominator, ratioNumerator);
      target = rdiv(desired * 32768, level);
    }
    gain = target < gain ? target : gain + rdiv((target - gain) * release, 32768);
    minGain = Math.min(minGain, gain);
    if (gain < 32768) reduced += 1;
    samples.push(rdiv(input[index] * gain, 32768));
  }
  return { samples, minGain, reduced };
}

module.exports = { envelope, normalize, gate, compress };
