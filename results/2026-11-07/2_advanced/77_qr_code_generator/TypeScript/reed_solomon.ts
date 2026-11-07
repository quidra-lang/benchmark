import type { Correction } from './types.ts';

const powers = Array(255), logarithms = Array(256).fill(0);
let element = 1;
for (let i = 0; i < 255; i++) {
  powers[i] = element; logarithms[element] = i;
  element *= 2;
  if (element >= 256) element ^= 0x11d;
}

export const alpha = (exponent: number): number => powers[(exponent % 255 + 255) % 255];
export const multiply = (a: number, b: number): number => a === 0 || b === 0 ? 0 : alpha(logarithms[a] + logarithms[b]);
export const divide = (a: number, b: number): number => a === 0 ? 0 : alpha(logarithms[a] - logarithms[b]);

export function generator(degree: number): number[] {
  let polynomial = [1];
  for (let i = 0; i < degree; i++) {
    const next = Array(polynomial.length + 1).fill(0);
    for (let j = 0; j < polynomial.length; j++) {
      next[j] ^= polynomial[j];
      next[j + 1] ^= multiply(polynomial[j], alpha(i));
    }
    polynomial = next;
  }
  return polynomial;
}

export function encode(data: number[], degree: number): number[] {
  const polynomial = generator(degree), work = data.concat(Array(degree).fill(0));
  for (let i = 0; i < data.length; i++) {
    const coefficient = work[i];
    for (let j = 0; j <= degree; j++) work[i + j] ^= multiply(coefficient, polynomial[j]);
  }
  return work.slice(data.length);
}

export function syndromes(codewords: number[], degree: number): number[] {
  const result = [];
  for (let j = 0; j < degree; j++) {
    let value = 0;
    for (const codeword of codewords) value = multiply(value, alpha(j)) ^ codeword;
    result.push(value);
  }
  return result;
}

function evaluate(coefficients: number[], value: number): number {
  let result = 0;
  for (let i = coefficients.length - 1; i >= 0; i--) result = multiply(result, value) ^ coefficients[i];
  return result;
}

export function correct(received: number[], degree: number): Correction {
  const original = syndromes(received, degree);
  const failure = (): Correction => ({ status: 'failed', syndromes: original, positions: [], codewords: received.slice() });
  if (original.every(value => value === 0)) {
    return { status: 'ok', syndromes: original, positions: [], codewords: received.slice() };
  }
  let locator = [1], previous = [1], length = 0, shift = 1, beta = 1;
  for (let q = 0; q < degree; q++) {
    let delta = original[q];
    for (let i = 1; i <= length; i++) delta ^= multiply(locator[i] || 0, original[q - i]);
    if (delta === 0) { shift++; continue; }
    const saved = locator.slice(), factor = divide(delta, beta);
    while (locator.length < previous.length + shift) locator.push(0);
    for (let i = 0; i < previous.length; i++) locator[i + shift] ^= multiply(factor, previous[i]);
    if (2 * length <= q) {
      length = q + 1 - length; previous = saved; beta = delta; shift = 1;
    } else shift++;
  }
  if (length > Math.floor(degree / 2)) return failure();
  const positions = [];
  for (let i = 0; i < received.length; i++) {
    if (evaluate(locator, alpha(255 - (received.length - 1 - i))) === 0) positions.push(i);
  }
  if (positions.length !== length) return failure();
  const omega = Array(degree).fill(0), derivative = Array(Math.max(0, locator.length - 1)).fill(0);
  for (let i = 0; i < original.length; i++) {
    for (let j = 0; j < locator.length && i + j < degree; j++) omega[i + j] ^= multiply(original[i], locator[j]);
  }
  for (let i = 1; i < locator.length; i += 2) derivative[i - 1] = locator[i];
  const corrected = received.slice();
  for (const position of positions) {
    const x = alpha(received.length - 1 - position), z = alpha(255 - (received.length - 1 - position));
    const denominator = evaluate(derivative, z);
    if (denominator === 0) return failure();
    corrected[position] ^= multiply(x, divide(evaluate(omega, z), denominator));
  }
  if (syndromes(corrected, degree).some(value => value !== 0)) return failure();
  const changed = positions.filter(position => corrected[position] !== received[position]);
  return { status: 'corrected', syndromes: original, positions: changed, codewords: corrected };
}

