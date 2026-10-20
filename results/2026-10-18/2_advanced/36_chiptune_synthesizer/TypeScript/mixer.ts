import { waveform, clockNoise } from './instruments.ts';
import type { Instrument } from './song_parser.ts';
export interface Oscillator {
  instrument: Instrument | null;
  sounding: boolean;
  phase: number;
  mode: number;
  register: number;
  amplitude: number;
  increment: number;
}
export function generate(
  channels: Oscillator[],
  count: number,
  gain: number,
  mute: number[],
  samples: number[],
  lanes: number[][] | null = null,
): number {
  let clipped = 0;
  for (let i = 0; i < count; i++) {
    let mixed = 0;
    for (let k = 0; k < channels.length; k++) {
      const channel = channels[k];
      let value = 0;
      if (channel.sounding) {
        const instrument = channel.instrument!;
        value =
          (2 * waveform(instrument, channel.phase, channel.mode, channel.register) - 15) *
          channel.amplitude;
        channel.phase += channel.increment;
        if (channel.phase >= 65536) {
          channel.phase -= 65536;
          if (instrument.wave === 'NOISE') {
            channel.register = clockNoise(channel.register, channel.mode);
          }
        }
      }
      if (lanes !== null) lanes[k].push(value);
      if (mute[k] === 0) mixed += value;
    }
    let sample = 128 + Math.floor((gain * mixed) / 4096);
    if (sample < 0 || sample > 255) {
      clipped++;
      sample = Math.min(255, Math.max(0, sample));
    }
    samples.push(sample);
  }
  return clipped;
}
export function fadeOut(samples: number[], length: number): void {
  const count = Math.min(length, samples.length);
  for (let i = samples.length - count; i < samples.length; i++) {
    samples[i] = 128 + Math.floor(((samples[i] - 128) * (samples.length - 1 - i)) / count);
  }
}
