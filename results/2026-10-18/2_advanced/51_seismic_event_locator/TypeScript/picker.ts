import type { Station, Parameters } from './waveform_io.ts';
import { median } from './magnitude.ts';
export type PickState = 'used' | 'dropped' | 'added' | 'rejected' | 'unassociated';
export interface Pick {
  station: Station;
  sample: number;
  time: number;
  duration: number;
  snr: number;
  amplitude: number;
  clipped: boolean;
  candidate: number | null;
  state: PickState;
  event: number | null;
  residual: number | null;
  firstResidual: number;
  distanceKm: number;
  ml: number | null;
  md: number;
  mlResidual: number;
}
export function detectPicks(station: Station, p: Parameters) {
  const samples = station.samples;
  let sum = 0;
  for (const v of samples) sum += v;
  const mean = Math.floor(sum / samples.length);
  const d = samples.map((v) => v - mean);
  const energy = d.map((v) => v * v);
  const prefix = [0];
  const absolute = d.map(Math.abs);
  for (const e of energy) prefix.push(prefix[prefix.length - 1] + e);
  const picks: Pick[] = [];
  let triggers = 0;
  let shortTriggers = 0;
  let start: number | null = null;
  let maximumRatio = 0;
  const [onP, onQ] = p.triggerOn;
  const [offP, offQ] = p.triggerOff;
  const sw = p.staWindow;
  const lw = p.ltaWindow;
  const finish = (begin: number, end: number) => {
    const duration = end - begin;
    if (duration < p.minDuration) {
      shortTriggers++;
      return;
    }
    let k = begin;
    while (k - 1 >= begin - sw + 1 && energy[k - 1] >= p.noiseLevel) k--;
    let amplitude = 0;
    let clipped = false;
    for (let j = k; j < Math.min(k + p.amplitudeWindow, samples.length); j++) {
      amplitude = Math.max(amplitude, absolute[j]);
      if (Math.abs(samples[j]) >= p.clipLevel) clipped = true;
    }
    const sample = station.start + k;
    picks.push({
      station,
      sample,
      time: sample / 100,
      duration,
      snr: maximumRatio,
      amplitude,
      clipped,
      candidate: null,
      state: 'unassociated',
      event: null,
      residual: null,
      firstResidual: 0,
      distanceKm: 0,
      ml: null,
      md: 0,
      mlResidual: 0,
    });
  };
  for (let i = sw + lw - 1; i < samples.length; i++) {
    const sta = prefix[i + 1] - prefix[i - sw + 1];
    const lta = prefix[i - sw + 1] - prefix[i - sw - lw + 1];
    if (start === null) {
      if (sta * lw * onQ >= onP * lta * sw) {
        start = i;
        maximumRatio = (sta * lw) / (lta * sw);
        triggers++;
      }
    } else if (sta * lw * offQ < offP * lta * sw) {
      finish(start, i);
      start = null;
    } else maximumRatio = Math.max(maximumRatio, (sta * lw) / (lta * sw));
  }
  if (start !== null) finish(start, samples.length);
  return {
    mean,
    noise: median(absolute)!,
    peak: Math.max(...absolute),
    clippedSamples: samples.filter((v) => Math.abs(v) >= p.clipLevel).length,
    triggers,
    shortTriggers,
    picks,
  };
}
