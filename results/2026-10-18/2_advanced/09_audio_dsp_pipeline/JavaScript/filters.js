const { floorDiv, rdiv, ClipCounter } = require('./signals');

function fir(input, divisor, taps) {
  const samples = [];
  const clips = new ClipCounter();
  for (let index = 0; index < input.length; index += 1) {
    let value = 0;
    for (let tap = 0; tap < taps.length; tap += 1) value += taps[tap] * (input[index - tap] ?? 0);
    samples.push(clips.apply(floorDiv(value, divisor)));
  }
  return { samples, clipped: clips.count };
}

function biquad(input, coefficients) {
  const clips = new ClipCounter();
  let samples = input;
  for (let start = 0; start < coefficients.length; start += 5) {
    const [b0, b1, b2, a1, a2] = coefficients.slice(start, start + 5);
    const output = [];
    for (let index = 0; index < samples.length; index += 1) {
      const value = b0 * samples[index] + b1 * (samples[index - 1] ?? 0) + b2 * (samples[index - 2] ?? 0)
        - a1 * (output[index - 1] ?? 0) - a2 * (output[index - 2] ?? 0);
      output.push(clips.apply(floorDiv(value, 16384)));
    }
    samples = output;
  }
  return { samples, sections: floorDiv(coefficients.length, 5), clipped: clips.count };
}

function movingAverage(input, width) {
  const samples = [];
  let sum = 0;
  for (let index = 0; index < input.length; index += 1) {
    sum += input[index];
    if (index >= width) sum -= input[index - width];
    samples.push(rdiv(sum, width));
  }
  return samples;
}

function dcBlock(input, numerator, denominator) {
  const samples = [];
  const clips = new ClipCounter();
  for (let index = 0; index < input.length; index += 1) {
    const value = input[index] - (input[index - 1] ?? 0) + rdiv(numerator * (samples[index - 1] ?? 0), denominator);
    samples.push(clips.apply(value));
  }
  return { samples, clipped: clips.count };
}

module.exports = { fir, biquad, movingAverage, dcBlock };
