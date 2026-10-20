'use strict';

const PI = 3.141592653589793;
const rot = angle => [Math.cos(angle), -Math.sin(angle)];
const conjugate = value => [value[0], -value[1]];
const multiply = (a, b) => [a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0]];
const squared = value => value[0] * value[0] + value[1] * value[1];
const magnitude = value => Math.sqrt(squared(value));
const phase = value => Math.atan2(value[1], value[0]);
const isPowerOfTwo = value => (value & (value - 1)) === 0;
const asComplex = (values, length = values.length) => Array.from({ length }, (_, i) => [i < values.length ? values[i] : 0, 0]);

function pow2(minimum) {
  let length = 1;
  while (length < minimum) length *= 2;
  return length;
}

function radix2(input, inverse = false) {
  const values = input.map(value => value.slice());
  const length = values.length;
  const bits = Math.log2(length);
  for (let n = 1; n < length; n++) {
    let original = n;
    let reversed = 0;
    for (let bit = 0; bit < bits; bit++) {
      reversed = 2 * reversed + original % 2;
      original = Math.floor(original / 2);
    }
    if (n < reversed) [values[n], values[reversed]] = [values[reversed], values[n]];
  }
  const twiddles = Array.from({ length: Math.floor(length / 2) }, (_, k) => {
    const value = rot(2 * PI * k / length);
    return inverse ? conjugate(value) : value;
  });
  for (let size = 2; size <= length; size *= 2) {
    for (let block = 0; block < length; block += size) {
      for (let j = 0; j < size / 2; j++) {
        const t = multiply(twiddles[j * (length / size)], values[block + j + size / 2]);
        const u = values[block + j];
        values[block + j] = [u[0] + t[0], u[1] + t[1]];
        values[block + j + size / 2] = [u[0] - t[0], u[1] - t[1]];
      }
    }
  }
  return inverse ? values.map(value => [value[0] / length, value[1] / length]) : values;
}

function bluestein(input) {
  const length = input.length;
  const size = pow2(2 * length - 1);
  const chirp = Array.from({ length }, (_, n) => rot(PI * ((n * n) % (2 * length)) / length));
  const a = asComplex([], size);
  const b = asComplex([], size);
  for (let n = 0; n < length; n++) {
    a[n] = multiply(input[n], chirp[n]);
    b[n] = conjugate(chirp[n]);
    if (n > 0) b[size - n] = conjugate(chirp[n]);
  }
  const first = radix2(a);
  const second = radix2(b);
  const convolution = radix2(first.map((value, k) => multiply(value, second[k])), true);
  return chirp.map((value, k) => multiply(value, convolution[k]));
}

const dft = input => isPowerOfTwo(input.length) ? radix2(input) : bluestein(input);

function idft(input) {
  if (isPowerOfTwo(input.length)) return radix2(input, true);
  return bluestein(input.map(conjugate)).map(value => [value[0] / input.length, -value[1] / input.length]);
}

function packedFFT(values) {
  const length = values.length;
  const half = length / 2;
  const packed = Array.from({ length: half }, (_, j) => [values[2 * j], values[2 * j + 1]]);
  const transformed = radix2(packed);
  return Array.from({ length: half + 1 }, (_, k) => {
    const a = transformed[k % half];
    const b = conjugate(transformed[(half - k) % half]);
    const even = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    const odd = [(a[1] - b[1]) / 2, -(a[0] - b[0]) / 2];
    const term = multiply(rot(2 * PI * k / length), odd);
    return [even[0] + term[0], even[1] + term[1]];
  });
}

function convolution(first, second) {
  const count = first.length + second.length - 1;
  const length = pow2(count);
  const a = radix2(asComplex(first, length));
  const b = radix2(asComplex(second, length));
  return radix2(a.map((value, k) => multiply(value, b[k])), true).slice(0, count).map(value => value[0]);
}

function chirpZ(values, start, step, count, sampleRate) {
  const length = pow2(values.length + count - 1);
  const a = asComplex([], length);
  const b = asComplex([], length);
  for (let n = 0; n < values.length; n++) {
    const shifted = multiply([values[n], 0], rot(2 * PI * start * n / sampleRate));
    a[n] = multiply(shifted, rot(PI * step * (n * n) / sampleRate));
  }
  for (let m = -(values.length - 1); m < count; m++) {
    b[m < 0 ? m + length : m] = conjugate(rot(PI * step * (m * m) / sampleRate));
  }
  const first = radix2(a);
  const second = radix2(b);
  const transformed = radix2(first.map((value, k) => multiply(value, second[k])), true);
  return Array.from({ length: count }, (_, j) => multiply(rot(PI * step * (j * j) / sampleRate), transformed[j]));
}

module.exports = { PI, rot, conjugate, multiply, squared, magnitude, phase, isPowerOfTwo, asComplex,
  pow2, radix2, bluestein, dft, idft, packedFFT, convolution, chirpZ };
