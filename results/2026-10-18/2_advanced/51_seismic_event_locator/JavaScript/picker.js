'use strict';

const { median } = require('./magnitude');

function detectPicks(station, params) {
  const samples = station.samples;
  let total = 0;
  for (const value of samples) total += value;
  const mean = Math.floor(total / samples.length);
  const deviations = samples.map(value => value - mean);
  const energy = deviations.map(value => value * value);
  const prefix = [0];
  for (const value of energy) prefix.push(prefix.at(-1) + value);
  const absolute = deviations.map(value => Math.abs(value));
  const clippedSamples = samples.filter(value => Math.abs(value) >= params.clipLevel).length;
  const picks = [];
  let triggers = 0;
  let shortTriggers = 0;
  let start = null;
  let maximumRatio = 0;
  const [onNumerator, onDenominator] = params.triggerOn;
  const [offNumerator, offDenominator] = params.triggerOff;
  const sw = params.staWindow;
  const lw = params.ltaWindow;
  function finish(end) {
    const duration = end - start;
    if (duration < params.minDuration) {
      shortTriggers++;
      return;
    }
    let position = start;
    while (position - 1 >= start - sw + 1 && energy[position - 1] >= params.noiseLevel) position--;
    let amplitude = 0;
    let clipped = false;
    for (let j = position; j < Math.min(position + params.amplitudeWindow, samples.length); j++) {
      amplitude = Math.max(amplitude, absolute[j]);
      if (Math.abs(samples[j]) >= params.clipLevel) clipped = true;
    }
    const sample = station.start + position;
    picks.push({ station, sample, time: sample / 100, duration, snr: maximumRatio, amplitude,
      clipped, candidate: null, state: 'unassociated', event: null, residual: null });
  }
  for (let i = sw + lw - 1; i < samples.length; i++) {
    const sta = prefix[i + 1] - prefix[i - sw + 1];
    const lta = prefix[i - sw + 1] - prefix[i - sw - lw + 1];
    if (start === null) {
      if (sta * lw * onDenominator >= onNumerator * lta * sw) {
        start = i;
        maximumRatio = (sta * lw) / (lta * sw);
        triggers++;
      }
    } else if (sta * lw * offDenominator < offNumerator * lta * sw) {
      finish(i);
      start = null;
    } else {
      maximumRatio = Math.max(maximumRatio, (sta * lw) / (lta * sw));
    }
  }
  if (start !== null) finish(samples.length);
  return { mean, noise: median(absolute), peak: Math.max(...absolute), clippedSamples, triggers, shortTriggers, picks };
}

module.exports = { detectPicks };
