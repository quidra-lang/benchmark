'use strict';

const { PI, rot, magnitude } = require('./fft');
const coefficients = {
  rectangular: [1], hann: [0.5, 0.5], hamming: [0.54, 0.46], blackman: [0.42, 0.5, 0.08],
  flattop: [0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368]
};

function makeWindow(name, length, sampleRate) {
  const values = Array.from({ length }, (_, n) => {
    let total = 0;
    for (let j = 0; j < coefficients[name].length; j++) {
      total += (j % 2 === 0 ? 1 : -1) * coefficients[name][j] * Math.cos(2 * PI * j * n / length);
    }
    return total;
  });
  let s1 = 0;
  let s2 = 0;
  const halfBin = [0, 0];
  for (let n = 0; n < length; n++) {
    s1 += values[n];
    s2 += values[n] * values[n];
    const rotation = rot(PI * n / length);
    halfBin[0] += values[n] * rotation[0];
    halfBin[1] += values[n] * rotation[1];
  }
  const coherentGain = s1 / length;
  const enbwBins = length * s2 / (s1 * s1);
  return { name, values, s1, s2, coherentGain, enbwBins, enbwHz: enbwBins * sampleRate / length,
    scallopingDb: -20 * Math.log10(magnitude(halfBin) / s1) };
}

module.exports = { names: Object.keys(coefficients), makeWindow };
