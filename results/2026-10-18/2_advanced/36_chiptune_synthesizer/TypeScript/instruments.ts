import type { Instrument } from './song_parser.ts';
const T = [26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388];
const S = [0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
  255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24];

export function frequency(note: number): number {
  const octave = Math.floor(note / 12);
  return octave >= 4 ? T[note % 12] * 2 ** (octave - 4) : Math.floor(T[note % 12] / 2 ** (4 - octave));
}
export const transpose = (value: number, semitones: number): number =>
  Math.floor(value * T[semitones % 12] / T[0]) * 2 ** Math.floor(semitones / 12);
export function oscillation(position: number, depth: number, divisor: number): number {
  const value = Math.floor(S[position % 32] * depth / divisor);
  return position < 32 ? value : -value;
}
export interface EnvelopeState { age: number; keyedOff: boolean; offAge: number; offEnvelope: number }
export function envelope(instrument: Instrument, state: EnvelopeState): number {
  const [attack, decay, sustain, release] = instrument.envelope, age = state.age;
  if (state.keyedOff) {
    const elapsed = age - state.offAge;
    return elapsed < release ? Math.floor(state.offEnvelope * (release - 1 - elapsed) / release) : 0;
  }
  if (age < attack) return Math.floor(15 * (age + 1) / attack);
  if (age < attack + decay) return 15 - Math.floor((15 - sustain) * (age - attack + 1) / decay);
  return sustain;
}
export function waveform(instrument: Instrument, phase: number, mode: number, register: number): number {
  switch (instrument.wave) {
    case 'PULSE': return Math.floor(phase / 8192) < [1, 2, 4, 6][mode] ? 15 : 0;
    case 'TRIANGLE': { const j = Math.floor(phase / 2048); return j < 16 ? 15 - j : j - 16; }
    case 'SAW': return Math.floor(phase / 4096);
    case 'TABLE': return instrument.table[Math.floor(phase / 2048)];
    case 'NOISE': return register % 2 === 0 ? 15 : 0;
  }
}
export function clockNoise(register: number, mode: number): number {
  const bit = (register & 1) ^ ((register >> (mode === 0 ? 1 : 6)) & 1);
  return Math.floor(register / 2) + bit * 16384;
}
