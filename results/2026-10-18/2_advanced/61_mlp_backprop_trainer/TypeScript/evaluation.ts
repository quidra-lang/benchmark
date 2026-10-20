import type { Image } from './dataset.ts';
export function real(value: number | null, digits = 4) {
  if (value === null) return '-';
  if (Math.abs(value) >= 1e21) return `${BigInt(value)}.${'0'.repeat(digits)}`;
  const text = value.toFixed(digits);
  return Number(text) === 0 ? (0).toFixed(digits) : text;
}
export function ratio(a: number, b: number) {
  if (!b) return '-';
  const q = Math.floor((20000 * a + b) / (2 * b));
  return `${Math.floor(q / 10000)}.${String(q % 10000).padStart(4, '0')}`;
}
export function prediction(scores: number[]) {
  let best = 0;
  for (let k = 1; k < scores.length; k++) if (scores[k] > scores[best]) best = k;
  return best;
}
export function secondClass(scores: number[], first: number) {
  let best = first === 0 ? 1 : 0;
  for (let k = 0; k < scores.length; k++) if (k !== first && scores[k] > scores[best]) best = k;
  return best;
}
export function confusion(images: Image[], results: { predicted: number }[], classes: number) {
  const matrix: number[][] = Array.from({ length: classes }, () => Array(classes).fill(0));
  for (let i = 0; i < images.length; i++) matrix[images[i].label][results[i].predicted]++;
  return matrix;
}
export function perClass(matrix: number[][]) {
  return matrix.map((values, k) => {
    let support = 0;
    let predicted = 0;
    for (let i = 0; i < matrix.length; i++) {
      support += values[i];
      predicted += matrix[i][k];
    }
    return {
      support,
      predicted,
      precision: ratio(values[k], predicted),
      recall: ratio(values[k], support),
      f1: ratio(2 * values[k], support + predicted),
    };
  });
}
export const levelMaps = (maps: number[][], width: number, height: number) =>
  Array.from({ length: height }, (_, row) =>
    maps.map((map) => map.slice(row * width, (row + 1) * width).join('')).join(' '),
  );
export function imageRows(image: Image, width: number, height: number) {
  const pixels = image.pixels.replace(/[01]/g, (p) => (p === '1' ? '#' : '.'));
  return Array.from({ length: height }, (_, row) => pixels.slice(row * width, (row + 1) * width));
}
