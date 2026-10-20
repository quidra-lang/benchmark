import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
export interface Settings {
  season: number;
  holdout: number;
  horizon: number;
  cvStart: number;
  combo: number;
  alpha: number[];
  beta: number[];
  gamma: number[];
  phi: number[];
  maxAr: number;
  maxLag: number;
  ljungBox: number[];
  outlier: number;
  interval: number[];
}
export interface Inventory {
  onHand: number;
  leadTime: number;
  review: number;
  service: number;
}
export interface Series {
  name: string;
  periods: string[];
  raw: (number | null)[];
  events: Map<string, string>;
  inventory: Inventory;
}
const lines = (name: string) =>
  readFileSync('input/' + name, 'ascii')
    .split('\n')
    .slice(0, -1);
export function readInput() {
  const fields = new Map(
    lines('params.txt').map((line) => {
      const [name, ...values] = line.split(' ');
      return [name, values.map(Number)];
    }),
  );
  const first = (name: string) => fields.get(name)![0];
  const settings: Settings = {
    season: first('season'),
    holdout: first('holdout'),
    horizon: first('horizon'),
    cvStart: first('cv_start'),
    combo: first('combo'),
    alpha: fields.get('alpha')!,
    beta: fields.get('beta')!,
    gamma: fields.get('gamma')!,
    phi: fields.get('phi')!,
    maxAr: first('max_ar'),
    maxLag: first('max_lag'),
    ljungBox: fields.get('ljung_box')!,
    outlier: first('outlier'),
    interval: fields.get('interval')!,
  };
  const series: Series[] = [];
  for (const line of lines('series.csv').slice(1)) {
    const [name, period, value] = line.split(',');
    if (series.at(-1)?.name !== name) {
      series.push({
        name,
        periods: [],
        raw: [],
        events: new Map(),
        inventory: { onHand: 0, leadTime: 0, review: 0, service: 0 },
      });
    }
    const item = series[series.length - 1];
    item.periods.push(period);
    item.raw.push(value === 'NA' ? null : Number(value));
  }
  const byName = new Map(series.map((s) => [s.name, s]));
  for (const line of lines('events.csv').slice(1)) {
    const [name, period, kind] = line.split(',');
    byName.get(name)!.events.set(period, kind);
  }
  for (const line of lines('inventory.csv').slice(1)) {
    const [name, onHand, leadTime, review, service] = line.split(',');
    byName.get(name)!.inventory = {
      onHand: Number(onHand),
      leadTime: Number(leadTime),
      review: Number(review),
      service: Number(service),
    };
  }
  return { settings, series };
}
export function nextMonth(period: string) {
  let [year, month] = period.split('-').map(Number);
  if (month === 12) {
    year++;
    month = 1;
  } else month++;
  return String(year).padStart(4, '0') + '-' + String(month).padStart(2, '0');
}
export function real(value: number) {
  if (Math.abs(value) >= 1e21) {
    return (value < 0 ? '-' : '') + BigInt(Math.abs(value)).toString() + '.0000';
  }
  const text = value.toFixed(4);
  return text === '-0.0000' ? '0.0000' : text;
}
export function writeLines(name: string, values: string[]) {
  mkdirSync('output', { recursive: true });
  writeFileSync('output/' + name, values.length ? values.join('\n') + '\n' : '', 'ascii');
}
