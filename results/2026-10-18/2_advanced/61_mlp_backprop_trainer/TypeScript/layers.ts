import type { Activation } from './dataset.ts';
export interface Layout {
  units: number;
  inputs: number;
  offset: number;
  biasOffset: number;
  end: number;
}
export interface Output {
  scores: number[];
  loss: number;
  errors: number[];
}
export function activate(kind: Activation, z: number) {
  return kind === 'TANH'
    ? Math.tanh(z)
    : kind === 'SIGMOID'
      ? 1 / (1 + Math.exp(-z))
      : z > 0
        ? z
        : 0;
}
export function derivative(kind: Activation, z: number, a: number) {
  return kind === 'TANH' ? 1 - a * a : kind === 'SIGMOID' ? a * (1 - a) : z > 0 ? 1 : 0;
}
export function preactivate(theta: number[], layer: Layout, inputs: number[]) {
  const values: number[] = [];
  for (let j = 0; j < layer.units; j++) {
    let sum = 0;
    for (let i = 0; i < layer.inputs; i++) {
      sum += theta[layer.offset + j * layer.inputs + i] * inputs[i];
    }
    values.push(sum + theta[layer.biasOffset + j]);
  }
  return values;
}
export function propagate(theta: number[], layer: Layout, errors: number[]) {
  const values: number[] = [];
  for (let i = 0; i < layer.inputs; i++) {
    let sum = 0;
    for (let j = 0; j < layer.units; j++) {
      sum += theta[layer.offset + j * layer.inputs + i] * errors[j];
    }
    values.push(sum);
  }
  return values;
}
export function output(kind: 'SOFTMAX' | 'SIGMOID', values: number[], label: number): Output {
  const size = values.length;
  const errors: number[] = [];
  let scores: number[];
  let loss: number;
  if (kind === 'SOFTMAX') {
    let maximum = values[0];
    for (let k = 1; k < size; k++) maximum = Math.max(maximum, values[k]);
    const exponentials = values.map((v) => Math.exp(v - maximum));
    let total = 0;
    for (const value of exponentials) total += value;
    scores = exponentials.map((v) => v / total);
    loss = Math.log(total) - (values[label] - maximum);
    for (let k = 0; k < size; k++) errors.push(scores[k] - (k === label ? 1 : 0));
  } else {
    scores = values.map((v) => activate('SIGMOID', v));
    loss = 0;
    for (let k = 0; k < size; k++) {
      const difference = scores[k] - (k === label ? 1 : 0);
      loss += difference * difference;
      errors.push((2 * difference * scores[k] * (1 - scores[k])) / size);
    }
    loss /= size;
  }
  return { scores, loss, errors };
}
