import { writeFileSync } from 'node:fs';
export const sign = (value: number) => (value > 0 ? 1 : -1);
export function fixed(value: number, digits: number) {
  if (Math.abs(value) >= 1e21) {
    return (value < 0 ? '-' : '') + BigInt(Math.abs(value)).toString() + '.' + '0'.repeat(digits);
  }
  const text = value.toFixed(digits);
  return Number(text) === 0 && text.startsWith('-') ? text.slice(1) : text;
}
export const ratio = (a: number, b: number) => (b > 0 ? fixed(a / b, 4) : '-');
export function folds(count: number, k: number) {
  return Array.from({ length: k }, (_, fold) => {
    const train: number[] = [];
    const test: number[] = [];
    for (let i = 0; i < count; i++) (i % k === fold ? test : train).push(i);
    return { train, test };
  });
}
export function binary(labels: number[], values: number[]) {
  let tp = 0;
  let fp = 0;
  let tn = 0;
  let fn = 0;
  for (let i = 0; i < labels.length; i++) {
    if (sign(values[i]) === 1) {
      if (labels[i] === 1) tp++;
      else fp++;
    } else if (labels[i] === -1) tn++;
    else fn++;
  }
  return { tp, fp, tn, fn, correct: tp + tn };
}
export function auc(labels: number[], values: number[]) {
  let sum = 0;
  let positive = 0;
  let negative = 0;
  for (const label of labels) {
    if (label === 1) positive++;
    else negative++;
  }
  for (let i = 0; i < labels.length; i++) {
    if (labels[i] === 1) {
      for (let j = 0; j < labels.length; j++) {
        if (labels[j] === -1) {
          if (values[i] > values[j]) sum++;
          else if (values[i] === values[j]) sum += 0.5;
        }
      }
    }
  }
  return sum / (positive * negative);
}
export function confusion(classes: number[], predictions: number[]) {
  const counts = Array.from({ length: 3 }, () => [0, 0, 0]);
  for (let i = 0; i < classes.length; i++) counts[classes[i] - 1][predictions[i] - 1]++;
  return counts;
}
export function write(path: string, lines: string[]) {
  writeFileSync(path, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
