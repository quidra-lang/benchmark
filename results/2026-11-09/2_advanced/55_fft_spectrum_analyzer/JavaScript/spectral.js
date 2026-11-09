'use strict';

const { asComplex, dft, packedFFT, magnitude, squared, conjugate, multiply } = require('./fft');

const localMaximum = (values, k) => k > 0 && k + 1 < values.length && values[k] > values[k - 1] && values[k] > values[k + 1];

function interpolate(values, k, logarithmic = true) {
  if (!localMaximum(values, k)) return { position: k, value: values[k] };
  const convert = logarithmic ? Math.log : value => value;
  const alpha = convert(values[k - 1]);
  const beta = convert(values[k]);
  const gamma = convert(values[k + 1]);
  const delta = (alpha - gamma) / (2 * (alpha - 2 * beta + gamma));
  const value = beta - (alpha - gamma) * delta / 4;
  return { position: k + delta, value: logarithmic ? Math.exp(value) : value };
}

function median(values) {
  const ordered = values.slice().sort((a, b) => a - b);
  const middle = Math.floor(ordered.length / 2);
  return ordered.length % 2 === 1 ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2;
}

function amplitudeSpectrum(signal, window) {
  const length = window.values.length;
  const windowed = window.values.map((weight, n) => signal[n] * weight);
  const transformed = dft(asComplex(windowed));
  const amplitude = Array.from({ length: Math.floor(length / 2) + 1 }, (_, k) =>
    (k === 0 || 2 * k === length ? 1 : 2) * magnitude(transformed[k]) / window.s1);
  return { window, windowed, transformed, amplitude };
}

function* segments(signal, window, hop) {
  const length = window.values.length;
  for (let start = 0; start + length <= signal.length; start += hop) {
    const windowed = window.values.map((weight, n) => signal[start + n] * weight);
    yield { start, windowed, transformed: packedFFT(windowed) };
  }
}

function welch(first, second, window, sampleRate, inspect) {
  const length = window.values.length;
  const bins = length / 2 + 1;
  const pxx = Array(bins).fill(0);
  const pyy = Array(bins).fill(0);
  const pxy = Array.from({ length: bins }, () => [0, 0]);
  const secondSegments = segments(second, window, length / 2);
  let count = 0;
  for (const x of segments(first, window, length / 2)) {
    const y = secondSegments.next().value;
    inspect(x);
    inspect(y);
    for (let k = 0; k < bins; k++) {
      pxx[k] += squared(x.transformed[k]);
      pyy[k] += squared(y.transformed[k]);
      const cross = multiply(conjugate(x.transformed[k]), y.transformed[k]);
      pxy[k][0] += cross[0];
      pxy[k][1] += cross[1];
    }
    count++;
  }
  const psd = pxx.map((value, k) => (k === 0 || k === length / 2 ? 1 : 2) * value / (count * sampleRate * window.s2));
  const coherence = pxy.map((value, k) => squared(value) / (pxx[k] * pyy[k]));
  const transfer = pxy.map((value, k) => [value[0] / pxx[k], value[1] / pxx[k]]);
  return { segments: count, psd, coherence, transfer };
}

module.exports = { localMaximum, interpolate, median, amplitudeSpectrum, segments, welch };
