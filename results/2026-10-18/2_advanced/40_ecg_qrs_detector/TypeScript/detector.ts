import type { Signals } from './filters.ts';
import { div } from './report.ts';

export type PeakClass = 'qrs' | 'searchback' | 'twave' | 'refractory' | 'noise';
export interface Peak {
  time: number;
  r: number;
  integrated: number;
  filtered: number;
  slope: number;
  thresholdI: number;
  thresholdF: number;
  kind: PeakClass;
}
export interface Levels {
  spki: number;
  npki: number;
  spkf: number;
  npkf: number;
}
export function findPeaks(signals: Signals): Peak[] {
  const { bandpass: f, derivative: d, integrated: m } = signals;
  const peaks: Peak[] = [];
  for (let n = 0; n < m.length; n++) {
    if (m[n] <= 0) continue;
    let maximum = true;
    for (let j = Math.max(0, n - 20); j < n; j++) {
      if (m[j] >= m[n]) {
        maximum = false;
        break;
      }
    }
    if (!maximum) continue;
    for (let j = n + 1; j <= Math.min(m.length - 1, n + 20); j++) {
      if (m[j] > m[n]) {
        maximum = false;
        break;
      }
    }
    if (!maximum) continue;
    let r = Math.max(0, n - 30);
    let slope = 0;
    for (let j = r + 1; j <= n; j++) if (Math.abs(f[j]) > Math.abs(f[r])) r = j;
    for (let j = Math.max(0, n - 29); j <= n; j++) slope = Math.max(slope, Math.abs(d[j]));
    peaks.push({
      time: n,
      r,
      integrated: m[n],
      filtered: Math.abs(f[r]),
      slope,
      thresholdI: 0,
      thresholdF: 0,
      kind: 'noise',
    });
  }
  return peaks;
}
export function initialLevels(signals: Signals): Levels {
  const m = signals.integrated.slice(0, 400);
  const f = signals.bandpass.slice(0, 400).map(Math.abs);
  return {
    spki: div(Math.max(...m), 3),
    npki: div(
      m.reduce((a, b) => a + b, 0),
      800,
    ),
    spkf: div(Math.max(...f), 3),
    npkf: div(
      f.reduce((a, b) => a + b, 0),
      800,
    ),
  };
}
export function qrsWidth(filtered: number[], r: number): number {
  let first = r;
  let last = r;
  for (let j = Math.max(0, r - 25); j <= Math.min(filtered.length - 1, r + 25); j++) {
    if (4 * Math.abs(filtered[j]) >= Math.abs(filtered[r])) {
      first = Math.min(first, j);
      last = Math.max(last, j);
    }
  }
  return 5 * (last - first + 1);
}
