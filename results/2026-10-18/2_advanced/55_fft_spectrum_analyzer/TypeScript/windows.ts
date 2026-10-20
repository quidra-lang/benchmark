import { PI, add, complex, magnitude, rot, scale } from './fft.ts';

export type WindowName = 'rectangular' | 'hann' | 'hamming' | 'blackman' | 'flattop';
export const windowNames: WindowName[] = ['rectangular', 'hann', 'hamming', 'blackman', 'flattop'];
const coefficients: Record<WindowName, number[]> = {
  rectangular: [1],
  hann: [0.5, 0.5],
  hamming: [0.54, 0.46],
  blackman: [0.42, 0.5, 0.08],
  flattop: [0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368],
};
export function windowName(text: string): WindowName {
  switch (text) {
    case 'rectangular':
    case 'hann':
    case 'hamming':
    case 'blackman':
    case 'flattop':
      return text;
  }
  throw new Error('Invalid window name');
}
export function window(name: WindowName, length: number): number[] {
  return Array.from({ length }, (_, n) => {
    let value = 0;
    coefficients[name].forEach((coefficient, j) => {
      value += (j % 2 ? -1 : 1) * coefficient * Math.cos((2 * PI * j * n) / length);
    });
    return value;
  });
}
export function figures(values: number[], sampleRate: number) {
  let s1 = 0;
  let s2 = 0;
  let scalloping = complex();
  values.forEach((value, n) => {
    s1 += value;
    s2 += value * value;
    scalloping = add(scalloping, scale(rot((PI * n) / values.length), value));
  });
  const enbwBins = (values.length * s2) / (s1 * s1);
  return {
    s1,
    s2,
    coherentGain: s1 / values.length,
    enbwBins,
    enbwHz: (enbwBins * sampleRate) / values.length,
    scallopingDb: -20 * Math.log10(magnitude(scalloping) / s1),
  };
}
