import { readFileSync } from 'node:fs';

const PITCHES = ['C-', 'C#', 'D-', 'D#', 'E-', 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-'];
export const noteNumber = (text: string): number =>
  12 * Number(text[2]) + PITCHES.indexOf(text.slice(0, 2));
export const noteName = (note: number): string => PITCHES[note % 12] + Math.floor(note / 12);
export type EffectName =
  | '0'
  | '1'
  | '2'
  | '3'
  | '4'
  | '5'
  | '6'
  | '7'
  | 'A'
  | 'B'
  | 'C'
  | 'D'
  | 'E1'
  | 'E2'
  | 'E9'
  | 'EA'
  | 'EB'
  | 'EC'
  | 'ED'
  | 'EE'
  | 'F'
  | 'P'
  | 'Q'
  | 'R'
  | 'V';
export const EFFECTS: EffectName[] = [
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  'A',
  'B',
  'C',
  'D',
  'E1',
  'E2',
  'E9',
  'EA',
  'EB',
  'EC',
  'ED',
  'EE',
  'F',
  'P',
  'Q',
  'R',
  'V',
];
export interface Effect {
  text: string;
  name: EffectName;
  argument: number;
  x: number;
  y: number;
}
export interface Cell {
  note: number | 'OFF' | null;
  instrument: number | null;
  volume: number | null;
  effect: Effect | null;
}
export type Waveform = 'PULSE' | 'TRIANGLE' | 'SAW' | 'NOISE' | 'TABLE';
export interface Instrument {
  number: number;
  name: string;
  wave: Waveform;
  mode: number;
  table: number[];
  envelope: [number, number, number, number];
  vibrato: [number, number, number] | null;
  arpeggio: number[] | null;
  sweep: number;
}
export interface Song {
  title: string;
  rate: number;
  speed: number;
  tempo: number;
  gain: number;
  instruments: Map<number, Instrument>;
  patterns: Map<number, Cell[][]>;
  order: number[];
}
export interface Settings {
  maximum: number;
  loops: number;
  fade: number;
  mute: number[];
  window: { start: number; length: number; width: number; height: number; scope: number };
  roll: { start: number; rows: number };
  preview: { note: number; ticks: number; release: number };
  traces: Set<string>;
}
const readLines = (name: string) =>
  readFileSync('input/' + name, 'ascii')
    .split('\n')
    .slice(0, -1);

export function parseCell(text: string): Cell {
  const [note, instrument, volume, effectText] = text.split(' ');
  let effect: Effect | null = null;
  if (effectText !== '...') {
    const extended = effectText[0] === 'E';
    effect = {
      text: effectText,
      name: EFFECTS.find((name) => name === (extended ? effectText.slice(0, 2) : effectText[0]))!,
      argument: parseInt(extended ? effectText[2] : effectText.slice(1), 16),
      x: parseInt(effectText[1], 16),
      y: parseInt(effectText[2], 16),
    };
  }
  return {
    note: note === '...' ? null : note === 'OFF' ? 'OFF' : noteNumber(note),
    instrument: instrument === '..' ? null : parseInt(instrument, 16),
    volume: volume === '.' ? null : parseInt(volume, 16),
    effect,
  };
}

export function readSong(): { song: Song; settings: Settings } {
  const lines = readLines('song.txt').filter((line) => line !== '' && !line.startsWith('#'));
  const value = (index: number) => Number(lines[index].split(' ')[1]);
  const song: Song = {
    title: lines[0].slice(6),
    rate: value(1),
    speed: value(2),
    tempo: value(3),
    gain: value(4),
    instruments: new Map(),
    patterns: new Map(),
    order: [],
  };
  for (let i = 5; i < lines.length; i++) {
    const words = lines[i].split(' ');
    if (words[0] === 'ORDER') song.order = words.slice(1).map((v) => parseInt(v, 16));
    else if (words[0] === 'INSTRUMENT') {
      const instrument: Instrument = {
        number: parseInt(words[1], 16),
        name: words[2],
        wave: 'TRIANGLE',
        mode: 0,
        table: [],
        envelope: [0, 0, 0, 0],
        vibrato: null,
        arpeggio: null,
        sweep: 0,
      };
      while (lines[++i] !== 'END') {
        const [name, ...attributes] = lines[i].split(' ');
        const numbers = attributes.map(Number);
        switch (name) {
          case 'WAVE': {
            const wave = attributes[0];
            if (
              wave !== 'PULSE' &&
              wave !== 'TRIANGLE' &&
              wave !== 'SAW' &&
              wave !== 'NOISE' &&
              wave !== 'TABLE'
            ) {
              throw new Error('Unknown waveform');
            }
            instrument.wave = wave;
            if (wave === 'PULSE') instrument.mode = [12, 25, 50, 75].indexOf(Number(attributes[1]));
            if (wave === 'NOISE') instrument.mode = Number(attributes[1] === 'SHORT');
            if (wave === 'TABLE') instrument.table = [...attributes[1]].map((v) => parseInt(v, 16));
            break;
          }
          case 'ENVELOPE':
            instrument.envelope = [numbers[0], numbers[1], numbers[2], numbers[3]];
            break;
          case 'VIBRATO':
            instrument.vibrato = [numbers[0], numbers[1], numbers[2]];
            break;
          case 'ARPEGGIO':
            instrument.arpeggio = numbers;
            break;
          case 'SWEEP':
            instrument.sweep = numbers[0];
            break;
        }
      }
      song.instruments.set(instrument.number, instrument);
    } else {
      const number = parseInt(words[1], 16);
      const rows = Array.from({ length: 64 }, () =>
        Array.from({ length: 4 }, () => parseCell('... .. . ...')),
      );
      while (lines[++i] !== 'END') {
        rows[parseInt(lines[i].slice(0, 2), 16)] = lines[i].slice(3).split(' | ').map(parseCell);
      }
      song.patterns.set(number, rows);
    }
  }
  const params = readLines('params.txt').map((line) => line.split(' '));
  const [start, length, width, height, scope] = params[4].slice(1).map(Number);
  const settings: Settings = {
    maximum: Number(params[0][1]),
    loops: Number(params[1][1]),
    fade: Number(params[2][1]),
    mute: params[3].slice(1).map(Number),
    window: { start, length, width, height, scope },
    roll: { start: Number(params[5][1]), rows: Number(params[5][2]) },
    preview: {
      note: noteNumber(params[6][1]),
      ticks: Number(params[6][2]),
      release: Number(params[6][3]),
    },
    traces: new Set(params.slice(7).map((w) => parseInt(w[1], 16) + ',' + parseInt(w[2], 16))),
  };
  return { song, settings };
}
