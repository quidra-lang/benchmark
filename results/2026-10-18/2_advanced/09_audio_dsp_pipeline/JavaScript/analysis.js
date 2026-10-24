const { floorDiv, peak } = require('./signals');

function isqrt(value) {
  const n = BigInt(value);
  if (n < 2n) return Number(n);
  let estimate = n;
  let next = (estimate + 1n) / 2n;
  while (next < estimate) {
    estimate = next;
    next = (estimate + n / estimate) / 2n;
  }
  return Number(estimate);
}

function energy(samples) {
  let value = 0;
  for (const sample of samples) value += sample * sample;
  return value;
}

function rms(samples) {
  return isqrt(floorDiv(energy(samples), samples.length));
}

function zeroCrossings(samples) {
  let count = 0;
  for (let index = 1; index < samples.length; index += 1) {
    if ((samples[index - 1] < 0) !== (samples[index] < 0)) count += 1;
  }
  return count;
}

function clipped(samples) {
  let count = 0;
  for (const sample of samples) if (sample === -32768 || sample === 32767) count += 1;
  return count;
}

function measure(samples) {
  let sum = 0;
  for (const sample of samples) sum += sample;
  const power = energy(samples);
  return { peak: peak(samples), sum, energy: power, rms: isqrt(floorDiv(power, samples.length)),
    zero_crossings: zeroCrossings(samples), clipped: clipped(samples) };
}

function crest(samples, measurements = measure(samples)) {
  if (measurements.energy === 0) return 'none';
  const numerator = BigInt(measurements.peak * measurements.peak * samples.length);
  const denominator = BigInt(measurements.energy);
  let first = numerator;
  let second = denominator;
  while (second !== 0n) [first, second] = [second, first % second];
  return `${numerator / first}/${denominator / first}`;
}

function autocorrelation(samples, lag) {
  let value = 0;
  for (let index = 0; index < samples.length - lag; index += 1) value += samples[index] * samples[index + lag];
  return value;
}

function pitchLag(samples, low, high) {
  let bestLag = low;
  let bestValue = autocorrelation(samples, low);
  for (let lag = low + 1; lag <= high; lag += 1) {
    const value = autocorrelation(samples, lag);
    if (value > bestValue) {
      bestLag = lag;
      bestValue = value;
    }
  }
  return bestValue > 0 ? bestLag : null;
}

module.exports = { isqrt, energy, rms, zeroCrossings, clipped, measure, crest, autocorrelation, pitchLag };
