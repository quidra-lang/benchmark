const fs = require('node:fs');

function floorDiv(numerator, denominator) {
  let n = BigInt(numerator);
  let d = BigInt(denominator);
  if (d < 0n) [n, d] = [-n, -d];
  let quotient = n / d;
  if (n < 0n && n % d !== 0n) quotient -= 1n;
  return Number(quotient);
}

function ceilDiv(numerator, denominator) {
  return -floorDiv(-numerator, denominator);
}

function mod(numerator, denominator) {
  return numerator - denominator * floorDiv(numerator, denominator);
}

function rdiv(numerator, denominator) {
  return floorDiv(2 * numerator + denominator, 2 * denominator);
}

function sat(value) {
  return Math.max(-32768, Math.min(32767, value));
}

class ClipCounter {
  constructor() {
    this.count = 0;
  }

  apply(value) {
    if (value < -32768 || value > 32767) this.count += 1;
    return sat(value);
  }
}

function peak(samples) {
  let maximum = 0;
  for (const sample of samples) maximum = Math.max(maximum, Math.abs(sample));
  return maximum;
}

class Signal {
  constructor(name, rate, samples, origin = 'input', ingredients = []) {
    this.name = name;
    this.rate = rate;
    this.samples = samples;
    this.origin = origin;
    this.ingredients = ingredients;
  }
}

function readSignals(path) {
  const lines = fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
  const signals = [];
  let position = 0;
  while (position < lines.length) {
    const [, name, rateText, lengthText] = lines[position].split(' ');
    position += 1;
    const length = Number(lengthText);
    const samples = [];
    while (samples.length < length) {
      samples.push(...lines[position].split(' ').map(Number));
      position += 1;
    }
    signals.push(new Signal(name, Number(rateText), samples));
  }
  return signals;
}

function formatSignal(signal) {
  const lines = [`SIGNAL ${signal.name} ${signal.rate} ${signal.samples.length}`];
  for (let start = 0; start < signal.samples.length; start += 16) {
    lines.push(signal.samples.slice(start, start + 16).join(' '));
  }
  return lines;
}

function impulse(count, position, amplitude) {
  const samples = Array(count).fill(0);
  samples[position] = amplitude;
  return samples;
}

function step(count, position, amplitude) {
  return Array.from({ length: count }, (_, index) => index >= position ? amplitude : 0);
}

function noise(count, seed) {
  const samples = [];
  let state = seed;
  for (let index = 0; index < count; index += 1) {
    state = mod(48271 * state, 2147483647);
    samples.push(mod(state, 65536) - 32768);
  }
  return samples;
}

module.exports = { floorDiv, ceilDiv, mod, rdiv, sat, ClipCounter, peak, Signal,
  readSignals, formatSignal, impulse, step, noise };
