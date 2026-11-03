import { readFileSync } from 'node:fs';

export interface Station {
  code: string;
  name: string;
}
export interface Constituent {
  name: string;
  speed: number;
}
export interface Observation {
  time: number;
  value: number | null;
  milli: number | null;
}
export interface NumericRow {
  time: number;
  value: number;
  milli: number;
}
export interface SpikeSettings {
  window: number;
  count: number;
  factor: number;
  minimum: number;
}
export interface Parameters {
  epoch: number;
  stations: Station[];
  reference: string;
  flatRun: number;
  spike: SpikeSettings;
  rayleigh: number;
  snrMin: number;
  topResiduals: number;
  surge: { threshold: number; hours: number };
  start: number;
  hours: number;
  grid: number;
  minRange: number;
  correlationLag: number;
  plot: { code: string; hours: number; top: number; bottom: number; step: number };
}
const lines = (path: string): string[] => readFileSync(path, 'ascii').trimEnd().split('\n');
const absoluteMinute = (value: string): number =>
  Date.parse(value.replace(' ', 'T') + ':00Z') / 60000;
export const datetime = (epoch: number, minute: number): string =>
  new Date((epoch + minute) * 60000).toISOString().slice(0, 16).replace('T', ' ');
export const hourDatetime = (epoch: number, hour: number): string => datetime(epoch, hour * 60);
export const date = (epoch: number, day: number): string =>
  datetime(epoch, day * 1440).slice(0, 10);
function readParameters(): Parameters {
  const source = lines('input/params.txt');
  const epoch = absoluteMinute(source[0].slice(6));
  const stations: Station[] = [];
  let i = 1;
  while (source[i].startsWith('station ')) {
    stations.push({ code: source[i].slice(8, 11), name: source[i].slice(12) });
    i++;
  }
  const next = (): string[] => source[i++].split(' ');
  const reference = next()[1];
  const flatRun = Number(next()[1]);
  const s = next();
  const spike = {
    window: Number(s[1]),
    count: Number(s[2]),
    factor: Number(s[3]),
    minimum: Number(s[4]),
  };
  const rayleigh = Number(next()[1]);
  const snrMin = Number(next()[1]);
  const topResiduals = Number(next()[1]);
  const surgeRow = next();
  const surge = { threshold: Number(surgeRow[1]), hours: Number(surgeRow[2]) };
  const prediction = next();
  const start = (absoluteMinute(prediction[1] + ' ' + prediction[2]) - epoch) / 60;
  const hours = Number(prediction[3]);
  const grid = Number(next()[1]);
  const minRange = Number(next()[1]);
  const correlationLag = Number(next()[1]);
  const plotRow = next();
  const plot = {
    code: plotRow[1],
    hours: Number(plotRow[2]),
    top: Number(plotRow[3]),
    bottom: Number(plotRow[4]),
    step: Number(plotRow[5]),
  };
  return {
    epoch,
    stations,
    reference,
    flatRun,
    spike,
    rayleigh,
    snrMin,
    topResiduals,
    surge,
    start,
    hours,
    grid,
    minRange,
    correlationLag,
    plot,
  };
}
export function readAll(): {
  params: Parameters;
  constituents: Constituent[];
  observations: Map<string, Observation[]>;
} {
  const params = readParameters();
  const rows = lines('input/constituents.txt');
  const constituents = rows.slice(1, Number(rows[0]) + 1).map((line) => {
    const [name, speed] = line.split(' ');
    return { name, speed: Number(speed) };
  });
  const observations = new Map<string, Observation[]>(params.stations.map((s) => [s.code, []]));
  for (const line of lines('input/observations.csv').slice(1)) {
    const [code, time, level] = line.split(',');
    observations.get(code)!.push({
      time: (absoluteMinute(time) - params.epoch) / 60,
      value: level === 'NA' ? null : Number(level),
      milli: level === 'NA' ? null : Number(level.replace('.', '')),
    });
  }
  return { params, constituents, observations };
}
