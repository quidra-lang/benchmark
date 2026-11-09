const { floorDiv, rdiv, ClipCounter } = require('./signals');

function gain(input, numerator, denominator) {
  const clips = new ClipCounter();
  const samples = input.map(value => clips.apply(rdiv(value * numerator, denominator)));
  return { samples, clipped: clips.count };
}

function mix(inputs, weights, denominator) {
  const length = Math.max(...inputs.map(input => input.length));
  const clips = new ClipCounter();
  const samples = [];
  for (let index = 0; index < length; index += 1) {
    let value = 0;
    for (let source = 0; source < inputs.length; source += 1) value += weights[source] * (inputs[source][index] ?? 0);
    samples.push(clips.apply(rdiv(value, denominator)));
  }
  return { samples, clipped: clips.count };
}

function delay(input, length) {
  return Array(length).fill(0).concat(input);
}

function echo(input, delayLength, numerator, denominator, tail) {
  const samples = input.concat(Array(tail).fill(0));
  const clips = new ClipCounter();
  for (let index = delayLength; index < samples.length; index += 1) {
    samples[index] = clips.apply(samples[index] + rdiv(numerator * samples[index - delayLength], denominator));
  }
  return { samples, clipped: clips.count };
}

function resample(input, oldRate, newRate) {
  const length = floorDiv((input.length - 1) * newRate, oldRate) + 1;
  const samples = [];
  for (let index = 0; index < length; index += 1) {
    const position = index * oldRate;
    const first = floorDiv(position, newRate);
    const remainder = position - first * newRate;
    samples.push(remainder === 0 ? input[first]
      : input[first] + rdiv((input[first + 1] - input[first]) * remainder, newRate));
  }
  return samples;
}

function fade(input, fadeIn, fadeOut) {
  const samples = input.slice();
  for (let index = 0; index < fadeIn; index += 1) samples[index] = rdiv(samples[index] * index, fadeIn);
  for (let index = input.length - fadeOut; index < input.length; index += 1) {
    samples[index] = rdiv(samples[index] * (input.length - 1 - index), fadeOut);
  }
  return samples;
}

module.exports = { gain, mix, delay, echo, resample, fade };
