import { readFileSync } from 'node:fs';
import { windowName, type WindowName } from './windows.ts';

export interface Settings {
  mainLength: number;
  mainWindow: WindowName;
  threshold: number;
  peakCount: number;
  fundamental: number;
  search: number;
  welchLength: number;
  welchWindow: WindowName;
  frameLength: number;
  hop: number;
  shadeDb: number;
  spectrogramWindow: WindowName;
  onsetFactor: number;
  pitchLow: number;
  pitchHigh: number;
  bandLow: number;
  bandHigh: number;
  notch: number;
  notchWidth: number;
  envelopeLow: number;
  envelopeHigh: number;
  zoomLow: number;
  zoomHigh: number;
  zoomCount: number;
  fir: number[];
  maxLag: number;
  bands: number[];
  thirdLow: number;
  thirdHigh: number;
  blockLength: number;
}
const lines = (name: string): string[] =>
  readFileSync('input/' + name, 'ascii')
    .split('\n')
    .slice(0, -1);
export function readInput() {
  const signal = lines('signal.csv');
  const [sampleRate, count] = signal[0].split(',').map(Number);
  const channels = signal.slice(1).map((line) => line.split(',').map(Number));
  const rows = lines('params.txt').map((line) => line.split(' ').slice(1));
  const values = (i: number) => rows[i].map(Number);
  const settings: Settings = {
    mainLength: +rows[0][0],
    mainWindow: windowName(rows[1][0]),
    threshold: +rows[2][0],
    peakCount: +rows[3][0],
    fundamental: +rows[4][0],
    search: +rows[4][1],
    welchLength: +rows[5][0],
    welchWindow: windowName(rows[5][1]),
    frameLength: +rows[6][0],
    hop: +rows[6][1],
    shadeDb: +rows[6][2],
    spectrogramWindow: windowName(rows[6][3]),
    onsetFactor: +rows[7][0],
    pitchLow: +rows[8][0],
    pitchHigh: +rows[8][1],
    bandLow: +rows[9][0],
    bandHigh: +rows[9][1],
    notch: +rows[10][0],
    notchWidth: +rows[10][1],
    envelopeLow: +rows[11][0],
    envelopeHigh: +rows[11][1],
    zoomLow: +rows[12][0],
    zoomHigh: +rows[12][1],
    zoomCount: +rows[12][2],
    fir: values(13),
    maxLag: +rows[14][0],
    bands: values(15),
    thirdLow: +rows[16][0],
    thirdHigh: +rows[16][1],
    blockLength: +rows[17][0],
  };
  return {
    sampleRate,
    count,
    first: channels.map((row) => row[0]),
    second: channels.map((row) => row[1]),
    settings,
  };
}
